// SPDX-License-Identifier: Apache-2.0
// q25-ims-logd: Android's logd socket for the IMS daemons. liblog sends
// each record as a datagram on /dev/socket/logdw; this writes the text logs
// to stdout with a syslog level prefix, for the journal. Binary (event)
// logs are dropped.
//
//   q25-ims-logd <socket path>
#define _GNU_SOURCE
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

// liblog's android_log_header_t: log id, thread id, realtime (s, ns).
#define HEADER_SIZE (1 + 2 + 4 + 4)
#define LOG_ID_EVENTS 2
#define LOG_ID_STATS 4
#define LOG_ID_SECURITY 6

// Android priority (VERBOSE 2 .. FATAL 7) to a syslog level.
static int level(uint8_t prio)
{
	static const int map[] = { 7, 7, 7, 7, 6, 4, 3, 2 };
	return prio < sizeof(map) / sizeof(map[0]) ? map[prio] : 6;
}

int main(int argc, char **argv)
{
	if (argc != 2) {
		fprintf(stderr, "usage: q25-ims-logd <socket path>\n");
		return 2;
	}
	struct sockaddr_un addr = { .sun_family = AF_UNIX };
	if (strlen(argv[1]) >= sizeof(addr.sun_path))
		return 2;
	strcpy(addr.sun_path, argv[1]);
	unlink(argv[1]);
	int fd = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC, 0);
	if (fd < 0 || bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0 || chmod(argv[1], 0222) < 0) {
		fprintf(stderr, "q25-ims-logd: %s: %s\n", argv[1], strerror(errno));
		return 1;
	}
	setvbuf(stdout, NULL, _IOLBF, 0);
	static char buf[5 * 1024];
	for (;;) {
		ssize_t n = recv(fd, buf, sizeof(buf) - 1, 0);
		if (n < 0) {
			if (errno == EINTR)
				continue;
			return 1;
		}
		if (n < HEADER_SIZE + 3)
			continue;
		uint8_t id = (uint8_t)buf[0];
		if (id == LOG_ID_EVENTS || id == LOG_ID_STATS || id == LOG_ID_SECURITY)
			continue;
		buf[n] = 0;
		uint8_t prio = (uint8_t)buf[HEADER_SIZE];
		const char *tag = buf + HEADER_SIZE + 1;
		size_t tlen = strnlen(tag, (size_t)(n - HEADER_SIZE - 1));
		const char *msg = tag + tlen + 1;
		if (msg >= buf + n)
			msg = "";
		// One journal line per message line.
		for (const char *line = msg; *line;) {
			size_t len = strcspn(line, "\n");
			if (len)
				printf("<%d>%s: %.*s\n", level(prio), tag, (int)len, line);
			line += len + (line[len] == '\n');
		}
	}
}
