// SPDX-License-Identifier: Apache-2.0
// q25-ims-props: Android system properties as bionic reads them, without
// Android's init: one pre-split property area (bionic's ContextsPreSplit,
// /dev/__properties__ as a file) and the property service that sets them.
//
//   q25-ims-props <area> <props file>...   build the area from name=value
//                                          lines (build.prop format; later
//                                          lines win)
//   q25-ims-props serve <area> <socket>    serve property_service (protocol
//                                          v2, PROP_MSG_SETPROP2) on <socket>
//
// The layout and the update sequence follow bionic's prop_area and
// SystemProperties::Update/Add. Values longer than PROP_VALUE_MAX - 1 are
// refused (bionic's long properties need the serialized contexts); ro.*
// properties, once set, cannot change.
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/futex.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/time.h>
#include <sys/un.h>
#include <unistd.h>

#define PA_SIZE (128 * 1024)
#define PROP_AREA_MAGIC 0x504f5250u
#define PROP_AREA_VERSION 0xfc6ed0abu
#define PROP_VALUE_MAX 92
#define PROP_NAME_MAX 256
#define PROP_MSG_SETPROP2 0x00020001u
#define PROP_SUCCESS 0u
#define PROP_ERROR_INVALID_NAME 0x10u
#define PROP_ERROR_INVALID_VALUE 0x14u
#define PROP_ERROR_READ_ONLY_PROPERTY 0x0Bu
#define PROP_ERROR_SET_FAILED 0x18u

struct prop_area {
	uint32_t bytes_used;
	_Atomic uint32_t serial;
	uint32_t magic, version, reserved[28];
	uint8_t data[];
};

struct prop_bt {
	uint32_t namelen;
	_Atomic uint32_t prop, left, right, children;
	char name[];
};

struct prop_info {
	_Atomic uint32_t serial;
	char value[PROP_VALUE_MAX];
	char name[];
};

static struct prop_area *pa;
#define DATA_SIZE (PA_SIZE - sizeof(struct prop_area))
/* The root node, then the dirty backup area readers copy from mid-update. */
#define DIRTY_BACKUP sizeof(struct prop_bt)
#define FIRST_FREE (sizeof(struct prop_bt) + ((PROP_VALUE_MAX + 3) & ~3u))

static void *at(uint32_t offset)
{
	return pa->data + offset;
}

static uint32_t allocate(size_t size)
{
	size_t aligned = (size + 3) & ~(size_t)3;
	if (pa->bytes_used + aligned > DATA_SIZE)
		return 0;
	uint32_t offset = pa->bytes_used;
	pa->bytes_used += aligned;
	return offset;
}

static uint32_t new_bt(const char *name, uint32_t len)
{
	uint32_t o = allocate(sizeof(struct prop_bt) + len + 1);
	if (o) {
		struct prop_bt *b = at(o);
		b->namelen = len;
		memcpy(b->name, name, len);
	}
	return o;
}

// bionic's cmp_prop_name: by length, then bytes.
static int cmp(const char *a, uint32_t alen, const char *b, uint32_t blen)
{
	return alen != blen ? (alen < blen ? -1 : 1) : strncmp(a, b, alen);
}

// One level of the trie is a binary tree; find `name` in it, or add it.
static uint32_t find_bt(_Atomic uint32_t *slot, const char *name, uint32_t len, int add)
{
	for (;;) {
		uint32_t cur = atomic_load_explicit(slot, memory_order_acquire);
		if (!cur) {
			uint32_t o = add ? new_bt(name, len) : 0;
			if (o)
				atomic_store_explicit(slot, o, memory_order_release);
			return o;
		}
		struct prop_bt *b = at(cur);
		int c = cmp(name, len, b->name, b->namelen);
		if (c == 0)
			return cur;
		slot = c < 0 ? &b->left : &b->right;
	}
}

static struct prop_info *find(const char *name, int add)
{
	uint32_t cur = 0; /* the root node */
	for (const char *part = name;;) {
		const char *dot = strchr(part, '.');
		uint32_t len = dot ? (uint32_t)(dot - part) : (uint32_t)strlen(part);
		if (!len)
			return NULL;
		cur = find_bt(&((struct prop_bt *)at(cur))->children, part, len, add);
		if (!cur)
			return NULL;
		if (!dot)
			break;
		part = dot + 1;
	}
	struct prop_bt *b = at(cur);
	uint32_t p = atomic_load_explicit(&b->prop, memory_order_acquire);
	if (p || !add)
		return p ? at(p) : NULL;
	size_t nlen = strlen(name);
	p = allocate(sizeof(struct prop_info) + nlen + 1);
	if (!p)
		return NULL;
	struct prop_info *pi = at(p);
	memcpy(pi->name, name, nlen);
	atomic_store_explicit(&pi->serial, 0, memory_order_relaxed); /* empty until set */
	atomic_store_explicit(&b->prop, p, memory_order_release);
	return pi;
}

static void wake(_Atomic uint32_t *addr)
{
	syscall(SYS_futex, addr, FUTEX_WAKE, INT32_MAX, NULL, NULL, 0);
}

// SystemProperties::Update, or Add for a new property.
static uint32_t set(const char *name, const char *value, int serving)
{
	size_t vlen = strlen(value);
	if (vlen >= PROP_VALUE_MAX)
		return PROP_ERROR_INVALID_VALUE;
	struct prop_info *pi = find(name, 0);
	int added = !pi;
	if (pi && serving && strncmp(name, "ro.", 3) == 0)
		return PROP_ERROR_READ_ONLY_PROPERTY;
	if (!pi && !(pi = find(name, 1)))
		return PROP_ERROR_SET_FAILED;
	uint32_t serial = atomic_load_explicit(&pi->serial, memory_order_relaxed);
	if (!added) {
		memcpy(at(DIRTY_BACKUP), pi->value, (serial >> 24) + 1);
		atomic_thread_fence(memory_order_release);
		serial |= 1;
		atomic_store_explicit(&pi->serial, serial, memory_order_relaxed);
	}
	memset(pi->value, 0, sizeof(pi->value));
	memcpy(pi->value, value, vlen);
	atomic_thread_fence(memory_order_release);
	/* Bit 0 is the dirty bit: a new property starts clean at its length. */
	atomic_store_explicit(&pi->serial,
			      ((uint32_t)vlen << 24) | (added ? 0 : ((serial + 1) & 0xffffff)),
			      memory_order_relaxed);
	if (!added)
		wake(&pi->serial);
	atomic_store_explicit(&pa->serial, atomic_load_explicit(&pa->serial, memory_order_relaxed) + 1,
			      memory_order_release);
	wake(&pa->serial);
	return PROP_SUCCESS;
}

static int load(const char *path)
{
	FILE *f = fopen(path, "re");
	if (!f) {
		fprintf(stderr, "q25-ims-props: %s: %s\n", path, strerror(errno));
		return -1;
	}
	char *line = NULL;
	size_t cap = 0;
	ssize_t n;
	int rc = 0;
	while ((n = getline(&line, &cap, f)) > 0) {
		while (n && (line[n - 1] == '\n' || line[n - 1] == '\r'))
			line[--n] = 0;
		char *s = line + strspn(line, " \t");
		char *eq = strchr(s, '=');
		if (*s == '#' || !eq || eq == s)
			continue;
		*eq = 0;
		uint32_t r = set(s, eq + 1, 0);
		if (r == PROP_ERROR_SET_FAILED) {
			fprintf(stderr, "q25-ims-props: no room for %s\n", s);
			rc = -1;
			break;
		}
	}
	free(line);
	fclose(f);
	return rc;
}

static int build(const char *out, char **files, int nfiles)
{
	static uint8_t buf[PA_SIZE];
	pa = (struct prop_area *)buf;
	pa->magic = PROP_AREA_MAGIC;
	pa->version = PROP_AREA_VERSION;
	pa->bytes_used = FIRST_FREE;
	for (int i = 0; i < nfiles; i++)
		if (load(files[i]) < 0)
			return 1;
	// Bionic maps it only if root-owned and not group- or world-writable.
	char tmp[4096];
	snprintf(tmp, sizeof(tmp), "%s.new", out);
	int fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0444);
	if (fd < 0 || write(fd, buf, sizeof(buf)) != (ssize_t)sizeof(buf) || fsync(fd) < 0 ||
	    close(fd) < 0 || rename(tmp, out) < 0) {
		fprintf(stderr, "q25-ims-props: %s: %s\n", out, strerror(errno));
		return 1;
	}
	return 0;
}

static int read_all(int fd, void *buf, size_t len)
{
	for (size_t got = 0; got < len;) {
		ssize_t n = recv(fd, (char *)buf + got, len - got, MSG_WAITALL);
		if (n <= 0)
			return -1;
		got += (size_t)n;
	}
	return 0;
}

static int read_string(int fd, char *buf, size_t max)
{
	uint32_t len;
	if (read_all(fd, &len, sizeof(len)) || len >= max || read_all(fd, buf, len))
		return -1;
	buf[len] = 0;
	return 0;
}

// One client: PROP_MSG_SETPROP2, name, value; reply with the result.
static void handle(int c)
{
	uint32_t cmd, result;
	char name[PROP_NAME_MAX], value[PROP_VALUE_MAX + 1];
	struct timeval tv = { .tv_sec = 2 };
	setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
	if (read_all(c, &cmd, sizeof(cmd)) || cmd != PROP_MSG_SETPROP2)
		return;
	if (read_string(c, name, sizeof(name)))
		result = PROP_ERROR_INVALID_NAME;
	else if (read_string(c, value, sizeof(value)))
		result = PROP_ERROR_INVALID_VALUE;
	else
		result = set(name, value, 1);
	printf("%s=%s: %s\n", name, value, result == PROP_SUCCESS ? "set" : "refused");
	send(c, &result, sizeof(result), MSG_NOSIGNAL);
}

static int serve(const char *area, const char *path)
{
	int fd = open(area, O_RDWR | O_CLOEXEC);
	if (fd < 0)
		return perror(area), 1;
	pa = mmap(NULL, PA_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (pa == MAP_FAILED || pa->magic != PROP_AREA_MAGIC || pa->version != PROP_AREA_VERSION) {
		fprintf(stderr, "q25-ims-props: %s: not a property area\n", area);
		return 1;
	}
	struct sockaddr_un addr = { .sun_family = AF_UNIX };
	if (strlen(path) >= sizeof(addr.sun_path))
		return 2;
	strcpy(addr.sun_path, path);
	unlink(path);
	int s = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
	if (s < 0 || bind(s, (struct sockaddr *)&addr, sizeof(addr)) < 0 || chmod(path, 0666) < 0 ||
	    listen(s, 8) < 0)
		return perror(path), 1;
	setvbuf(stdout, NULL, _IOLBF, 0);
	for (;;) {
		int c = accept4(s, NULL, NULL, SOCK_CLOEXEC);
		if (c < 0) {
			if (errno == EINTR)
				continue;
			return 1;
		}
		handle(c);
		close(c);
	}
}

int main(int argc, char **argv)
{
	if (argc == 4 && strcmp(argv[1], "serve") == 0)
		return serve(argv[2], argv[3]);
	if (argc >= 3 && strcmp(argv[1], "serve") != 0)
		return build(argv[1], argv + 2, argc - 2);
	fprintf(stderr, "usage: q25-ims-props <area> <props file>... | serve <area> <socket>\n");
	return 2;
}
