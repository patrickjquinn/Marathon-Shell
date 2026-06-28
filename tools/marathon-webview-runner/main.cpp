// marathon-webview-runner — Phase 2 scaffold for the WPE WebKit
// host process. One instance per webview in Marathon. Receives a URL
// on argv[1], spins up WPEBackend-fdo against a nested Wayland
// client connection, creates a WebKitWebView, and exports rendered
// dmabufs back to Marathon's compositor via the same
// zwp_linux_dmabuf_v1 v4 surface that already serves the rest of the
// QQuick app surfaces. See project_wpe_webview_plan memory for the
// full path.
//
// This file is intentionally minimal in Phase 2: prove the linker
// resolves wpe-webkit-2.0 + wpebackend-fdo-1.0 + wayland-client +
// glib-2.0 against Marathon's build, then instantiate the runtime
// objects to verify the engine actually initialises on etnaviv
// GLES2. The dmabuf bridge + Wayland surface attachment land in a
// follow-up patch — those mirror cog/platform/wayland and Marathon
// already has the receiving side in shell/src/wayland/linuxdmabufv1.

#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include <wayland-client.h>
#include <wpe/wpe.h>
#include <wpe/fdo.h>
#include <wpe/fdo-egl.h>
#include <wpe/webkit.h>
#include <glib.h>

namespace {

    // Singleton glib main loop. WebKit's GLib API drives everything off
    // this — we never spin it manually; let g_main_loop_run park the
    // thread until something exits.
    GMainLoop *gMainLoop = nullptr;

    void       onLoadFailed(WebKitWebView *, WebKitLoadEvent, const char *failingURI, GError *error,
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

    void onTerm(int) {
        if (gMainLoop)
            g_main_loop_quit(gMainLoop);
    }

} // namespace

int main(int argc, char **argv) {
    const char *url = argc > 1 ? argv[1] : "about:blank";

    g_message("[marathon-webview-runner] booting; url=%s", url);

    // WPE only initialises through WPEBackend-fdo when we hand it the
    // host's Wayland display. The runner shares the user session's
    // WAYLAND_DISPLAY with Marathon's compositor.
    wl_display *display = wl_display_connect(nullptr);
    if (!display) {
        g_critical("[marathon-webview-runner] wl_display_connect failed; "
                   "WAYLAND_DISPLAY=%s",
                   g_getenv("WAYLAND_DISPLAY"));
        return 1;
    }
    wpe_fdo_initialize_for_egl_display(display);

    // Engine + persistent network process. WPENetworkProcess is what
    // the wpewebkit aport ships under /usr/libexec/wpe-webkit-2.0.
    WebKitWebContext *ctx = webkit_web_context_new();

    WebKitWebView    *view =
        WEBKIT_WEB_VIEW(g_object_new(WEBKIT_TYPE_WEB_VIEW, "web-context", ctx, nullptr));

    g_signal_connect(view, "load-changed", G_CALLBACK(onLoadChanged), nullptr);
    g_signal_connect(view, "load-failed", G_CALLBACK(onLoadFailed), nullptr);

    webkit_web_view_load_uri(view, url);

    // TODO(phase 2.1): create wpe_view_backend_exportable_fdo via
    // wpe_view_backend_exportable_fdo_dmabuf_create, register the
    // dmabuf export callbacks, attach the exported wl_buffer to a
    // local wl_surface, and pass that surface to Marathon's
    // compositor (matching the xdg_surface adoption flow that
    // shell/src/wayland/waylandcompositor.cpp already runs for
    // marathon-app-runner clients). The receiving end already exists
    // in linuxdmabufv1.{h,cpp}; this end is the gap closure.

    gMainLoop = g_main_loop_new(nullptr, FALSE);
    signal(SIGINT, onTerm);
    signal(SIGTERM, onTerm);
    g_main_loop_run(gMainLoop);

    g_object_unref(view);
    g_object_unref(ctx);
    g_main_loop_unref(gMainLoop);
    wl_display_disconnect(display);
    return 0;
}
