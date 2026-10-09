/* SPDX-FileCopyrightText: 2026 Patrick Quinn
 * SPDX-License-Identifier: MIT
 *
 * Keel fallback for the libiphb API (names and signatures as in libiphb's
 * public header), used only when the real libiphb is not available, i.e. on
 * development hosts without DSME. Waits are plain timers: they do not wake
 * the device from suspend. Device builds link the real libiphb.
 */
#ifndef KEEL_IPHB_FALLBACK_H
#define KEEL_IPHB_FALLBACK_H

#include <time.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void *iphb_t;

iphb_t iphb_open(int *dummy);
int iphb_get_fd(iphb_t iphbh);
time_t iphb_wait2(iphb_t iphbh, unsigned mintime, unsigned maxtime, int must_wait, int resume);
int iphb_discard_wakeups(iphb_t iphbh);
iphb_t iphb_close(iphb_t iphbh);

#ifdef __cplusplus
}
#endif

#endif
