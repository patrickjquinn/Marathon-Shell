/*
 * SPDX-FileCopyrightText: 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */
#ifndef MINDONE_NVRAM_SHIM_H
#define MINDONE_NVRAM_SHIM_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

int NVM_GetLIDByName(const char *name);

/*
 * NVM_GetFileDesc(lid, size_out, reserved, mode) -- opens the LID's backing
 * file and returns a REAL POSIX file descriptor (disassembly-confirmed: the
 * returned value in x0 is passed directly as the first argument to
 * __read_chk(fd, buf, count, buflen) at the call site, i.e. libnvram opens
 * the file itself and hands back an fd, it does not hand back an opaque
 * handle needing translation).
 *   - `size_out`: an out-parameter (int*) the disassembly shows filled in
 *     by the call and then used, sign-extended, as the read() length --
 *     almost certainly "how many bytes to read for this record."
 *   - `reserved`: a second pointer argument (mov x2, sp) whose target is
 *     never read back by ccci_mdinit's own code after the call in either
 *     traced call site -- pass a valid zeroed word, do not pass NULL
 *     (unverified whether the callee itself dereferences it
 *     unconditionally).
 *   - `mode`: 0 in both traced call sites (both are reads). The write path
 *     was not observed in ccci_mdinit (it only ever reads MD_SBP), so the
 *     nonzero value(s) for write are UNVERIFIED -- do not guess a write
 *     call against this shim without confirming mode's write value first
 *     (a wrong mode on a real NVRAM LID risks corrupting it).
 * Return: a struct-by-value in x0:x1 (AAPCS64 packs a <=16-byte, two
 * 8-byte-field aggregate return into x0/x1) -- x0 is consumed as the fd,
 * x1 ("token") is disassembly-confirmed saved across the call and fed
 * verbatim into NVM_CloseFileDesc's second argument. We model this as a
 * `long`-pair struct rather than committing to the field types the real
 * implementation uses internally, since only the register-level ABI
 * outcome (which we replicate) was actually observed, not the source type.
 */
struct nvm_file_desc {
	long fd;	/* x0 on return: real POSIX fd, negative on error */
	long token;	/* x1 on return: opaque, must be echoed back to NVM_CloseFileDesc */
};
struct nvm_file_desc NVM_GetFileDesc(int lid, int *size_out, void *reserved, int mode);

/* NVM_CloseFileDesc(fd, token) -- `token` is whatever NVM_GetFileDesc
 * returned in the paired `.token` field for that same fd; disassembly shows
 * it masked to 32 bits before the call (`and x1, x23, #0xffffffff`), so a
 * 32-bit-clean value is sufficient even though the parameter slot is 64-bit.
 * Return: nonzero on success (checked via `tbnz w0, #0` -- "branch if bit 0
 * set"), matching ccci_mdinit treating bit0==1 as success.
 */
int NVM_CloseFileDesc(long fd, long token);

struct nvm_file_desc; /* fwd decl already above; kept for reading order */
int NVM_RestoreFromBinRegion_OneFile(int variant, const char *path);

#ifdef __cplusplus
}
#endif

#endif /* MINDONE_NVRAM_SHIM_H */
