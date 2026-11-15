// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-or-later
//
// libpacific-eglshadercache.so, preloaded by pacific-env: a disk cache for
// the GPU driver's compiled shaders.
//
// Android's libEGL keeps compiled shaders in a blob cache (the driver's
// EGL_ANDROID_blob_cache), but only on disk when the app has named a file
// with android::egl_set_cache_filename(), as Android's framework does for
// every app. Nothing does under libhybris, so each WebProcess compiled every
// shader Skia needed afresh: on the Jolla Phone a page's first scroll paused
// 30-70 ms each time new content needed a new GPU program (Skia's program
// builder and Mali's compiler, measured with simpleperf). At start-up, before
// any EGL call, this names a cache file per program (PACIFIC_EGL_SHADER_CACHE
// with the program's name appended), so shaders compiled once load from disk
// in every later process. WebKit reaches EGL through libepoxy, which looks
// eglInitialize up in libEGL itself, so a constructor, not an interposed
// eglInitialize. The network process draws nothing and is left alone.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

__attribute__((constructor)) static void name_cache_file(void)
{
    const char *base = getenv("PACIFIC_EGL_SHADER_CACHE");
    if (!base || !*base)
        return;
    char exe[256];
    const ssize_t n = readlink("/proc/self/exe", exe, sizeof exe - 1);
    if (n <= 0)
        return;
    exe[n] = 0;
    const char *program = strrchr(exe, '/') ? strrchr(exe, '/') + 1 : exe;
    if (strstr(program, "NetworkProcess"))
        return;
    char file[1024];
    if (snprintf(file, sizeof file, "%s.%s", base, program) >= (int)sizeof file)
        return;
    void *hybris = dlopen("libhybris-common.so.1", RTLD_LAZY);
    if (!hybris)
        return;
    void *(*android_dlopen)(const char *, int) = (void *(*)(const char *, int))dlsym(hybris, "android_dlopen");
    void *(*android_dlsym)(void *, const char *) = (void *(*)(void *, const char *))dlsym(hybris, "android_dlsym");
    if (!android_dlopen || !android_dlsym)
        return;
    void *egl = android_dlopen("libEGL.so", RTLD_LAZY);
    if (!egl)
        return;
    void (*set_filename)(const char *) = (void (*)(const char *))android_dlsym(egl, "_ZN7android22egl_set_cache_filenameEPKc");
    if (!set_filename)
        return;
    set_filename(file);
    // Android's default holds 2 MB; a browser's Skia programs need more.
    void *(*cache)(void) = (void *(*)(void))android_dlsym(egl, "_ZN7android11egl_cache_t3getEv");
    void (*set_limit)(void *, long) = (void (*)(void *, long))android_dlsym(egl, "_ZN7android11egl_cache_t13setCacheLimitEl");
    if (cache && set_limit)
        set_limit(cache(), 16L << 20);
}
