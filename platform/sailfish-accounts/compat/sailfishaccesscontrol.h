// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Host fallback for sailfish-access-control's one function Sailfish.Accounts
// uses (sailfish_access_control_hasgroup(), named as in its public header,
// github.com/sailfishos/sailfish-access-control, LGPL-2.1-or-later). Device
// builds link the system library (pkg-config sailfishaccesscontrol); this
// answers from the user's groups as the C library does.

#ifndef KEEL_SAILFISHACCESSCONTROL_H
#define KEEL_SAILFISHACCESSCONTROL_H

#include <stdbool.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

bool sailfish_access_control_hasgroup(uid_t uid, const char *group_name);

#ifdef __cplusplus
}
#endif

#endif
