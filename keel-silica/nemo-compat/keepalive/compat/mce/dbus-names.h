/* SPDX-FileCopyrightText: 2026 Patrick Quinn
 * SPDX-License-Identifier: MIT
 *
 * Keel fallback for the MCE D-Bus names nemo-keepalive uses, for hosts
 * without mce-headers. The values are MCE's public D-Bus names. Device builds
 * use the real <mce/dbus-names.h> from mce-headers.
 */
#ifndef KEEL_MCE_DBUS_NAMES_FALLBACK_H
#define KEEL_MCE_DBUS_NAMES_FALLBACK_H
#define MCE_SERVICE "com.nokia.mce"
#define MCE_REQUEST_PATH "/com/nokia/mce/request"
#define MCE_SIGNAL_PATH "/com/nokia/mce/signal"
#endif
