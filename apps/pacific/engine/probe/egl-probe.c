// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// pacific-egl-probe: prints what the engine needs to know about the phone's
// EGL and GLES, as a Wayland client of the running compositor (the same EGL
// platform Qt and WPEBackend-fdo use). Lines are "key: value"; the
// extension lists are space-separated, as EGL returns them.
//
//   pacific-egl-probe            (WAYLAND_DISPLAY as for any app)
//
// Exit status: 0 when a display, a context and both extension lists were
// read; 1 otherwise (the output says how far it got).

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <stdio.h>
#include <stdlib.h>
#include <wayland-client.h>

static void print(const char* key, const char* value)
{
    printf("%s: %s\n", key, value ? value : "(none)");
}

int main(void)
{
    const char* clientExtensions = eglQueryString(EGL_NO_DISPLAY, EGL_EXTENSIONS);
    print("egl_client_extensions", clientExtensions);

    struct wl_display* wl = wl_display_connect(NULL);
    print("wayland_display", wl ? "connected" : "FAILED");
    EGLDisplay display = eglGetDisplay(wl ? (EGLNativeDisplayType)wl : EGL_DEFAULT_DISPLAY);
    EGLint major = 0;
    EGLint minor = 0;
    if (display == EGL_NO_DISPLAY || !eglInitialize(display, &major, &minor)) {
        printf("egl_initialize: FAILED 0x%x\n", eglGetError());
        return 1;
    }
    printf("egl_version: %d.%d\n", major, minor);
    print("egl_vendor", eglQueryString(display, EGL_VENDOR));
    print("egl_version_string", eglQueryString(display, EGL_VERSION));
    print("egl_client_apis", eglQueryString(display, EGL_CLIENT_APIS));
    print("egl_extensions", eglQueryString(display, EGL_EXTENSIONS));

    // EGL 1.5 entry points libepoxy looks up (libegl-stubs.so provides them
    // when the driver does not).
    const char* entryPoints[] = { "eglCreateSync", "eglCreateImage", "eglWaitSync", "eglClientWaitSync",
        "eglCreatePlatformWindowSurface", "eglBindWaylandDisplayWL", "eglCreateImageKHR",
        "eglDupNativeFenceFDANDROID", "eglHybrisCreateNativeBuffer" };
    for (size_t i = 0; i < sizeof(entryPoints) / sizeof(entryPoints[0]); ++i)
        printf("proc_%s: %s\n", entryPoints[i], eglGetProcAddress(entryPoints[i]) ? "yes" : "no");

    static const EGLint configAttributes[] = { EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT, EGL_NONE };
    EGLConfig config = NULL;
    EGLint count = 0;
    if (!eglChooseConfig(display, configAttributes, &config, 1, &count) || count < 1) {
        printf("egl_config: FAILED 0x%x\n", eglGetError());
        return 1;
    }
    eglBindAPI(EGL_OPENGL_ES_API);
    static const EGLint contextAttributes[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
    EGLContext context = eglCreateContext(display, config, EGL_NO_CONTEXT, contextAttributes);
    if (context == EGL_NO_CONTEXT) {
        printf("egl_context: FAILED 0x%x\n", eglGetError());
        return 1;
    }
    // Surfaceless first, a 16x16 pbuffer if the driver has no surfaceless
    // contexts.
    EGLSurface surface = EGL_NO_SURFACE;
    if (!eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, context)) {
        print("egl_surfaceless_current", "no");
        EGLint pbufferAttributes[] = { EGL_WIDTH, 16, EGL_HEIGHT, 16, EGL_NONE };
        surface = eglCreatePbufferSurface(display, config, pbufferAttributes);
        if (surface == EGL_NO_SURFACE || !eglMakeCurrent(display, surface, surface, context)) {
            printf("egl_make_current: FAILED 0x%x\n", eglGetError());
            return 1;
        }
    } else {
        print("egl_surfaceless_current", "yes");
    }
    print("gl_vendor", (const char*)glGetString(GL_VENDOR));
    print("gl_renderer", (const char*)glGetString(GL_RENDERER));
    print("gl_version", (const char*)glGetString(GL_VERSION));
    print("gl_shading_language", (const char*)glGetString(GL_SHADING_LANGUAGE_VERSION));
    print("gl_extensions", (const char*)glGetString(GL_EXTENSIONS));
    GLint maxTexture = 0;
    glGetIntegerv(GL_MAX_TEXTURE_SIZE, &maxTexture);
    printf("gl_max_texture_size: %d\n", maxTexture);

    eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    if (surface != EGL_NO_SURFACE)
        eglDestroySurface(display, surface);
    eglDestroyContext(display, context);
    eglTerminate(display);
    if (wl)
        wl_display_disconnect(wl);
    return 0;
}
