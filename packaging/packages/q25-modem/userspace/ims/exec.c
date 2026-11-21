// SPDX-License-Identifier: Apache-2.0
// q25-ims-exec: start an Android vendor daemon the way init starts a
// service with `socket` lines: each named socket is bound at
// /dev/socket/<name>, listened on, and handed over as
// ANDROID_SOCKET_<name>=<fd> (libcutils' android_get_control_socket).
//
//   q25-ims-exec [-s name:stream|dgram|seqpacket:mode]... -- program [args]
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

#define SOCKET_DIR "/dev/socket/"

static int make_socket(char *spec)
{
	char *name = strtok(spec, ":"), *type = strtok(NULL, ":"), *mode = strtok(NULL, ":");
	if (!name || !type || !mode)
		return -1;
	int t = !strcmp(type, "stream") ? SOCK_STREAM : !strcmp(type, "dgram") ? SOCK_DGRAM :
		!strcmp(type, "seqpacket") ? SOCK_SEQPACKET : -1;
	if (t < 0)
		return -1;
	struct sockaddr_un addr = { .sun_family = AF_UNIX };
	if (snprintf(addr.sun_path, sizeof(addr.sun_path), SOCKET_DIR "%s", name) >= (int)sizeof(addr.sun_path))
		return -1;
	unlink(addr.sun_path);
	int fd = socket(AF_UNIX, t, 0); /* inherited across exec, as init's are */
	if (fd < 0 || bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0 ||
	    chmod(addr.sun_path, (mode_t)strtol(mode, NULL, 8)) < 0 ||
	    (t != SOCK_DGRAM && listen(fd, 8) < 0)) {
		fprintf(stderr, "q25-ims-exec: %s: %s\n", addr.sun_path, strerror(errno));
		return -1;
	}
	char key[128], val[16];
	snprintf(key, sizeof(key), "ANDROID_SOCKET_%s", name);
	snprintf(val, sizeof(val), "%d", fd);
	return setenv(key, val, 1);
}

int main(int argc, char **argv)
{
	int i = 1;
	for (; i < argc && strcmp(argv[i], "--") != 0; i++) {
		if (strcmp(argv[i], "-s") != 0 || i + 1 >= argc || make_socket(argv[++i]) < 0) {
			fprintf(stderr, "usage: q25-ims-exec [-s name:type:mode]... -- program [args]\n");
			return 2;
		}
	}
	if (i + 1 >= argc)
		return 2;
	execv(argv[i + 1], argv + i + 1);
	fprintf(stderr, "q25-ims-exec: %s: %s\n", argv[i + 1], strerror(errno));
	return 127;
}
