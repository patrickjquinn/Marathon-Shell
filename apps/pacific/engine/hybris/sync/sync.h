// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LGPL-2.1-only
//
// The one libsync call the plugin makes (libsync.so.2 at run time), in place
// of AOSP's sync.h and the kernel's sync_file.h it pulls in.
#pragma once
#ifdef __cplusplus
extern "C" {
#endif
int sync_wait(int fd, int timeout);
#ifdef __cplusplus
}
#endif
