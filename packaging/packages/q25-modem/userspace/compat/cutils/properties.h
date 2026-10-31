/* SPDX-License-Identifier: Apache-2.0 */
/*
 * Q25 musl shim for the Android property service: read-only defaults from
 * /etc/q25-modem/properties ("key=value" lines), runtime values as files in
 * /run/q25-modem/props/<key> (shared by all three daemons and scripts).
 */
#ifndef Q25_COMPAT_CUTILS_PROPERTIES_H
#define Q25_COMPAT_CUTILS_PROPERTIES_H
#define PROPERTY_KEY_MAX	32
#define PROPERTY_VALUE_MAX	92
int property_get(const char *key, char *value, const char *default_value);
int property_set(const char *key, const char *value);
#endif
