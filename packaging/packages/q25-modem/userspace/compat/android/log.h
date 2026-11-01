/* SPDX-License-Identifier: Apache-2.0 */
/* Q25 musl shim: Android liblog -> stderr (journald under systemd). */
#ifndef Q25_COMPAT_ANDROID_LOG_H
#define Q25_COMPAT_ANDROID_LOG_H
enum { ANDROID_LOG_UNKNOWN, ANDROID_LOG_DEFAULT, ANDROID_LOG_VERBOSE, ANDROID_LOG_DEBUG,
       ANDROID_LOG_INFO, ANDROID_LOG_WARN, ANDROID_LOG_ERROR, ANDROID_LOG_FATAL };
int __android_log_print(int prio, const char *tag, const char *fmt, ...)
	__attribute__((format(printf, 3, 4)));
#endif
