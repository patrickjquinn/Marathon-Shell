#define _GNU_SOURCE
#include <stdio.h>
#include <dlfcn.h>
#include <string.h>

/*
 * libminisf_shim.c - Loader redirection shim for qt6-qpa-hwcomposer-plugin
 *
 * This shim intercepts android_dlopen calls for "libminisf.so" and redirects
 * them to the standard glibc dlopen call. This solves the "incompatible or missing"
 * error when running on Glibc-based Halium distributions like Droidian, where
 * the plugin expects Bionic semantics but only Glibc libraries (libsf.so.1) exist.
 *
 * Usage:
 *   gcc -shared -fPIC libminisf_shim.c -o libminisf_shim.so -ldl
 *   export LD_PRELOAD=/path/to/libminisf_shim.so
 */

static void *minisf_handle = NULL;

/* Prototype for the Bionic loader function we are intercepting */
void *android_dlopen(const char *filename, int flags);
void *android_dlsym(void *handle, const char *symbol);

void *android_dlopen(const char *filename, int flags) {
    /* Check if the requested library is the one we need to patch */
    if (filename && strstr(filename, "libminisf")) {
        // fprintf(stderr, "SHIM: Intercepted android_dlopen for %s -> Redirecting to dlopen\n", filename);
        
        /* 
         * Use standard glibc dlopen. 
         * RTLD_GLOBAL is important so symbols are visible to other libraries
         */
        minisf_handle = dlopen(filename, RTLD_NOW | RTLD_GLOBAL);
        
        if (!minisf_handle) {
            fprintf(stderr, "SHIM: dlopen failed for %s: %s\n", filename, dlerror());
        }
        return minisf_handle;
    }
    
    /* For all other libraries, call the real android_dlopen (from libhybris) */
    void *(*real_func)(const char *, int) = dlsym(RTLD_NEXT, "android_dlopen");
    return real_func ? real_func(filename, flags) : NULL;
}

void *android_dlsym(void *handle, const char *symbol) {
    /* If the handle matches our shimmed handle, use standard dlsym */
    if (handle == minisf_handle) {
        // fprintf(stderr, "SHIM: Intercepted android_dlsym for %s -> Redirecting to dlsym\n", symbol);
        return dlsym(handle, symbol);
    }

    /* Otherwise use the real android_dlsym */
    void *(*real_func)(void *, const char *) = dlsym(RTLD_NEXT, "android_dlsym");
    return real_func ? real_func(handle, symbol) : NULL;
}
