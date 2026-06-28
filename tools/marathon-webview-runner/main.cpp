// marathon-webview-runner — Phase 2.1
//
// Per-app WPE WebKit host process. Marathon's compositor speaks Wayland;
// this runner is a Wayland client. Pipeline:
//
//   WebProcess renders → EGLImage → host export_fdo_egl_image callback
//   → eglExportDMABUFImageMESA (per-plane fd/stride/offset) →
//   zwp_linux_dmabuf_v1.create_params + add + create_immed → wl_buffer
//   → wl_surface_attach + damage + commit → Marathon's compositor
//   adopts the xdg_toplevel.
//
// The dmabuf-export path is the only client-side option on etnaviv:
// EGL_WL_create_wayland_buffer_from_image (Cog's preferred entrypoint)
// is a SERVER-side extension and absent in Mesa's etnaviv client
// driver. Cog gets away with it because its WebProcess connects to
// Cog's own nested compositor — Cog is a Wayland server in that
// direction. The runner is a pure Wayland client to Marathon's
// compositor and cannot use the server-side EGL_WL extension.
//
// References — see project_wpe_phase_2_validated memory + the report
// the Phase 2.1 research agent produced + EGL_MESA_image_dma_buf_export
// spec.

#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <unistd.h>

#include <wayland-client.h>
#include <wayland-egl.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>

#include <wpe/wpe.h>
#include <wpe/fdo.h>
#include <wpe/fdo-egl.h>
#include <wpe/webkit.h>
#include <glib.h>
#include <glib-unix.h>

#include "xdg-shell-client-protocol.h"
#include "linux-dmabuf-v1-client-protocol.h"

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

    // EGL extension function pointers — loaded via eglGetProcAddress at
    // startup. The Mesa dmabuf export path is the only one that works
    // client-side on etnaviv (EGL_WL_create_wayland_buffer_from_image is
    // a SERVER-side extension and is absent in Mesa's etnaviv client
    // driver).
    using PFNEGLEXPORTDMABUFIMAGEQUERYMESAPROC = EGLBoolean(EGLAPIENTRYP)(EGLDisplay, EGLImageKHR,
                                                                          int          *fourcc,
                                                                          int          *num_planes,
                                                                          EGLuint64KHR *modifiers);
    using PFNEGLEXPORTDMABUFIMAGEMESAPROC      = EGLBoolean(EGLAPIENTRYP)(EGLDisplay, EGLImageKHR,
                                                                     int *fds, EGLint *strides,
                                                                     EGLint *offsets);

    PFNEGLEXPORTDMABUFIMAGEQUERYMESAPROC egl_export_dmabuf_query = nullptr;
    PFNEGLEXPORTDMABUFIMAGEMESAPROC      egl_export_dmabuf       = nullptr;

    struct Runner {
        // Wayland globals — bound in registry.global handler.
        wl_display          *wlDisplay   = nullptr;
        wl_registry         *registry    = nullptr;
        wl_compositor       *compositor  = nullptr;
        xdg_wm_base         *xdgWmBase   = nullptr;
        zwp_linux_dmabuf_v1 *linuxDmabuf = nullptr;

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

    // ---- Build a wl_buffer from an EGLImage via Mesa's dmabuf export
    // path. Returns nullptr on failure; caller must release the WPE
    // image back to the engine in that case. fds returned by Mesa are
    // owned by us until create_params consumes them. ----
    wl_buffer *buildBufferFromImage(Runner *r, EGLImageKHR egl_image) {
        int          fourcc     = 0;
        int          num_planes = 0;
        EGLuint64KHR modifier   = 0;
        if (!egl_export_dmabuf_query(r->eglDisplay, egl_image, &fourcc, &num_planes, &modifier)) {
            g_warning("[marathon-webview-runner] eglExportDMABUFImageQueryMESA failed; "
                      "EGL error 0x%x",
                      eglGetError());
            return nullptr;
        }
        if (num_planes < 1 || num_planes > 4) {
            g_warning("[marathon-webview-runner] dmabuf query reported %d planes", num_planes);
            return nullptr;
        }

        int    fds[4]     = {-1, -1, -1, -1};
        EGLint strides[4] = {0};
        EGLint offsets[4] = {0};
        if (!egl_export_dmabuf(r->eglDisplay, egl_image, fds, strides, offsets)) {
            g_warning("[marathon-webview-runner] eglExportDMABUFImageMESA failed; "
                      "EGL error 0x%x",
                      eglGetError());
            return nullptr;
        }

        zwp_linux_buffer_params_v1 *params = zwp_linux_dmabuf_v1_create_params(r->linuxDmabuf);
        const uint32_t              mod_hi = static_cast<uint32_t>(modifier >> 32);
        const uint32_t              mod_lo = static_cast<uint32_t>(modifier & 0xffffffff);
        for (int i = 0; i < num_planes; ++i) {
            zwp_linux_buffer_params_v1_add(params, fds[i], i, static_cast<uint32_t>(offsets[i]),
                                           static_cast<uint32_t>(strides[i]), mod_hi, mod_lo);
        }

        wl_buffer *buffer = zwp_linux_buffer_params_v1_create_immed(
            params, r->width, r->height, static_cast<uint32_t>(fourcc), 0);

        zwp_linux_buffer_params_v1_destroy(params);

        // create_immed dup()s the fds during params.add, so we close ours.
        for (int i = 0; i < num_planes; ++i) {
            if (fds[i] >= 0)
                close(fds[i]);
        }

        if (!buffer)
            g_warning("[marathon-webview-runner] zwp_linux_buffer_params_v1_create_immed failed");
        return buffer;
    }

    // ---- Export callback from WPE: an EGLImage just landed. Convert to
    // wl_buffer and present. ----
    void onExportFdoEglImage(void *data, wpe_fdo_egl_exported_image *image) {
        g_message("[marathon-webview-runner] export_fdo_egl_image fired image=%p", image);
        auto *r = static_cast<Runner *>(data);
        if (!image || !r->surface || !r->linuxDmabuf || !egl_export_dmabuf) {
            if (image && r->exportable)
                wpe_view_backend_exportable_fdo_egl_dispatch_release_exported_image(r->exportable,
                                                                                    image);
            return;
        }

        EGLImageKHR egl_image = wpe_fdo_egl_exported_image_get_egl_image(image);
        wl_buffer  *buffer    = buildBufferFromImage(r, egl_image);
        if (!buffer) {
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
        } else if (std::strcmp(iface, zwp_linux_dmabuf_v1_interface.name) == 0) {
            // Bind v3. Qt's bundled global supports v3 (create_params +
            // buffer creation), and our v4 spike falls back to v3 for
            // create_params. v3 gives us everything we need.
            r->linuxDmabuf = static_cast<zwp_linux_dmabuf_v1 *>(wl_registry_bind(
                registry, name, &zwp_linux_dmabuf_v1_interface, std::min(version, 3u)));
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

        // Load the dmabuf-export entrypoints — Mesa's
        // EGL_MESA_image_dma_buf_export extension. This is the
        // CLIENT-side path that etnaviv exposes
        // (EGL_WL_create_wayland_buffer_from_image is server-side and
        // absent in the etnaviv client driver).
        egl_export_dmabuf_query = reinterpret_cast<PFNEGLEXPORTDMABUFIMAGEQUERYMESAPROC>(
            eglGetProcAddress("eglExportDMABUFImageQueryMESA"));
        egl_export_dmabuf = reinterpret_cast<PFNEGLEXPORTDMABUFIMAGEMESAPROC>(
            eglGetProcAddress("eglExportDMABUFImageMESA"));
        if (!egl_export_dmabuf_query || !egl_export_dmabuf) {
            g_critical("[marathon-webview-runner] missing EGL_MESA_image_dma_buf_export "
                       "entrypoints. EGL extensions: %s",
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

    if (!r.compositor || !r.xdgWmBase || !r.linuxDmabuf) {
        g_critical("[marathon-webview-runner] missing required globals: "
                   "compositor=%p xdg_wm_base=%p linux-dmabuf=%p",
                   r.compositor, r.xdgWmBase, r.linuxDmabuf);
        return 1;
    }

    if (!initEgl(r))
        return 1;

    // libwpe loads its backend impl dynamically and otherwise defaults
    // to libWPEBackend-default.so (which doesn't exist on Alpine).
    // Point it at FDO before any WPE call. This is the same trick
    // Cog uses in launcher/cog-launcher.c.
    wpe_loader_init("libWPEBackend-fdo-1.0.so.1");

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

    // Build the exportable BEFORE the wl_egl_window/eglMakeCurrent —
    // matches WindowViewBackend constructor order: initialize()
    // (creates exportable) runs before the surface→toplevel→activity
    // _state→wl_egl_window→eglMakeCurrent chain. (We don't follow the
    // exact order — exportable needs to exist before activity_state
    // dispatches against it.)
    r.exportable = wpe_view_backend_exportable_fdo_egl_create(
        &kExportableEglClient, &r, static_cast<uint32_t>(r.width), static_cast<uint32_t>(r.height));
    if (!r.exportable) {
        g_critical("[marathon-webview-runner] wpe_view_backend_exportable_fdo_egl_create failed");
        return 1;
    }

    // Wake the backend (visible|in_window — matching WindowViewBackend
    // line 691; NOT focused). Set size + scale factor. Do this BEFORE
    // constructing the WebKitWebView so the WebProcess starts with the
    // correct state from the first IPC handshake.
    {
        struct wpe_view_backend *vb =
            wpe_view_backend_exportable_fdo_get_view_backend(r.exportable);
        wpe_view_backend_dispatch_set_device_scale_factor(vb, 1.0f);
        wpe_view_backend_dispatch_set_size(vb, static_cast<uint32_t>(r.width),
                                           static_cast<uint32_t>(r.height));
        wpe_view_backend_add_activity_state(
            vb, wpe_view_activity_state_visible | wpe_view_activity_state_in_window);
    }

    // wl_egl_window + eglMakeCurrent — host EGL context must be current
    // before the WebProcess starts. Read directly from WPE's
    // MiniBrowser source (Tools/wpe/backends/fdo/WindowViewBackend.cpp
    // constructor lines 695-708).
    auto *eglWindow = wl_egl_window_create(r.surface, r.width, r.height);
    if (!eglWindow) {
        g_critical("[marathon-webview-runner] wl_egl_window_create failed");
        return 1;
    }
    auto createPlatformWindowSurface = reinterpret_cast<PFNEGLCREATEPLATFORMWINDOWSURFACEEXTPROC>(
        eglGetProcAddress("eglCreatePlatformWindowSurfaceEXT"));
    EGLSurface eglSurface = EGL_NO_SURFACE;
    if (createPlatformWindowSurface) {
        eglSurface = createPlatformWindowSurface(r.eglDisplay, r.eglConfig, eglWindow, nullptr);
    }
    if (eglSurface == EGL_NO_SURFACE) {
        eglSurface = eglCreateWindowSurface(
            r.eglDisplay, r.eglConfig, reinterpret_cast<EGLNativeWindowType>(eglWindow), nullptr);
    }
    if (eglSurface == EGL_NO_SURFACE) {
        g_critical("[marathon-webview-runner] eglCreate{Platform,}WindowSurface failed; "
                   "error 0x%x",
                   eglGetError());
        return 1;
    }
    if (!eglMakeCurrent(r.eglDisplay, eglSurface, eglSurface, r.eglContext)) {
        g_critical("[marathon-webview-runner] eglMakeCurrent failed; error 0x%x", eglGetError());
        return 1;
    }
    g_message("[marathon-webview-runner] EGL context current (surface=%p)", eglSurface);

    WebKitWebViewBackend *wkBackend = webkit_web_view_backend_new(
        wpe_view_backend_exportable_fdo_get_view_backend(r.exportable), nullptr, nullptr);

    r.webContext = webkit_web_context_new();
    r.webView    = WEBKIT_WEB_VIEW(g_object_new(WEBKIT_TYPE_WEB_VIEW, "backend", wkBackend,
                                                "web-context", r.webContext, nullptr));

    g_signal_connect(r.webView, "load-changed", G_CALLBACK(onLoadChanged), nullptr);
    g_signal_connect(r.webView, "load-failed", G_CALLBACK(onLoadFailed), nullptr);

    // Decide load mode by URL scheme. Plain "about:blank" / "http(s)://" go
    // through load_uri; an inline HTML probe ("inline:") rules out network +
    // resource-loader issues and proves the WebProcess + backend pipeline.
    if (std::strncmp(url, "inline:", 7) == 0) {
        const char *html = "<html><body style='background:#0a8'>"
                           "<h1 style='color:white;font:64px sans-serif'>Marathon WPE</h1>"
                           "</body></html>";
        g_message("[marathon-webview-runner] load_html (inline)");
        webkit_web_view_load_html(r.webView, html, nullptr);
    } else {
        g_message("[marathon-webview-runner] load_uri %s", url);
        webkit_web_view_load_uri(r.webView, url);
    }

    // Periodic diagnostic — once per second, log is-loading + estimated
    // load progress so we can see whether the WebView even thinks a load
    // is happening.
    g_timeout_add_seconds(
        1,
        [](gpointer ud) -> gboolean {
            auto *rr = static_cast<Runner *>(ud);
            if (!rr->webView)
                return G_SOURCE_REMOVE;
            g_message("[marathon-webview-runner] tick is_loading=%d progress=%.2f uri=%s",
                      webkit_web_view_is_loading(rr->webView),
                      webkit_web_view_get_estimated_load_progress(rr->webView),
                      webkit_web_view_get_uri(rr->webView));
            return G_SOURCE_CONTINUE;
        },
        &r);

    gMainLoop = g_main_loop_new(nullptr, FALSE);
    signal(SIGINT, onTerm);
    signal(SIGTERM, onTerm);

    // Wayland pumping via custom GSource (canonical pattern, mirrors
    // WPE's MiniBrowser Tools/wpe/backends/fdo/WindowViewBackend.cpp:91).
    //
    // The key insight from MiniBrowser source: `prepare` MUST call
    // dispatch_pending + flush before each main-loop poll cycle. This
    // is what drains wayland requests queued by other GSource callbacks
    // (notably WebKit's IPC handlers that call into WPE-fdo). Without
    // this, frame callbacks never reach the compositor, frame_complete
    // never fires back to WPE, the WebProcess IPC pipe fills up, and
    // WPEWebProcess ends in wchan=pipe_write. This was the r260-r264
    // failure mode.
    struct WlSource {
        GSource     source;
        GPollFD     pfd;
        wl_display *display;
    };
    static GSourceFuncs s_wlSourceFuncs = {
        // prepare: drain pending + flush before main loop blocks on poll.
        [](GSource *base, gint *timeout) -> gboolean {
            auto *src = reinterpret_cast<WlSource *>(base);
            *timeout  = -1;
            wl_display_dispatch_pending(src->display);
            wl_display_flush(src->display);
            return FALSE;
        },
        // check: dispatch only if poll(2) signalled fd-readable.
        [](GSource *base) -> gboolean {
            auto *src = reinterpret_cast<WlSource *>(base);
            return !!src->pfd.revents;
        },
        // dispatch: read events from fd (safe — check confirmed readiness).
        [](GSource *base, GSourceFunc, gpointer) -> gboolean {
            auto *src = reinterpret_cast<WlSource *>(base);
            if (src->pfd.revents & G_IO_IN)
                wl_display_dispatch(src->display);
            if (src->pfd.revents & (G_IO_ERR | G_IO_HUP))
                return FALSE;
            src->pfd.revents = 0;
            return TRUE;
        },
        nullptr,
        nullptr,
        nullptr,
    };
    GSource *wlSource = g_source_new(&s_wlSourceFuncs, sizeof(WlSource));
    auto    *wls      = reinterpret_cast<WlSource *>(wlSource);
    wls->display      = r.wlDisplay;
    wls->pfd.fd       = wl_display_get_fd(r.wlDisplay);
    wls->pfd.events   = G_IO_IN | G_IO_ERR | G_IO_HUP;
    wls->pfd.revents  = 0;
    g_source_add_poll(wlSource, &wls->pfd);
    g_source_set_priority(wlSource, G_PRIORITY_DEFAULT);
    g_source_set_can_recurse(wlSource, TRUE);
    g_source_attach(wlSource, nullptr);
    wl_display_flush(r.wlDisplay);

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
    if (r.linuxDmabuf)
        zwp_linux_dmabuf_v1_destroy(r.linuxDmabuf);
    if (r.compositor)
        wl_compositor_destroy(r.compositor);
    if (r.registry)
        wl_registry_destroy(r.registry);
    wl_display_disconnect(r.wlDisplay);
    g_main_loop_unref(gMainLoop);
    return 0;
}
