// SPDX-License-Identifier: MIT
/* Adapted from postmarketOS mesa-dri-simpledrm at pmaports e9759d55ebb185b87d498b37b842329d78e8b72b.
 * Keep this shim in a candidate-only driver directory; no KMS operations.
 */
#include <dlfcn.h>
#include <stdio.h>
void *__driDriverGetExtensions_simpledrm(void)
{
    static void *handle;
    static void *(*get_extensions)(void);
    if (!handle) handle = dlopen("/usr/lib/dri/libdril_dri.so", RTLD_NOW | RTLD_LOCAL);
    if (!handle) { fprintf(stderr, "Q25 KMSRO: %s\n", dlerror()); return 0; }
    if (!get_extensions) get_extensions = (void *(*)(void))dlsym(handle, "__driDriverGetExtensions_mediatek");
    if (!get_extensions) { fprintf(stderr, "Q25 KMSRO: %s\n", dlerror()); return 0; }
    return get_extensions();
}
