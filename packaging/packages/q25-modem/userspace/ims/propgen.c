// SPDX-License-Identifier: Apache-2.0
// q25-ims-props: Android system properties as bionic reads them, without
// Android's init: one pre-split property area (bionic's ContextsPreSplit,
// /dev/__properties__ as a file) built from `name=value` lines, the format
// of build.prop. Later lines win; values longer than PROP_VALUE_MAX - 1 are
// skipped (bionic's long properties need the serialized contexts).
//
//   q25-ims-props <out> <props file>...
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define PA_SIZE (128 * 1024)
#define PROP_AREA_MAGIC 0x504f5250u
#define PROP_AREA_VERSION 0xfc6ed0abu
#define PROP_VALUE_MAX 92
#define HEADER_SIZE (32 * 4)	/* bytes_used, serial, magic, version, reserved[28] */

struct prop_bt {
	uint32_t namelen, prop, left, right, children;
	char name[];
};

struct prop_info {
	uint32_t serial;
	char value[PROP_VALUE_MAX];
	char name[];
};

static uint8_t area[PA_SIZE];
static uint32_t *const header = (uint32_t *)area;
static uint8_t *const data = area + HEADER_SIZE;
#define bytes_used header[0]

static uint32_t allocate(size_t size)
{
	size_t aligned = (size + 3) & ~(size_t)3;
	if (bytes_used + aligned > PA_SIZE - HEADER_SIZE)
		return 0;
	uint32_t offset = bytes_used;
	bytes_used += aligned;
	return offset;
}

static struct prop_bt *bt(uint32_t offset)
{
	return (struct prop_bt *)(data + offset);
}

static uint32_t new_bt(const char *name, uint32_t len)
{
	uint32_t o = allocate(sizeof(struct prop_bt) + len + 1);
	if (o) {
		bt(o)->namelen = len;
		memcpy(bt(o)->name, name, len);
	}
	return o;
}

// bionic's cmp_prop_name: by length, then bytes.
static int cmp(const char *a, uint32_t alen, const char *b, uint32_t blen)
{
	return alen != blen ? (alen < blen ? -1 : 1) : strncmp(a, b, alen);
}

// One level of the trie is a binary tree; find or add `name` in it.
static uint32_t find_bt(uint32_t root, const char *name, uint32_t len)
{
	uint32_t cur = root;
	for (;;) {
		int c = cmp(name, len, bt(cur)->name, bt(cur)->namelen);
		if (c == 0)
			return cur;
		uint32_t *next = c < 0 ? &bt(cur)->left : &bt(cur)->right;
		if (!*next) {
			uint32_t o = new_bt(name, len);
			if (o)
				*next = o;
			return o;
		}
		cur = *next;
	}
}

static int add(const char *name, const char *value)
{
	size_t vlen = strlen(value);
	if (vlen >= PROP_VALUE_MAX)
		return 0;
	uint32_t cur = 0; /* the root node, at offset 0 */
	for (const char *part = name;;) {
		const char *dot = strchr(part, '.');
		uint32_t len = dot ? (uint32_t)(dot - part) : (uint32_t)strlen(part);
		if (!len)
			return -1;
		if (!bt(cur)->children) {
			uint32_t o = new_bt(part, len);
			if (!o)
				return -1;
			bt(cur)->children = o;
		}
		cur = find_bt(bt(cur)->children, part, len);
		if (!cur)
			return -1;
		if (!dot)
			break;
		part = dot + 1;
	}
	struct prop_info *pi;
	if (bt(cur)->prop) {
		pi = (struct prop_info *)(data + bt(cur)->prop);
	} else {
		size_t nlen = strlen(name);
		uint32_t o = allocate(sizeof(struct prop_info) + nlen + 1);
		if (!o)
			return -1;
		pi = (struct prop_info *)(data + o);
		memcpy(pi->name, name, nlen);
		bt(cur)->prop = o;
	}
	memset(pi->value, 0, sizeof(pi->value));
	memcpy(pi->value, value, vlen);
	pi->serial = (uint32_t)vlen << 24;
	return 0;
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
		if (add(s, eq + 1) < 0) {
			fprintf(stderr, "q25-ims-props: no room for %s\n", s);
			rc = -1;
			break;
		}
	}
	free(line);
	fclose(f);
	return rc;
}

int main(int argc, char **argv)
{
	if (argc < 3) {
		fprintf(stderr, "usage: q25-ims-props <out> <props file>...\n");
		return 2;
	}
	header[2] = PROP_AREA_MAGIC;
	header[3] = PROP_AREA_VERSION;
	bytes_used = sizeof(struct prop_bt); /* the empty root */
	for (int i = 2; i < argc; i++)
		if (load(argv[i]) < 0)
			return 1;
	// Bionic maps it only if root-owned and not group- or world-writable.
	char tmp[4096];
	snprintf(tmp, sizeof(tmp), "%s.new", argv[1]);
	int fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0444);
	if (fd < 0 || write(fd, area, sizeof(area)) != (ssize_t)sizeof(area) || fsync(fd) < 0 ||
	    close(fd) < 0 || rename(tmp, argv[1]) < 0) {
		fprintf(stderr, "q25-ims-props: %s: %s\n", argv[1], strerror(errno));
		return 1;
	}
	return 0;
}
