// SPDX-License-Identifier: Apache-2.0
/*
 * Q25 musl build: MediaTek's libnvram/libsysenv are bionic-only vendor
 * libraries and are not shipped. Every entry point reports "unavailable";
 * callers already treat that as non-fatal (sbp=0, no bin-region restore).
 */
#include <errno.h>
#include "nvram_shim.h"

int NVM_GetLIDByName(const char *name)
{
	(void)name;
	errno = ENOSYS;
	return -1;
}

struct nvm_file_desc NVM_GetFileDesc(int lid, int *size_out, void *reserved, int mode)
{
	struct nvm_file_desc d = { .fd = -1 };

	(void)lid;
	(void)reserved;
	(void)mode;
	if (size_out)
		*size_out = 0;
	errno = ENOSYS;
	return d;
}

int NVM_CloseFileDesc(long fd, long token)
{
	(void)fd;
	(void)token;
	return 0;
}

int NVM_RestoreFromBinRegion_OneFile(int variant, const char *path)
{
	(void)variant;
	(void)path;
	return 0;
}
