#define _GNU_SOURCE
// SPDX-License-Identifier: Apache-2.0
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include <android/log.h>
#include <cutils/properties.h>

#define PROP_DIR	"/run/q25-modem/props"
#define PROP_DEFAULTS	"/etc/q25-modem/properties"

int __android_log_print(int prio, const char *tag, const char *fmt, ...)
{
	static const char lv[] = "??VDIWEF";
	va_list ap;
	int n;

	/* systemd-journald maps the <N> prefix to a syslog priority */
	fprintf(stderr, "<%d>%s %c: ", prio >= ANDROID_LOG_ERROR ? 3 :
		prio == ANDROID_LOG_WARN ? 4 : prio == ANDROID_LOG_INFO ? 6 : 7,
		tag ? tag : "", prio >= 0 && prio < 8 ? lv[prio] : '?');
	va_start(ap, fmt);
	n = vfprintf(stderr, fmt, ap);
	va_end(ap);
	if (n <= 0 || fmt[strlen(fmt) - 1] != '\n')
		fputc('\n', stderr);
	return n;
}

static int key_ok(const char *key)
{
	return key && *key && !strchr(key, '/') && strlen(key) < 128 && strcmp(key, ".") &&
	       strcmp(key, "..");
}

int property_get(const char *key, char *value, const char *def)
{
	char path[192], line[256];
	FILE *f;
	size_t n = 0;

	value[0] = 0;
	if (key_ok(key)) {
		snprintf(path, sizeof(path), PROP_DIR "/%s", key);
		f = fopen(path, "re");
		if (f) {
			n = fread(value, 1, PROPERTY_VALUE_MAX - 1, f);
			fclose(f);
			while (n && (value[n - 1] == '\n' || value[n - 1] == '\r'))
				n--;
			value[n] = 0;
			return (int)n;
		}
		f = fopen(PROP_DEFAULTS, "re");
		if (f) {
			size_t kl = strlen(key);

			while (fgets(line, sizeof(line), f)) {
				if (strncmp(line, key, kl) || line[kl] != '=')
					continue;
				strncpy(value, line + kl + 1, PROPERTY_VALUE_MAX - 1);
				value[PROPERTY_VALUE_MAX - 1] = 0;
				value[strcspn(value, "\r\n")] = 0;
				fclose(f);
				return (int)strlen(value);
			}
			fclose(f);
		}
	}
	if (def) {
		strncpy(value, def, PROPERTY_VALUE_MAX - 1);
		value[PROPERTY_VALUE_MAX - 1] = 0;
	}
	return (int)strlen(value);
}

int property_set(const char *key, const char *value)
{
	char path[192], tmp[200];
	int fd;
	ssize_t len = (ssize_t)strlen(value);

	if (!key_ok(key) || len >= PROPERTY_VALUE_MAX) {
		errno = EINVAL;
		return -1;
	}
	mkdir("/run/q25-modem", 0755);
	mkdir(PROP_DIR, 0755);
	snprintf(path, sizeof(path), PROP_DIR "/%s", key);
	snprintf(tmp, sizeof(tmp), "%s.tmp", path);
	fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
	if (fd < 0)
		return -1;
	if (write(fd, value, len) != len) {
		close(fd);
		return -1;
	}
	close(fd);
	if (rename(tmp, path))
		return -1;
	fprintf(stderr, "<6>props: set %s=%s\n", key, value);
	return 0;
}
