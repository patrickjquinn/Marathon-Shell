// marathon-webview-runner — Phase 2.1
//
// Per-app WPE WebKit host process. Marathon's compositor speaks Wayland;
// this runner is a Wayland client. Pipeline:
//
//   WebProcess renders → EGLImage → host export_fdo_egl_image callback
//   → eglCreateWaylandBufferFromImageWL → wl_surface_attach + damage +
//   commit → Marathon's compositor adopts the xdg_toplevel.
//
// The EGL-image bridge is the same one Cog uses
// (platform/wayland/cog-view-wl.c). It is much simpler than raw dmabuf
// plumbing — no zwp_linux_dmabuf_v1.create_params traffic on the wire,
// no modifier negotiation, no plane accounting. Mesa etnaviv's
// EGL_WL_create_wayland_buffer_from_image extension does the work
// host-side.
//
// References — see project_wpe_phase_2_validated memory + the report
// the Phase 2.1 research agent produced.

#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include <wayland-client.h>
#include <wayland-egl.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>

#include <wpe/wpe.h>
#include <wpe/fdo.h>
#include <wpe/fdo-egl.h>
#include <wpe/webkit.h>
#include <glib.h>

#include "xdg-shell-client-protocol.h"

namespace {

    // Default surface size for embedded webviews. The QML side resizes by
    // sending xdg_toplevel.set_size — until then we render at this size so
    // the WebProcess has something to draw against.
    constexpr int kDefaultWidth  = 540;
    constexpr int kDefaultHeight = 1140;

    // Singleton glib main loop. WebKit's GLib API drives everything off
    // this — we never spin it manually; let g_main_loop_run park the
    // thread until something exits.
    GMainLoop *gMainLoop = nullptr;

    // EGL function pointers loaded via eglGetProcAddress at startup. The
    // wayland-buffer-from-image extension is core to the Cog pattern.
    using PFNEGLCREATEWAYLANDBUFFERFROMIMAGEWL = struct wl_buffer *(EGLAPIENTRYP)(EGLDisplay,
                                                                                  EGLImageKHR);

    PFNEGLCREATEWAYLANDBUFFERFROMIMAGEWL egl_create_wl_buffer_from_image = nullptr;

    struct Runner {
        // Wayland globals — bound in registry.global handler.
        wl_display    *wlDisplay  = nullptr;
        wl_registry   *registry   = nullptr;
        wl_compositor *compositor = nullptr;
        xdg_wm_base   *xdgWmBase  = nullptr;

        // Surface chain. xdg_toplevel is the window Marathon's
        // compositor adopts.
        wl_surface   *surface     = nullptr;
        xdg_surface  *xdgSurface  = nullptr;
        xdg_toplevel *xdgToplevel = nullptr;
        bool          configured  = false;

        // EGL plumbing. The display is needed for
        // wpe_fdo_initialize_for_egl_display (was passed wl_display
        // wrongly in Phase 2; now corrected). We never make GL calls
        // ourselves — WebKit's WebProcess does — but we need a context
        // bound to convert exported images to wl_buffers.
        EGLDisplay eglDisplay = EGL_NO_DISPLAY;
        EGLContext eglContext = EGL_NO_CONTEXT;
        EGLConfig  eglConfig  = nullptr;

        // WPE state.
        wpe_view_backend_exportable_fdo *exportable = nullptr;
        WebKitWebContext                *webContext = nullptr;
        WebKitWebView                   *webView    = nullptr;

        // Current frame state. We track the image that's on screen so
        // we can release it back to WPE when the buffer's done.
        wpe_fdo_egl_exported_image *pendingImage  = nullptr;
        wl_callback                *frameCallback = nullptr;

        int                         width  = kDefaultWidth;
        int                         height = kDefaultHeight;
    };

    // ---- xdg_wm_base ping ----
    void onWmBasePing(void *, xdg_wm_base *wm, uint32_t serial) {
        xdg_wm_base_pong(wm, serial);
    }
    const xdg_wm_base_listener kWmBaseListener = {onWmBasePing};

    // ---- xdg_surface configure ----
    void onSurfaceConfigure(void *data, xdg_surface *xs, uint32_t serial) {
        auto *r = static_cast<Runner *>(data);
        xdg_surface_ack_configure(xs, serial);
        r->configured = true;
    }
    const xdg_surface_listener kSurfaceListener = {onSurfaceConfigure};

    // ---- xdg_toplevel configure ----
    void onToplevelConfigure(void *data, xdg_toplevel *, int32_t w, int32_t h, wl_array *) {
        auto *r = static_cast<Runner *>(data);
        if (w > 0 && h > 0 && (w != r->width || h != r->height)) {
            r->width  = w;
            r->height = h;
            if (r->exportable) {
                wpe_view_backend_dispatch_set_size(
                    wpe_view_backend_exportable_fdo_get_view_backend(r->exportable),
                    static_cast<uint32_t>(w), static_cast<uint32_t>(h));
            }
        }
    }
    void onToplevelClose(void *, xdg_toplevel *) {
        if (gMainLoop)
            g_main_loop_quit(gMainLoop);
    }
    void onToplevelBounds(void *, xdg_toplevel *, int32_t, int32_t) {
        // Marathon's compositor advertises bounds; we just track what
        // configure tells us, so this is a no-op.
    }
    void onToplevelCapabilities(void *, xdg_toplevel *, wl_array *) {
        // Same — we don't expose minimise/maximise UI.
    }
    const xdg_toplevel_listener kToplevelListener = {
        onToplevelConfigure,
        onToplevelClose,
        onToplevelBounds,
        onToplevelCapabilities,
    };

    // ---- Frame callback: WPE expects dispatch_frame_complete once we've
    // acknowledged the compositor's frame done event. This drives the
    // next render. ----
    void                       onFrameDone(void *data, wl_callback *cb, uint32_t /*time*/);
    const wl_callback_listener kFrameListener = {onFrameDone};

    void                       onFrameDone(void *data, wl_callback *cb, uint32_t) {
        auto *r = static_cast<Runner *>(data);
        if (cb)
            wl_callback_destroy(cb);
        r->frameCallback = nullptr;
        if (r->exportable)
            wpe_view_backend_exportable_fdo_dispatch_frame_complete(r->exportable);
    }

    // ---- Buffer release callback: when the compositor stops using the
    // wl_buffer we built last frame, release the EGLImage back to WPE. ----
    struct PendingBuffer {
        Runner                     *runner;
        wpe_fdo_egl_exported_image *image;
        wl_buffer                  *buffer;
    };

    void onBufferRelease(void *data, wl_buffer *buffer) {
        auto *pb = static_cast<PendingBuffer *>(data);
        if (pb->runner && pb->runner->exportable && pb->image) {
            wpe_view_backend_exportable_fdo_egl_dispatch_release_exported_image(
                pb->runner->exportable, pb->image);
        }
        if (buffer)
            wl_buffer_destroy(buffer);
        delete pb;
    }
    const wl_buffer_listener kBufferListener = {onBufferRelease};

    // ---- Export callback from WPE: an EGLImage just landed. Convert to
    // wl_buffer and present. ----
    void onExportFdoEglImage(void *data, wpe_fdo_egl_exported_image *image) {
        auto *r = static_cast<Runner *>(data);
        if (!image || !r->surface || !egl_create_wl_buffer_from_image) {
            // Drop the image straight back to WPE — it'll wait and try
            // again next frame.
            if (image && r->exportable)
                wpe_view_backend_exportable_fdo_egl_dispatch_release_exported_image(r->exportable,
                                                                                    image);
            return;
        }

        EGLImageKHR egl_image = wpe_fdo_egl_exported_image_get_egl_image(image);
        wl_buffer  *buffer    = egl_create_wl_buffer_from_image(r->eglDisplay, egl_image);
        if (!buffer) {
            g_warning("[marathon-webview-runner] eglCreateWaylandBufferFromImageWL failed; "
                      "EGL error 0x%x",
                      eglGetError());
            wpe_view_backend_exportable_fdo_egl_dispatch_release_exported_image(r->exportable,
                                                                                image);
            return;
        }

        auto *pb = new PendingBuffer{r, image, buffer};
        wl_buffer_add_listener(buffer, &kBufferListener, pb);

        wl_surface_attach(r->surface, buffer, 0, 0);
        wl_surface_damage_buffer(r->surface, 0, 0, r->width, r->height);

        // Frame callback — needed for dispatch_frame_complete.
        if (r->frameCallback)
            wl_callback_destroy(r->frameCallback);
        r->frameCallback = wl_surface_frame(r->surface);
        wl_callback_add_listener(r->frameCallback, &kFrameListener, r);

        wl_surface_commit(r->surface);
    }

    // export_egl_image (raw EGLImageKHR variant) and export_shm_buffer
    // are not used in the EGL exportable path Cog uses; we leave them
    // unimplemented (NULL function pointer) so WPE selects
    // export_fdo_egl_image.
    const wpe_view_backend_exportable_fdo_egl_client kExportableEglClient = {
        nullptr,             // export_egl_image (legacy)
        onExportFdoEglImage, // export_fdo_egl_image
        nullptr,             // export_shm_buffer (sw fallback)
        nullptr,             // _wpe_reserved0
        nullptr,             // _wpe_reserved1
    };

    // ---- Registry bindings ----
    void onRegistryGlobal(void *data, wl_registry *registry, uint32_t name, const char *iface,
                          uint32_t version) {
        auto *r = static_cast<Runner *>(data);
        if (std::strcmp(iface, wl_compositor_interface.name) == 0) {
            r->compositor = static_cast<wl_compositor *>(
                wl_registry_bind(registry, name, &wl_compositor_interface, std::min(version, 4u)));
        } else if (std::strcmp(iface, xdg_wm_base_interface.name) == 0) {
            r->xdgWmBase = static_cast<xdg_wm_base *>(
                wl_registry_bind(registry, name, &xdg_wm_base_interface, std::min(version, 4u)));
            xdg_wm_base_add_listener(r->xdgWmBase, &kWmBaseListener, r);
        }
    }
    void                       onRegistryGlobalRemove(void *, wl_registry *, uint32_t) {}
    const wl_registry_listener kRegistryListener = {onRegistryGlobal, onRegistryGlobalRemove};

    // ---- Signals ----
    void onTerm(int) {
        if (gMainLoop)
            g_main_loop_quit(gMainLoop);
    }

    // ---- Load progress ----
    void onLoadFailed(WebKitWebView *, WebKitLoadEvent, const char *failingURI, GError *error,
                      gpointer) {
        g_warning("[marathon-webview-runner] load failed for %s: %s",
                  failingURI ? failingURI : "(null)",
                  error && error->message ? error->message : "(no message)");
    }
    void onLoadChanged(WebKitWebView *, WebKitLoadEvent event, gpointer) {
        const char *name = "?";
        switch (event) {
            case WEBKIT_LOAD_STARTED: name = "started"; break;
            case WEBKIT_LOAD_REDIRECTED: name = "redirected"; break;
            case WEBKIT_LOAD_COMMITTED: name = "committed"; break;
            case WEBKIT_LOAD_FINISHED: name = "finished"; break;
        }
        g_message("[marathon-webview-runner] load %s", name);
    }

    // ---- EGL bring-up. Pulled out because it's chunky. ----
    bool initEgl(Runner &r) {
        // Mesa exposes eglGetPlatformDisplay with EGL_PLATFORM_WAYLAND_KHR
        // for getting a display tied to our wl_display.
        auto getPlatformDisplay = reinterpret_cast<PFNEGLGETPLATFORMDISPLAYEXTPROC>(
            eglGetProcAddress("eglGetPlatformDisplayEXT"));
        if (getPlatformDisplay)
            r.eglDisplay = getPlatformDisplay(EGL_PLATFORM_WAYLAND_KHR, r.wlDisplay, nullptr);
        if (r.eglDisplay == EGL_NO_DISPLAY)
            r.eglDisplay = eglGetDisplay(reinterpret_cast<EGLNativeDisplayType>(r.wlDisplay));

        if (r.eglDisplay == EGL_NO_DISPLAY) {
            g_critical("[marathon-webview-runner] no EGL display");
            return false;
        }

        EGLint major = 0, minor = 0;
        if (!eglInitialize(r.eglDisplay, &major, &minor)) {
            g_critical("[marathon-webview-runner] eglInitialize failed; error 0x%x", eglGetError());
            return false;
        }
        g_message("[marathon-webview-runner] EGL %d.%d initialised", major, minor);

        if (!eglBindAPI(EGL_OPENGL_ES_API)) {
            g_critical("[marathon-webview-runner] eglBindAPI(GLES) failed");
            return false;
        }

        // Minimal GLES2 config. We never present to this context — it
        // exists solely so WPE can validate the EGL extensions exist.
        const EGLint cfgAttribs[] = {
            EGL_SURFACE_TYPE,
            EGL_WINDOW_BIT,
            EGL_RENDERABLE_TYPE,
            EGL_OPENGL_ES2_BIT,
            EGL_RED_SIZE,
            8,
            EGL_GREEN_SIZE,
            8,
            EGL_BLUE_SIZE,
            8,
            EGL_ALPHA_SIZE,
            8,
            EGL_NONE,
        };
        EGLint nConfigs = 0;
        if (!eglChooseConfig(r.eglDisplay, cfgAttribs, &r.eglConfig, 1, &nConfigs) ||
            nConfigs < 1) {
            g_critical("[marathon-webview-runner] eglChooseConfig failed");
            return false;
        }

        const EGLint ctxAttribs[] = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE};
        r.eglContext = eglCreateContext(r.eglDisplay, r.eglConfig, EGL_NO_CONTEXT, ctxAttribs);
        if (r.eglContext == EGL_NO_CONTEXT) {
            g_critical("[marathon-webview-runner] eglCreateContext failed; error 0x%x",
                       eglGetError());
            return false;
        }

        // Load the wayland-buffer-from-image entrypoint — Mesa's
        // EGL_WL_create_wayland_buffer_from_image extension.
        egl_create_wl_buffer_from_image = reinterpret_cast<PFNEGLCREATEWAYLANDBUFFERFROMIMAGEWL>(
            eglGetProcAddress("eglCreateWaylandBufferFromImageWL"));
        if (!egl_create_wl_buffer_from_image) {
            g_critical("[marathon-webview-runner] missing "
                       "eglCreateWaylandBufferFromImageWL — Mesa "
                       "EGL_WL_create_wayland_buffer_from_image absent. "
                       "EGL extensions: %s",
                       eglQueryString(r.eglDisplay, EGL_EXTENSIONS));
            return false;
        }
        return true;
    }

} // namespace

int main(int argc, char **argv) {
    const char *url = argc > 1 ? argv[1] : "about:blank";

    g_message("[marathon-webview-runner] booting; url=%s", url);

    Runner r;

    r.wlDisplay = wl_display_connect(nullptr);
    if (!r.wlDisplay) {
        g_critical("[marathon-webview-runner] wl_display_connect failed; WAYLAND_DISPLAY=%s",
                   g_getenv("WAYLAND_DISPLAY"));
        return 1;
    }

    r.registry = wl_display_get_registry(r.wlDisplay);
    wl_registry_add_listener(r.registry, &kRegistryListener, &r);
    wl_display_roundtrip(r.wlDisplay);

    if (!r.compositor || !r.xdgWmBase) {
        g_critical("[marathon-webview-runner] missing required globals: "
                   "compositor=%p xdg_wm_base=%p",
                   r.compositor, r.xdgWmBase);
        return 1;
    }

    if (!initEgl(r))
        return 1;

    // EGL must be live before WPE's fdo init — that call wires the
    // engine's image-export machinery against this EGL display.
    wpe_fdo_initialize_for_egl_display(r.eglDisplay);

    // xdg toplevel — Marathon's compositor will adopt this via its
    // xdg_surface receive path (shell/src/wayland/waylandcompositor.cpp).
    r.surface    = wl_compositor_create_surface(r.compositor);
    r.xdgSurface = xdg_wm_base_get_xdg_surface(r.xdgWmBase, r.surface);
    xdg_surface_add_listener(r.xdgSurface, &kSurfaceListener, &r);
    r.xdgToplevel = xdg_surface_get_toplevel(r.xdgSurface);
    xdg_toplevel_add_listener(r.xdgToplevel, &kToplevelListener, &r);

    xdg_toplevel_set_app_id(r.xdgToplevel, "org.marathon.WebView");
    xdg_toplevel_set_title(r.xdgToplevel, url);

    wl_surface_commit(r.surface);
    wl_display_roundtrip(r.wlDisplay); // wait for initial configure

    // Build the exportable + WebKitWebViewBackend wrapper.
    r.exportable = wpe_view_backend_exportable_fdo_egl_create(
        &kExportableEglClient, &r, static_cast<uint32_t>(r.width), static_cast<uint32_t>(r.height));
    if (!r.exportable) {
        g_critical("[marathon-webview-runner] wpe_view_backend_exportable_fdo_egl_create failed");
        return 1;
    }

    WebKitWebViewBackend *wkBackend = webkit_web_view_backend_new(
        wpe_view_backend_exportable_fdo_get_view_backend(r.exportable), nullptr, nullptr);

    r.webContext = webkit_web_context_new();
    r.webView    = WEBKIT_WEB_VIEW(g_object_new(WEBKIT_TYPE_WEB_VIEW, "backend", wkBackend,
                                                "web-context", r.webContext, nullptr));

    g_signal_connect(r.webView, "load-changed", G_CALLBACK(onLoadChanged), nullptr);
    g_signal_connect(r.webView, "load-failed", G_CALLBACK(onLoadFailed), nullptr);

    webkit_web_view_load_uri(r.webView, url);

    gMainLoop = g_main_loop_new(nullptr, FALSE);
    signal(SIGINT, onTerm);
    signal(SIGTERM, onTerm);

    // Wayland pumping. wpe-fdo internally drives WebProcess events via
    // GLib sources; we just need to attach the wl_display fd to the
    // main loop so commits + configure events flow.
    GIOChannel *wlChan = g_io_channel_unix_new(wl_display_get_fd(r.wlDisplay));
    g_io_add_watch(
        wlChan, static_cast<GIOCondition>(G_IO_IN | G_IO_ERR | G_IO_HUP),
        [](GIOChannel *, GIOCondition cond, gpointer ud) -> gboolean {
            auto *rr = static_cast<Runner *>(ud);
            if (cond & (G_IO_ERR | G_IO_HUP)) {
                g_warning("[marathon-webview-runner] wayland fd closed");
                g_main_loop_quit(gMainLoop);
                return G_SOURCE_REMOVE;
            }
            wl_display_dispatch(rr->wlDisplay);
            return G_SOURCE_CONTINUE;
        },
        &r);
    // Flush once at start so the queued requests reach the compositor.
    wl_display_flush(r.wlDisplay);

    // A second GLib source for periodic flush — Wayland needs the
    // client to call wl_display_flush() after any request burst.
    g_timeout_add(
        16,
        [](gpointer ud) -> gboolean {
            auto *rr = static_cast<Runner *>(ud);
            wl_display_flush(rr->wlDisplay);
            return G_SOURCE_CONTINUE;
        },
        &r);

    g_main_loop_run(gMainLoop);

    if (r.frameCallback)
        wl_callback_destroy(r.frameCallback);
    if (r.webView)
        g_object_unref(r.webView);
    if (r.webContext)
        g_object_unref(r.webContext);
    if (r.exportable)
        wpe_view_backend_exportable_fdo_destroy(r.exportable);
    if (r.xdgToplevel)
        xdg_toplevel_destroy(r.xdgToplevel);
    if (r.xdgSurface)
        xdg_surface_destroy(r.xdgSurface);
    if (r.surface)
        wl_surface_destroy(r.surface);
    if (r.eglContext != EGL_NO_CONTEXT)
        eglDestroyContext(r.eglDisplay, r.eglContext);
    if (r.eglDisplay != EGL_NO_DISPLAY)
        eglTerminate(r.eglDisplay);
    if (r.xdgWmBase)
        xdg_wm_base_destroy(r.xdgWmBase);
    if (r.compositor)
        wl_compositor_destroy(r.compositor);
    if (r.registry)
        wl_registry_destroy(r.registry);
    wl_display_disconnect(r.wlDisplay);
    g_main_loop_unref(gMainLoop);
    return 0;
}
