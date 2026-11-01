/*
 * SPDX-FileCopyrightText: 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <fnmatch.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/types.h>
#include <unistd.h>

#include <android/log.h>
#include <cutils/properties.h>

#include "ccci_ioctl.h"		/* struct ccci_header, CCCI_DEV_FS */
#include "ccci_rpc.h"		/* FS_NO_ERROR .. FS_MEM_OVERFLOW, shared with RPC */
#include "ccci_fs_wire.h"	/* verified CMPT structs, channel/size constants */

#include <sys/vfs.h>

#define FS_OP_OPEN		0x1001
#define FS_OP_SEEK		0x1002
#define FS_OP_READ		0x1003
#define FS_OP_WRITE		0x1004
#define FS_OP_CLOSE		0x1005
#define FS_OP_CLOSE_ALL		0x1006
#define FS_OP_CREATE_DIR	0x1007
#define FS_OP_REMOVE_DIR	0x1008
#define FS_OP_GET_FILE_SIZE	0x1009
#define FS_OP_GET_FOLDER_SIZE	0x100a
#define FS_OP_RENAME		0x100b
#define FS_OP_MOVE		0x100c
#define FS_OP_COUNT		0x100d
#define FS_OP_GET_DISK_INFO	0x100e
#define FS_OP_DELETE		0x100f
#define FS_OP_GET_ATTRIBUTES	0x1010
#define FS_OP_OPEN_EX		0x1011	/* Open, but the reply also carries the file size */
#define FS_OP_FIND_FIRST	0x1012
#define FS_OP_FIND_NEXT		0x1013
#define FS_OP_FIND_CLOSE	0x1014
#define FS_OP_CLOSE_ALL2	0x1017
#define FS_OP_XDELETE		0x1018
#define FS_OP_LF		0x1015	/* stock logs "LF: %d", answers a constant 0 */
#define FS_OP_UK		0x1016	/* stock logs "UK: %d", answers a constant 1 */
#define FS_OP_CDF		0x1019	/* stock logs "CDF: %d", answers a constant 0 */
#define FS_OP_SDF		0x101c	/* stock logs "SDF: %d", answers a constant 0 */
#define FS_OP_GET_DRIVE		0x101a
#define FS_OP_GET_CLUSTER_SIZE	0x101b
#define FS_OP_OTP_WRITE		0x101d
#define FS_OP_OTP_READ		0x101e
#define FS_OP_OTP_QUERY_LENGTH	0x101f
#define FS_OP_OTP_LOCK		0x1020
#define FS_OP_RESTORE		0x1021
#define FS_OP_CMPT_READ		0x1022	/* compound open+seek+read+close, one request */
#define FS_OP_BIN_REGION	0x1023
#define FS_OP_CMPT_WRITE	0x1024	/* compound open+seek+write+close */
#define FS_OP_GET_FILE_DETAIL	0x1025

#define FS_DISK_INFO_DWORDS	21	/* 84 bytes, the second response segment's length */
#define FS_FILE_DETAIL_BYTES	24	/* GetFileDetail's second segment (stock: v46[4] = 24) */

/* Ordinary filesystem writes are ON. The project rule is "writes only once NVRAM backups are
 * verified" -- they are: a full dump holds nvdata.bin (64M), nvram.bin (64M), nvcfg.bin (32M)
 * and protect1/2.bin (8M each), so anything these ops can damage is restorable.
 *
 * 🔴 OTP is the one exception and stays OFF by default. One-time-programmable fuses are in the
 * die, not in a partition: no backup can undo a wrong write or a lock, and a single misparsed
 * request would be permanent. The handlers below are written and compiled -- flip
 * MINDONE_FS_ALLOW_OTP_WRITE to 1 deliberately, never as a default.
 */
#ifndef MINDONE_FS_ALLOW_WRITES
#define MINDONE_FS_ALLOW_WRITES 1
#endif
#ifndef MINDONE_FS_ALLOW_OTP_WRITE
#define MINDONE_FS_ALLOW_OTP_WRITE 0
#endif

/* Open file handles.
 *
 * The modem addresses files by a small integer it gets back from Open, so the daemon has to keep
 * the mapping. The table is deliberately tiny and fixed: the stock daemon logs a FS_FILE_MAX of
 * its own, and a modem that leaks handles should hit a clean "too many open files" rather than
 * grow this process without bound. Index 0 is never handed out, so a handle is always positive
 * and a negative return is unambiguously an error.
 */
#define FS_HANDLE_MAX	32

static int g_fs_handles[FS_HANDLE_MAX];

static void fs_handle_init(void)
{
	unsigned i;

	for (i = 0; i < FS_HANDLE_MAX; i++)
		g_fs_handles[i] = -1;
}

#define FS_FLAG_READ_ONLY	0x00000100u
#define FS_FLAG_CREATE		0x00010000u
#define FS_FLAG_CREATE_ALWAYS	0x00020000u
#define FS_FLAG_NONBLOCK	0x10000000u
#define FS_OPEN_MODE		0660

static int fs_open_flags(uint32_t modem_flags)
{
	int f = (modem_flags & FS_FLAG_READ_ONLY) ? O_RDONLY : O_RDWR;

	if (modem_flags & FS_FLAG_CREATE)
		f = O_RDWR | O_CREAT;
	if (modem_flags & FS_FLAG_CREATE_ALWAYS)
		f = O_RDWR | O_CREAT | O_TRUNC;
	if (modem_flags & FS_FLAG_NONBLOCK)
		f |= O_NONBLOCK;

#if !MINDONE_FS_ALLOW_WRITES
	/* Downgrade rather than refuse: a modem that only wanted to read a file it declared
	 * writable still gets served. */
	f &= ~(O_RDWR | O_CREAT | O_TRUNC);
#endif
	return f;
}

static int fs_handle_open(const char *real, uint32_t modem_flags)
{
	unsigned i;
	int flags = fs_open_flags(modem_flags);

	for (i = 1; i < FS_HANDLE_MAX; i++) {
		if (g_fs_handles[i] >= 0)
			continue;
		g_fs_handles[i] = open(real, flags, FS_OPEN_MODE);
		if (g_fs_handles[i] < 0)
			return (errno == ENOENT) ? FS_ERR_ENOENT_MAPPED : FS_ERR_GENERIC_MAPPED;
		return (int)i;
	}
	return FS_ERR_EMFILE_MAPPED;
}

static int32_t fs_handle_close(int32_t h)
{
	if (h <= 0 || h >= FS_HANDLE_MAX || g_fs_handles[h] < 0)
		return FS_PARAM_ERROR;
	close(g_fs_handles[h]);
	g_fs_handles[h] = -1;
	return FS_NO_ERROR;
}

static ssize_t fs_handle_read(int32_t h, void *buf, size_t cap, size_t want)
{
	if (h <= 0 || h >= FS_HANDLE_MAX || g_fs_handles[h] < 0)
		return -1;
	if (want > cap)
		want = cap;
	return read(g_fs_handles[h], buf, want);
}

static ssize_t fs_handle_write(int32_t h, const void *buf, size_t len)
{
#if MINDONE_FS_ALLOW_WRITES
	if (h <= 0 || h >= FS_HANDLE_MAX || g_fs_handles[h] < 0)
		return -1;
	return write(g_fs_handles[h], buf, len);
#else
	(void)h; (void)buf; (void)len;
	return -1;
#endif
}

/* Whence values are the modem's, and they happen to match SEEK_SET/CUR/END (0/1/2); anything
 * else is refused rather than passed through to lseek. */
static int64_t fs_handle_seek(int32_t h, int32_t offset, int32_t whence)
{
	if (h <= 0 || h >= FS_HANDLE_MAX || g_fs_handles[h] < 0)
		return -1;
	if (whence != SEEK_SET && whence != SEEK_CUR && whence != SEEK_END)
		return -1;
	return (int64_t)lseek(g_fs_handles[h], (off_t)offset, whence);
}

static int32_t fs_handle_close_all(void)
{
	unsigned i;
	int32_t n = 0;

	for (i = 1; i < FS_HANDLE_MAX; i++) {
		if (g_fs_handles[i] < 0)
			continue;
		close(g_fs_handles[i]);
		g_fs_handles[i] = -1;
		n++;
	}
	return n;
}

/* Directory enumeration for FindFirst/FindNext/FindClose (ops 0x1012-0x1014).
 *
 * The modem walks a directory by getting a search handle from FindFirst and pulling one entry
 * per FindNext until the daemon reports "no more". Kept in its own small fixed table for the
 * same reason as the file handles: a leaking modem should hit a clean limit.
 */
#define FS_FIND_MAX	8

struct fs_find_slot {
	DIR *dir;
	char pattern[64];	/* the modem's name pattern, "*" when it asked for everything */
	char real_dir[512];	/* kept so FindNext can stat an entry without re-deriving the path */
};

static struct fs_find_slot g_fs_finds[FS_FIND_MAX];

static void fs_find_init(void)
{
	memset(g_fs_finds, 0, sizeof(g_fs_finds));
}

static int fs_find_open(const char *real_dir, const char *pattern)
{
	unsigned i;

	for (i = 1; i < FS_FIND_MAX; i++) {
		if (g_fs_finds[i].dir != NULL)
			continue;
		g_fs_finds[i].dir = opendir(real_dir);
		if (g_fs_finds[i].dir == NULL)
			return (errno == ENOENT) ? FS_ERR_ENOENT_MAPPED : FS_ERR_GENERIC_MAPPED;
		snprintf(g_fs_finds[i].pattern, sizeof(g_fs_finds[i].pattern), "%s",
			 (pattern && *pattern) ? pattern : "*");
		snprintf(g_fs_finds[i].real_dir, sizeof(g_fs_finds[i].real_dir), "%s", real_dir);
		return (int)i;
	}
	return FS_ERR_EMFILE_MAPPED;
}

static int32_t fs_find_close(int32_t h)
{
	if (h <= 0 || h >= FS_FIND_MAX || g_fs_finds[h].dir == NULL)
		return FS_PARAM_ERROR;
	closedir(g_fs_finds[h].dir);
	g_fs_finds[h].dir = NULL;
	g_fs_finds[h].pattern[0] = '\0';
	return FS_NO_ERROR;
}

/* Returns 0 and fills name/st on success, -1 when the directory is exhausted. "." and ".." are
 * skipped: the modem asks for files, and handing it the two special entries only makes it issue
 * pointless follow-up requests. */
static int fs_find_next(int32_t h, char *name, size_t name_cap, struct stat *st)
{
	struct dirent *de;
	const char *real_dir;

	if (h <= 0 || h >= FS_FIND_MAX || g_fs_finds[h].dir == NULL)
		return -1;
	real_dir = g_fs_finds[h].real_dir;

	while ((de = readdir(g_fs_finds[h].dir)) != NULL) {
		char full[PATH_MAX];

		if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0)
			continue;
		if (fnmatch(g_fs_finds[h].pattern, de->d_name, 0) != 0)
			continue;
		snprintf(name, name_cap, "%s", de->d_name);
		memset(st, 0, sizeof(*st));
		if ((size_t)snprintf(full, sizeof(full), "%s/%s", real_dir, de->d_name)
		    < sizeof(full))
			(void)stat(full, st);
		return 0;
	}
	return -1;
}

/* Recursive delete for XDelete (0x1018). Depth is bounded because the modem's own tree is
 * shallow and an unbounded recursion here would be a denial of service on a malformed reply. */
#define FS_XDELETE_MAX_DEPTH 8

static int32_t fs_rm_recursive(const char *path, unsigned depth)
{
	struct stat st;
	DIR *d;
	struct dirent *de;

	if (depth > FS_XDELETE_MAX_DEPTH)
		return FS_ERR_GENERIC_MAPPED;
	if (lstat(path, &st) != 0)
		return FS_ERR_ENOENT_MAPPED;
	if (!S_ISDIR(st.st_mode))
		return (unlink(path) == 0) ? FS_NO_ERROR : FS_ERR_GENERIC_MAPPED;

	d = opendir(path);
	if (d == NULL)
		return FS_ERR_GENERIC_MAPPED;
	while ((de = readdir(d)) != NULL) {
		char child[PATH_MAX];

		if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0)
			continue;
		if ((size_t)snprintf(child, sizeof(child), "%s/%s", path, de->d_name)
		    >= sizeof(child))
			continue;
		(void)fs_rm_recursive(child, depth + 1);
	}
	closedir(d);
	return (rmdir(path) == 0) ? FS_NO_ERROR : FS_ERR_GENERIC_MAPPED;
}

/* Sum of regular-file sizes under a directory, for GetFolderSize (0x100a). */
static int64_t fs_folder_size(const char *path, unsigned depth)
{
	DIR *d;
	struct dirent *de;
	int64_t total = 0;

	if (depth > FS_XDELETE_MAX_DEPTH)
		return 0;
	d = opendir(path);
	if (d == NULL)
		return -1;
	while ((de = readdir(d)) != NULL) {
		char child[PATH_MAX];
		struct stat st;

		if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0)
			continue;
		if ((size_t)snprintf(child, sizeof(child), "%s/%s", path, de->d_name)
		    >= sizeof(child))
			continue;
		if (lstat(child, &st) != 0)
			continue;
		if (S_ISDIR(st.st_mode)) {
			int64_t sub = fs_folder_size(child, depth + 1);

			if (sub > 0)
				total += sub;
		} else if (S_ISREG(st.st_mode)) {
			total += (int64_t)st.st_size;
		}
	}
	closedir(d);
	return total;
}

/* Number of entries in a directory, for Count (0x100d). */
static int32_t fs_dir_count(const char *path)
{
	DIR *d;
	struct dirent *de;
	int32_t n = 0;

	d = opendir(path);
	if (d == NULL)
		return -1;
	while ((de = readdir(d)) != NULL) {
		if (strcmp(de->d_name, ".") == 0 || strcmp(de->d_name, "..") == 0)
			continue;
		n++;
	}
	closedir(d);
	return n;
}

#define FS_ATTR_READONLY	0x01	/* bit 0, from FS_IsReadOnly() == 1 */
#define FS_ATTR_DIRECTORY	0x10	/* bit 4, set when FS_IsDIR() returns S_IFDIR */

static const char *fs_drive_dir(const char *path);



static int fs_resolve(const char *path, char *out, size_t cap)
{
	const char *dir = fs_drive_dir(path);
	size_t i, n;

	if (!path[0] || path[1] != ':')
		return -1;
	n = strlen(dir);
	if (n + 1 >= cap)
		return -1;
	memcpy(out, dir, n);

	for (i = 2; path[i]; i++) {
		if (path[i] == '.' && path[i + 1] == '.')
			return -1;			/* relative path, refused as in stock */
		if (n + 1 >= cap)
			return -1;
		out[n++] = (path[i] == '\\') ? '/' : path[i];
	}
	out[n] = '\0';
	return 0;
}

/* Drive letter -> directory. The stock daemon keeps a 10-entry table of 36-byte strings at
 * 0x2e910 (/mnt/vendor/nvdata/md, /mnt/vendor/protect_f/md, /mnt/vendor/protect_s/md,
 * /vendor/firmware, /mnt/vendor/nvdata/md_cmn, /data/vendor/mdlpm, /vendor/etc/mdota,
 * /mnt/vendor/nvcfg, /vendor/etc/md, /data/vendor_de/md) and statfs()es the selected one.
 * Which letter selects which index is not yet read out of the binary, so this maps the drive
 * the modem actually asks about and falls back to the NVRAM data directory otherwise - the
 * geometry reported is the filesystem's either way, which is what the query is for. */
static const char *fs_drive_dir(const char *path)
{
	switch (path[0]) {
	case 'Z': case 'z':
		/* The system drive - FS_CCCI_GetDrive returns 'Z' for FS_DRIVE_I_SYSTEM. Confirmed
		 * on the device: /mnt/vendor/nvdata/md/NVRAM holds exactly the directories the
		 * modem asks about (BACKUP, CALIBRAT, INFO_FILE, NVD_CORE, ...). */
		return "/mnt/vendor/nvdata/md";
	case 'X': case 'x':
		return "/mnt/vendor/protect_f/md";
	case 'Y': case 'y':
		return "/mnt/vendor/protect_s/md";
	default:
		return "/mnt/vendor/nvdata";
	}
}
#include "nvram_shim.h"

#define LOG_TAG "mindone_fsd"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

#define FS_MAX_SEGS	8

struct fs_req {
	uint32_t op_id;
	unsigned nseg;
	const unsigned char *seg[FS_MAX_SEGS];
	uint32_t seglen[FS_MAX_SEGS];
};

static int fs_parse_req(const unsigned char *payload, size_t len, struct fs_req *out)
{
	size_t off = 8;
	unsigned i;

	if (len < 8)
		return -1;
	memcpy(&out->op_id, payload, 4);
	memcpy(&out->nseg, payload + 4, 4);
	if (out->nseg > FS_MAX_SEGS) {
		LOGW("%s: %u segments, more than this daemon indexes", __func__, out->nseg);
		return -1;
	}
	for (i = 0; i < out->nseg; i++) {
		uint32_t seglen;

		if (off + 4 > len)
			return -1;
		memcpy(&seglen, payload + off, 4);
		off += 4;
		if (seglen > len - off)
			return -1;
		out->seg[i] = payload + off;
		out->seglen[i] = seglen;
		off += (seglen + 3u) & ~3u;
	}
	return 0;
}

/* UTF-16LE to ASCII. Every name on this wire is a drive letter or an NVRAM file name, all of
 * which are plain ASCII; anything else is refused rather than silently mangled. */
static int fs_wcs_to_str(const unsigned char *src, uint32_t bytes, char *out, size_t cap)
{
	size_t i, chars = bytes / 2;

	if (chars >= cap)
		return -1;
	for (i = 0; i < chars; i++) {
		uint16_t wc;

		memcpy(&wc, src + i * 2, sizeof(wc));
		if (!wc)
			break;
		if (wc >= 0x80)
			return -1;
		out[i] = (char)wc;
	}
	out[i] = '\0';
	return 0;
}

/* ------------------------------------------------------------------ */
/* Directory roots -- confirmed by exhaustive strings(1) over the stock  */
/* real on this single-modem board; md2/md3/md5 are listed for           */
/* completeness and rejected at runtime (FS_NO_MATCH) since this board   */
/* has no such modem instance.                                          */
/* ------------------------------------------------------------------ */
struct fs_root {
	const char *prefix;	/* what the MD-supplied filename may start with */
	const char *real_dir;	/* where it actually maps to on our filesystem */
	int live;		/* 1 if this instance really exists on our board */
};

static const struct fs_root kRoots[] = {
	{ "/nvdata/md_cmn",	"/mnt/vendor/nvdata/md_cmn",	1 },
	{ "/nvdata/md3_v",	"/mnt/vendor/nvdata/md3_v",	0 },
	{ "/nvdata/md2",	"/mnt/vendor/nvdata/md2",	0 },
	{ "/nvdata/md3",	"/mnt/vendor/nvdata/md3",	0 },
	{ "/nvdata/md5",	"/mnt/vendor/nvdata/md5",	0 },
	{ "/nvdata/md",		"/mnt/vendor/nvdata/md",	1 },
	{ "/protect_f/md2",	"/mnt/vendor/protect_f/md2",	0 },
	{ "/protect_f/md3",	"/mnt/vendor/protect_f/md3",	0 },
	{ "/protect_f/md",	"/mnt/vendor/protect_f/md",	1 },
	{ "/protect_s/md2",	"/mnt/vendor/protect_s/md2",	0 },
	{ "/protect_s/md3",	"/mnt/vendor/protect_s/md3",	0 },
	{ "/protect_s/md",	"/mnt/vendor/protect_s/md",	1 },
	{ "/nvcfg",		"/mnt/vendor/nvcfg",		1 },
};
#define N_ROOTS (sizeof(kRoots) / sizeof(kRoots[0]))

/*
 * Resolve an MD-supplied "filename" (root-relative, per the stock daemon's
 * own directory-root strings) into a real, sandboxed absolute path.
 * Rejects any ".." path component defensively, regardless of wire-parsing
 * correctness (see safety point 3 in the top comment).
 */
static int __attribute__((unused)) path_resolve(const char *md_filename, char *out, size_t out_len)
{
	size_t i;

	if (!md_filename || md_filename[0] != '/') {
		LOGW("path_resolve: rejecting non-absolute/empty name %s",
		     md_filename ? md_filename : "(null)");
		return FS_PARAM_ERROR;
	}
	if (strstr(md_filename, "..") != NULL) {
		LOGE("path_resolve: rejecting path-traversal attempt: %s", md_filename);
		return FS_PARAM_ERROR;
	}
	for (i = 0; i < N_ROOTS; i++) {
		size_t plen = strlen(kRoots[i].prefix);

		if (strncmp(md_filename, kRoots[i].prefix, plen) == 0) {
			if (!kRoots[i].live) {
				LOGW("path_resolve: %s maps to dead modem instance root %s (single-modem board)",
				     md_filename, kRoots[i].prefix);
				return FS_NO_MATCH;
			}
			if ((size_t)snprintf(out, out_len, "%s%s", kRoots[i].real_dir,
					      md_filename + plen) >= out_len)
				return FS_MEM_OVERFLOW;
			return FS_NO_ERROR;
		}
	}
	LOGW("path_resolve: %s does not match any known root", md_filename);
	return FS_NO_MATCH;
}

/* errno -> MD result code, per FS_ErrorConv (VA 0x1af38-0x1afd0) in the
 * stock binary -- the four arms actually confirmed there; anything else
 * falls through to the confirmed default arm. See ccci_fs_wire.h for the
 * address citations of each constant.
 */
static int errno_to_fs_result(int err)
{
	switch (err) {
	case ENOENT:
		return FS_ERR_ENOENT_MAPPED;	/* -9 */
	case EACCES:
		return FS_ERR_EACCES_MAPPED;	/* -16 */
	case EMFILE:
		return FS_ERR_EMFILE_MAPPED;	/* -5, == FS_FUNC_FAIL */
	default:
		return FS_ERR_GENERIC_MAPPED;	/* -18 */
	}
}

/* ------------------------------------------------------------------ */
/* file_handle table                                                    */
/* ------------------------------------------------------------------ */
#define MAX_OPEN_HANDLES 32

struct fs_handle {
	int fd;		/* -1 if free */
	char path[PATH_MAX];
};
static struct fs_handle g_handles[MAX_OPEN_HANDLES];

static void handles_init(void)
{
	int i;

	for (i = 0; i < MAX_OPEN_HANDLES; i++)
		g_handles[i].fd = -1;
}

/* Handle numbers we hand back are 1-based slot indices. 0/negative means
 * "no handle" on the wire (struct ccci_fs_cmpt_write_req.file_handle < 0
 * means "please open fresh", per the stock CMPT_Write logic).
 */
static int handle_alloc(int fd, const char *path)
{
	int i;

	for (i = 0; i < MAX_OPEN_HANDLES; i++) {
		if (g_handles[i].fd < 0) {
			g_handles[i].fd = fd;
			snprintf(g_handles[i].path, sizeof(g_handles[i].path), "%s", path);
			return i + 1;
		}
	}
	return -1;
}

static int handle_get_fd(int handle)
{
	if (handle < 1 || handle > MAX_OPEN_HANDLES)
		return -1;
	return g_handles[handle - 1].fd;
}

static void handle_free(int handle)
{
	if (handle < 1 || handle > MAX_OPEN_HANDLES)
		return;
	g_handles[handle - 1].fd = -1;
}

static void log_hexdump(const char *tag, const void *buf, size_t len)
{
	const unsigned char *p = buf;
	char line[3 * 16 + 1];
	size_t i, j;

	if (len > 512)
		len = 512; /* cap log spam; the point is wire-format recovery, not full capture */
	for (i = 0; i < len; i += 16) {
		size_t n = (len - i < 16) ? (len - i) : 16;

		for (j = 0; j < n; j++)
			snprintf(line + j * 3, 4, "%02x ", p[i + j]);
		LOGI("%s [%04zx] %s", tag, i, line);
	}
}

/* ------------------------------------------------------------------ */
/* Response builders -- both formats verified in ccci_fs_wire.h.        */
/* ------------------------------------------------------------------ */

struct fs_seg {
	const void *data;
	size_t len;
};

static size_t build_resp(unsigned char *out, size_t cap, const struct ccci_header *req,
			  uint32_t op_id, const struct fs_seg *segs, unsigned nseg)
{
	uint32_t words[6];
	size_t off = sizeof(words);
	unsigned i;

	if (cap < off)
		return 0;

	memcpy(words, req, sizeof(struct ccci_header));	/* words 0..3 */
	words[0] &= ~0x80000000u;
	words[2] += 1;					/* facing channel */
	words[4] = op_id | 0xFFFF0000u;
	words[5] = nseg;

	for (i = 0; i < nseg; i++) {
		const size_t len = segs[i].len;
		const size_t padded = (len + 3u) & ~(size_t)3u;

		if (off + 4 + padded > cap) {
			LOGE("%s: response would not fit (%zu of %zu bytes)", __func__,
			     off + 4 + padded, cap);
			return 0;
		}
		memcpy(out + off, &(uint32_t){ (uint32_t)len }, 4);
		off += 4;
		memset(out + off, 0, padded);		/* zero the padding, not just the data */
		if (segs[i].data && len)
			memcpy(out + off, segs[i].data, len);
		off += padded;
	}

	words[1] = (uint32_t)off;			/* total length, once it is known */
	memcpy(out, words, sizeof(words));
	return off;
}

/* The common case: one segment carrying nothing but the result code. */
static size_t build_result_resp(unsigned char *out, size_t cap, const struct ccci_header *req,
				 uint32_t op_id, int32_t result)
{
	const struct fs_seg seg = { &result, sizeof(result) };

	return build_resp(out, cap, req, op_id, &seg, 1);
}

/* Result plus one payload segment, e.g. a read or a disk-info answer. */
static size_t build_data_resp(unsigned char *out, size_t out_cap, const struct ccci_header *req,
			       uint32_t op_id, int32_t result, const void *data, size_t data_len)
{
	const struct fs_seg segs[2] = { { &result, sizeof(result) }, { data, data_len } };

	return build_resp(out, out_cap, req, op_id, segs, (data && data_len) ? 2 : 1);
}

/* ------------------------------------------------------------------ */
/* CMPT_Write-shaped request: base = payload start (buffer+0, per the    */
/* stock daemon's own call site -- see the "confirmed anomaly" note in   */
/* the top comment). opid_map bits per ccci_fs_wire.h.                   */
/* ------------------------------------------------------------------ */
static void ensure_parent_dir(const char *path);

/* Reply fields of the stock CMPT_Write: segments {done,err} (8), handle (4), written (4). */
struct cmpt_write_out {
	uint32_t done;
	int32_t err;
	int32_t handle;
	uint32_t written;
};

static int32_t handle_cmpt_write(const struct ccci_fs_cmpt_write_req *req, size_t req_and_data_len,
				  const char *real_path, struct cmpt_write_out *o)
{
	int handle = (req->file_handle >= 0) ? (int)req->file_handle : -1;
	int fd = -1;

	o->done = 0;
	o->handle = -1;
	o->written = 0;

	if (handle < 0) {
		int flags;

		if (!(req->opid_map & 0x1))
			return FS_PARAM_ERROR;
		flags = fs_open_flags(req->flag);
		if (flags & O_CREAT)
			ensure_parent_dir(real_path);
		fd = open(real_path, flags, 0660);
		if (fd < 0) {
			LOGW("cmpt_write: open(%s) failed: %s", real_path, strerror(errno));
			return errno_to_fs_result(errno);
		}
		handle = handle_alloc(fd, real_path);
		if (handle < 0) {
			close(fd);
			return FS_MEM_OVERFLOW;
		}
		o->done |= 0x1;
	} else {
		fd = handle_get_fd(handle);
		if (fd < 0)
			return FS_PARAM_ERROR;
	}
	o->handle = handle;

	if (req->opid_map & 0x4) {
		if (lseek(fd, (off_t)req->offset, (int)req->whence) < 0) {
			LOGW("cmpt_write: seek failed: %s", strerror(errno));
			return errno_to_fs_result(errno);
		}
		o->done |= 0x4;
	}

	/* WRITE is bit5 here, bit3 on the read side. */
	if (req->opid_map & 0x20) {
		const unsigned char *data = (const unsigned char *)req + sizeof(*req);
		size_t avail = (req_and_data_len > sizeof(*req)) ? req_and_data_len - sizeof(*req) : 0;
		size_t want = (req->length > 0 && (size_t)req->length <= avail) ? (size_t)req->length : avail;
		ssize_t n = write(fd, data, want);

		if (n < 0) {
			LOGW("cmpt_write: write failed: %s", strerror(errno));
			return errno_to_fs_result(errno);
		}
		o->written = (uint32_t)n;
		o->done |= 0x20;
	}

	if (req->opid_map & 0x10) {
		close(fd);
		handle_free(handle);
		o->handle = -1;
		o->done |= 0x10;
	}

	return FS_NO_ERROR;
}

/* ------------------------------------------------------------------ */
/* CMPT_Read-shaped request: base = payload+0x30, per ccci_fs_wire.h.    */
/* Always opens fresh (the stock handler never reuses a handle on this   */
/* path -- confirmed, see ccci_fs_wire.h) and always closes at the end   */
/* when bit4 is set, matching the stock CMPT_Read control flow.         */
/* ------------------------------------------------------------------ */
static void ensure_parent_dir(const char *path)
{
	char tmp[PATH_MAX];
	char *slash;
	size_t i;

	if ((size_t)snprintf(tmp, sizeof(tmp), "%s", path) >= sizeof(tmp))
		return;
	slash = strrchr(tmp, '/');
	if (!slash || slash == tmp)
		return;
	*slash = '\0';
	for (i = 1; tmp[i]; i++) {
		if (tmp[i] == '/') {
			tmp[i] = '\0';
			mkdir(tmp, 0770);
			tmp[i] = '/';
		}
	}
	mkdir(tmp, 0770);
}

/* Reply fields of the stock CMPT_Read: segments {done,err} (8), file size (4),
 * read_len (4), data (read_len). Returns the stock's internal code: -7 no OPEN bit,
 * -1 open, -2 size, -3 seek, -4 read, -5 close, -6 no CLOSE bit, 0 ok.
 */
struct cmpt_read_out {
	uint32_t done;
	int32_t err;
	uint32_t size;
	uint32_t read_len;
};

static int32_t handle_cmpt_read(const struct ccci_fs_cmpt_read_req *req, const char *real_path,
				 unsigned char *payload_out, size_t payload_cap, struct cmpt_read_out *o)
{
	struct stat st;
	int flags;
	int fd;

	o->done = 0;
	o->err = FS_NO_ERROR;
	o->size = req->size_out;	/* the stock echoes this word when GET_SIZE is not asked */
	o->read_len = 0;

	if (!(req->opid_map & 0x1)) {
		o->err = FS_ERR_GENERIC_MAPPED;
		return -7;
	}
	flags = fs_open_flags(req->flag);
	if (flags & O_CREAT)
		ensure_parent_dir(real_path);
	fd = open(real_path, flags, 0660);
	if (fd < 0) {
		o->err = errno_to_fs_result(errno);
		return -1;
	}
	o->done |= 0x1;

	if (req->opid_map & 0x2) {
		if (fstat(fd, &st) < 0) {
			o->err = errno_to_fs_result(errno);
			close(fd);
			return -2;
		}
		o->size = (uint32_t)st.st_size;
		o->done |= 0x2;
	}

	if (req->opid_map & 0x4) {
		if (lseek(fd, (off_t)req->offset, (int)req->whence) < 0) {
			o->err = errno_to_fs_result(errno);
			close(fd);
			return -3;
		}
		o->done |= 0x4;
	}

	if (req->opid_map & 0x8) {
		size_t want = (req->length <= payload_cap) ? (size_t)req->length : payload_cap;
		ssize_t n = read(fd, payload_out, want);

		if (n < 0) {
			o->err = errno_to_fs_result(errno);
			close(fd);
			return -4;
		}
		o->read_len = (uint32_t)n;
		o->done |= 0x8;
	}

	if (!(req->opid_map & 0x10)) {
		close(fd);
		return -6;
	}
	if (close(fd) < 0) {
		o->err = errno_to_fs_result(errno);
		return -5;
	}
	o->done |= 0x10;
	return 0;
}

static void handle_bin_region_access(const char *filename, int32_t *out_result) __attribute__((unused));
static void handle_bin_region_access(const char *filename, int32_t *out_result)
{
	LOGE("Main: FS_CCCI_OP_BIN_REGION_ACCESS requested for '%s' -- stubbed, returning FS_NO_FEATURE",
	     filename ? filename : "(null)");
	*out_result = FS_NO_FEATURE;
	(void)NVM_RestoreFromBinRegion_OneFile; /* kept linked/referenced, intentionally unused here */
}

/* ------------------------------------------------------------------ */
/* Main dispatch loop                                                   */
/* ------------------------------------------------------------------ */

/* Stock stream framing (WriteToMD): a stream is header(16) + op word(4) + up to
 * 16 KiB. On the wire it travels as packets of at most 0xd94 bytes, each one a
 * header plus the op word plus <= 3456 stream bytes; data[0] bit31 marks "more
 * packets follow".
 */
#define FS_STREAM_SIZE		CCCI_FS_INST_BUF_A
#define FS_PKT_PREFIX		20
#define FS_PKT_DATA_MAX		(CCCI_FS_READ_CHUNK - FS_PKT_PREFIX)
#define FS_PKT_MORE		0x80000000u

static ssize_t fs_read_stream(int fd, unsigned char *buf, size_t cap)
{
	unsigned char pkt[4096];
	size_t len = 0;
	int overflow = 0;
	uint32_t w;

	for (;;) {
		ssize_t n = read(fd, pkt, sizeof(pkt));

		if (n < 0)
			return -1;
		if (n == 0)
			continue;
		if (len == 0) {
			if ((size_t)n > cap)
				overflow = 1;
			else
				memcpy(buf, pkt, (size_t)n);
			len = (size_t)n;
		} else if (n > FS_PKT_PREFIX) {
			size_t add = (size_t)n - FS_PKT_PREFIX;

			if (len + add > cap)
				overflow = 1;
			else
				memcpy(buf + len, pkt + FS_PKT_PREFIX, add);
			len += add;
		}
		if ((size_t)n < sizeof(struct ccci_header))
			break;
		memcpy(&w, pkt, sizeof(w));
		if (!(w & FS_PKT_MORE))
			break;
	}
	if (overflow) {
		LOGE("Main: request stream of %zu bytes exceeds %zu, dropped", len, cap);
		return 0;
	}
	if (len >= sizeof(struct ccci_header)) {
		memcpy(&w, buf, sizeof(w));
		w &= ~FS_PKT_MORE;
		memcpy(buf, &w, sizeof(w));
		w = (uint32_t)len;
		memcpy(buf + 4, &w, sizeof(w));
	}
	return (ssize_t)len;
}

static int fs_write_stream(int fd, const unsigned char *buf, size_t len)
{
	unsigned char pkt[CCCI_FS_READ_CHUNK];
	size_t off = FS_PKT_PREFIX;

	if (len <= CCCI_FS_READ_CHUNK)
		return (write(fd, buf, len) == (ssize_t)len) ? 0 : -1;

	while (off < len) {
		size_t chunk = len - off;
		uint32_t w;

		memcpy(pkt, buf, FS_PKT_PREFIX);
		memcpy(&w, pkt, sizeof(w));
		if (chunk > FS_PKT_DATA_MAX) {
			chunk = FS_PKT_DATA_MAX;
			w |= FS_PKT_MORE;
		} else {
			w &= ~FS_PKT_MORE;
		}
		memcpy(pkt, &w, sizeof(w));
		w = (uint32_t)(chunk + FS_PKT_PREFIX);
		memcpy(pkt + 4, &w, sizeof(w));
		memcpy(pkt + FS_PKT_PREFIX, buf + off, chunk);
		if (write(fd, pkt, chunk + FS_PKT_PREFIX) != (ssize_t)(chunk + FS_PKT_PREFIX))
			return -1;
		off += chunk;
	}
	return 0;
}

static unsigned char rxbuf[FS_STREAM_SIZE];
static unsigned char txbuf[FS_STREAM_SIZE];
static unsigned char rdbuf[FS_STREAM_SIZE - 64];	/* room for the CMPT_Read reply fields */

int main(void)
{
	int fd;

	handles_init();
	LOGI("mindone_fsd starting (md_fsd Ver:mindone-2, CCCI Ver: our-6.12-port)");

	fs_handle_init();
	fs_find_init();

	fd = open(CCCI_DEV_FS, O_RDWR);
	if (fd < 0) {
		LOGE("open(%s) failed: %s", CCCI_DEV_FS, strerror(errno));
		return 1;
	}

	for (;;) {
		ssize_t n = fs_read_stream(fd, rxbuf, sizeof(rxbuf));
		struct ccci_header hdr;
		size_t resp_len;
		uint32_t req_op_id = 0;
		int32_t result = FS_NO_OP;

		if (n < 0) {
			LOGE("read(%s) failed: %s", CCCI_DEV_FS, strerror(errno));
			break;
		}
		if (n == 0)
			continue;

		log_hexdump("rx", rxbuf, (size_t)n);

		if ((size_t)n < sizeof(hdr)) {
			LOGW("Main: short read, %zd bytes, less than ccci_header (%zu)",
			     n, sizeof(hdr));
			continue;
		}
		memcpy(&hdr, rxbuf, sizeof(hdr));

		if (hdr.channel != CCCI_FS_CHANNEL_RX) {
			LOGW("Main: unexpected channel %u on /dev/ccci_fs (expected %u)",
			     (unsigned)hdr.channel, (unsigned)CCCI_FS_CHANNEL_RX);
			continue;
		}

		if ((size_t)n >= sizeof(hdr) + sizeof(uint32_t))
			memcpy(&req_op_id, rxbuf + sizeof(hdr), sizeof(req_op_id));
		else
			req_op_id = 0;

		/* Try the write-shaped CMPT struct first (base = payload
		 * start, i.e. right after the header) -- opid_map's WRITE
		 * bit (0x20) or OPEN-without-read/getsize bits distinguish
		 * it from the read-shaped struct well enough for the two
		 * fully-decoded shapes this daemon answers. See the top
		 * comment for why the real selector remains open.
		 */
		/* No pre-parse CMPT sniffing: the op_id word must be read by the
		 * segment parser below. The old offset-sniffers mis-took op_id
		 * 0x1022 (bit5 set) for a CMPT_WRITE opid_map and answered -2,
		 * which asserted the modem at HS2. */
		{
			struct fs_req req;
			char path[260], real[512];
			char path2[260], real2[512];
			int32_t rc;
			int path_ok;

			if (fs_parse_req(rxbuf + sizeof(hdr), (size_t)n - sizeof(hdr), &req) == 0) {
				req_op_id = req.op_id;
				path_ok = 0;
				path[0] = real[0] = path2[0] = real2[0] = '\0';

				/* Every request, served or not. Without this the log only shows what
				 * this daemon already handles, which is exactly the wrong half when
				 * the question is what the modem still needs. */
				LOGI("REQ op=0x%x segs=%u len0=%u", (unsigned)req.op_id, req.nseg,
				     req.nseg ? req.seglen[0] : 0);

				/* Stage 1: ops whose first segment is a path get it decoded and
				 * resolved once, here, so every handler below works on `real`. */
				switch (req.op_id) {
				case FS_OP_OPEN:
				case FS_OP_OPEN_EX:
				case FS_OP_GET_ATTRIBUTES:
				case FS_OP_GET_DISK_INFO:
				case FS_OP_CREATE_DIR:
				case FS_OP_REMOVE_DIR:
				case FS_OP_DELETE:
				case FS_OP_XDELETE:
				case FS_OP_GET_FOLDER_SIZE:
				case FS_OP_COUNT:
				case FS_OP_FIND_FIRST:
				case FS_OP_CMPT_READ:
				case FS_OP_CMPT_WRITE:
				case FS_OP_GET_FILE_DETAIL:
				case FS_OP_RESTORE:
				case FS_OP_RENAME:
				case FS_OP_MOVE:
					if (req.nseg < 1 ||
					    fs_wcs_to_str(req.seg[0], req.seglen[0], path,
							   sizeof(path)) != 0) {
						LOGW("Main: op 0x%x with no usable path",
						     (unsigned)req.op_id);
						break;
					}
					if (fs_resolve(path, real, sizeof(real)) != 0) {
						LOGW("Main: op 0x%x path \"%s\" refused",
						     (unsigned)req.op_id, path);
						rc = FS_ERR_ENOENT_MAPPED;
						resp_len = build_result_resp(txbuf, sizeof(txbuf),
									      &hdr, req.op_id, rc);
						goto send_resp;
					}
					path_ok = 1;
					/* Rename and Move carry a second path in segment 1. */
					if (req.op_id == FS_OP_RENAME || req.op_id == FS_OP_MOVE) {
						if (req.nseg < 2 ||
						    fs_wcs_to_str(req.seg[1], req.seglen[1], path2,
								   sizeof(path2)) != 0 ||
						    fs_resolve(path2, real2, sizeof(real2)) != 0) {
							LOGW("Main: op 0x%x without a usable second path",
							     (unsigned)req.op_id);
							rc = FS_PARAM_ERROR;
							resp_len = build_result_resp(txbuf,
										      sizeof(txbuf),
										      &hdr, req.op_id,
										      rc);
							goto send_resp;
						}
					}
					break;
				default:
					path_ok = 1; /* not a path op; nothing to resolve */
					break;
				}
				if (!path_ok)
					goto not_served;

				/* Stage 2: the operations themselves. */
				switch (req.op_id) {

				case FS_OP_GET_ATTRIBUTES: {
					struct stat st;

					if (stat(real, &st) != 0) {
						rc = FS_ERR_ENOENT_MAPPED;
					} else {
						rc = (access(real, W_OK) == 0) ? 0 : FS_ATTR_READONLY;
						if (S_ISDIR(st.st_mode))
							rc |= FS_ATTR_DIRECTORY;
					}
					LOGI("Main: GetAttributes \"%s\" -> %s: 0x%x", path, real,
					     (unsigned)rc);
					resp_len = build_result_resp(txbuf, sizeof(txbuf), &hdr,
								      req.op_id, rc);
					goto send_resp;
				}

				case FS_OP_OPEN: {
					uint32_t flags = 0;
					int h;

					if (req.nseg >= 2 && req.seglen[1] >= 4)
						memcpy(&flags, req.seg[1], sizeof(flags));
					h = fs_handle_open(real, flags);
					/* WARN, not INFO, whenever the modem asks for anything but a
					 * plain read: on this device those paths sit under NVRAM, and
					 * the first live exercise of the write side must be visible at
					 * a glance rather than buried in the request stream. */
					if (flags & ~FS_FLAG_READ_ONLY & (FS_FLAG_CREATE |
					    FS_FLAG_CREATE_ALWAYS))
						LOGW("Main: Open(WRITE) \"%s\" -> %s flags=0x%x: %d",
						     path, real, flags, h);
					else
						LOGI("Main: Open \"%s\" -> %s flags=0x%x: %d", path,
						     real, flags, h);
					resp_len = build_result_resp(txbuf, sizeof(txbuf), &hdr,
								      req.op_id, h);
					goto send_resp;
				}

				case FS_OP_OPEN_EX: {
					/* Open whose reply carries a second 8-byte segment. The stock
					 * fills it by handing back the third request segment verbatim
					 * (dispatcher case 0x1011: the reply's segment pointer is set
					 * to the request's segment-2 data). Mirror that rather than
					 * invent a meaning for bytes we have not decoded. */
					uint32_t flags = 0;
					unsigned char echo[8];
					int h;
					int32_t res;
					struct fs_seg segs[2];

					memset(echo, 0, sizeof(echo));
					if (req.nseg >= 2 && req.seglen[1] >= 4)
						memcpy(&flags, req.seg[1], sizeof(flags));
					if (req.nseg >= 3 && req.seglen[2] >= sizeof(echo))
						memcpy(echo, req.seg[2], sizeof(echo));
					h = fs_handle_open(real, flags);
					res = h;
					segs[0].data = &res;  segs[0].len = sizeof(res);
					segs[1].data = echo;  segs[1].len = sizeof(echo);
					LOGI("Main: OpenEx \"%s\" -> %s flags=0x%x: %d", path, real,
					     flags, h);
					resp_len = build_resp(txbuf, sizeof(txbuf), &hdr, req.op_id,
							       segs, 2);
					goto send_resp;
				}

				case FS_OP_CLOSE: {
					int32_t h;

					if (req.nseg < 1 || req.seglen[0] < 4)
						goto not_served;
					memcpy(&h, req.seg[0], sizeof(h));
					rc = fs_handle_close(h);
					LOGI("Main: Close %d -> %d", h, rc);
					resp_len = build_result_resp(txbuf, sizeof(txbuf), &hdr,
								      req.op_id, rc);
					goto send_resp;
				}

				case FS_OP_CLOSE_ALL:
				case FS_OP_CLOSE_ALL2: {
					int32_t closed = fs_handle_close_all();

					LOGI("Main: CloseAll -> %d handle(s) closed", closed);
					resp_len = build_result_resp(txbuf, sizeof(txbuf), &hdr,
								      req.op_id, FS_NO_ERROR);
					goto send_resp;
				}

				case FS_OP_SEEK: {
					int32_t h = 0, off = 0, whence = 0;
					int64_t pos;

					if (req.nseg < 3 || req.seglen[0] < 4 || req.seglen[1] < 4 ||
					    req.seglen[2] < 4)
						goto not_served;
					memcpy(&h, req.seg[0], sizeof(h));
					memcpy(&off, req.seg[1], sizeof(off));
					memcpy(&whence, req.seg[2], sizeof(whence));
					pos = fs_handle_seek(h, off, whence);
					LOGI("Main: Seek handle=%d off=%d whence=%d -> %lld", h, off,
					     whence, (long long)pos);
					resp_len = build_result_resp(txbuf, sizeof(txbuf), &hdr,
								      req.op_id,
								      (pos < 0) ? FS_ERR_GENERIC_MAPPED
										: (int32_t)pos);
					goto send_resp;
				}

				case FS_OP_READ: {
					int32_t h, want;
					ssize_t got;

					if (req.nseg < 2 || req.seglen[0] < 4 || req.seglen[1] < 4)
						goto not_served;
					memcpy(&h, req.seg[0], sizeof(h));
					memcpy(&want, req.seg[1], sizeof(want));
					got = fs_handle_read(h, rdbuf, sizeof(rdbuf), (size_t)want);
					LOGI("Main: Read handle=%d want=%d -> %zd", h, want, got);
					if (got < 0) {
						resp_len = build_result_resp(txbuf, sizeof(txbuf),
									      &hdr, req.op_id,
									      FS_ERR_GENERIC_MAPPED);
					} else {
						const int32_t res = FS_NO_ERROR;
						const int32_t cnt = (int32_t)got;
						const struct fs_seg segs[3] = {
							{ &res,  sizeof(res)  },
							{ &cnt,  sizeof(cnt) },
							{ rdbuf, (size_t)got },
						};

						resp_len = build_resp(txbuf, sizeof(txbuf), &hdr,
								       req.op_id, segs, 3);
					}
					goto send_resp;
				}

				case FS_OP_WRITE: {
					/* Two segments back: result, then the count written
					 * (dispatcher case 0x1004). */
					int32_t h;
					ssize_t put;
					int32_t res, cnt;
					struct fs_seg segs[2];

					if (req.nseg < 2 || req.seglen[0] < 4)
						goto not_served;
					memcpy(&h, req.seg[0], sizeof(h));
					put = fs_handle_write(h, req.seg[1], req.seglen[1]);
					res = (put < 0) ? FS_ERR_GENERIC_MAPPED : FS_NO_ERROR;
					cnt = (put < 0) ? 0 : (int32_t)put;
					LOGW("Main: Write handle=%d len=%u -> %zd", h, req.seglen[1],
					     put);
					segs[0].data = &res; segs[0].len = sizeof(res);
					segs[1].data = &cnt; segs[1].len = sizeof(cnt);
					resp_len = build_resp(txbuf, sizeof(txbuf), &hdr, req.op_id,
							       segs, 2);
					goto send_resp;
				}

				case FS_OP_CREATE_DIR:
					rc = FS_NO_ERROR;
#if MINDONE_FS_ALLOW_WRITES
					if (mkdir(real, 0770) != 0 && errno != EEXIST)
						rc = FS_ERR_GENERIC_MAPPED;
#else
					rc = FS_ERR_GENERIC_MAPPED;
#endif
					LOGI("Main: CreateDir \"%s\" -> %s: %d", path, real, rc);
					resp_len = build_result_resp(txbuf, sizeof(txbuf), &hdr,
								      req.op_id, rc);
					goto send_resp;

				case FS_OP_REMOVE_DIR:
					rc = FS_NO_ERROR;
#if MINDONE_FS_ALLOW_WRITES
					if (rmdir(real) != 0)
						rc = (errno == ENOENT) ? FS_ERR_ENOENT_MAPPED
								       : FS_ERR_GENERIC_MAPPED;
#else
					rc = FS_ERR_GENERIC_MAPPED;
#endif
					LOGW("Main: RemoveDir \"%s\" -> %s: %d", path, real, rc);
					resp_len = build_result_resp(txbuf, sizeof(txbuf), &hdr,
								      req.op_id, rc);
					goto send_resp;

				case FS_OP_DELETE:
					rc = FS_NO_ERROR;
#if MINDONE_FS_ALLOW_WRITES
					if (unlink(real) != 0)
						rc = (errno == ENOENT) ? FS_ERR_ENOENT_MAPPED
								       : FS_ERR_GENERIC_MAPPED;
#else
					rc = FS_ERR_GENERIC_MAPPED;
#endif
					LOGW("Main: Delete \"%s\" -> %s: %d", path, real, rc);
					resp_len = build_result_resp(txbuf, sizeof(txbuf), &hdr,
								      req.op_id, rc);
					goto send_resp;

				case FS_OP_XDELETE:
#if MINDONE_FS_ALLOW_WRITES
					rc = fs_rm_recursive(real, 0);
#else
					rc = FS_ERR_GENERIC_MAPPED;
#endif
					LOGW("Main: XDelete(recursive) \"%s\" -> %s: %d", path, real, rc);
					resp_len = build_result_resp(txbuf, sizeof(txbuf), &hdr,
								      req.op_id, rc);
					goto send_resp;

				case FS_OP_RENAME:
				case FS_OP_MOVE:
					rc = FS_NO_ERROR;
#if MINDONE_FS_ALLOW_WRITES
					if (rename(real, real2) != 0)
						rc = (errno == ENOENT) ? FS_ERR_ENOENT_MAPPED
								       : FS_ERR_GENERIC_MAPPED;
#else
					rc = FS_ERR_GENERIC_MAPPED;
#endif
					LOGW("Main: %s \"%s\" -> \"%s\": %d",
					     (req.op_id == FS_OP_MOVE) ? "Move" : "Rename",
					     path, path2, rc);
					resp_len = build_result_resp(txbuf, sizeof(txbuf), &hdr,
								      req.op_id, rc);
					goto send_resp;

				case FS_OP_RESTORE:
					/* The stock's FS_CCCI_Restore undoes a delete from its own
					 * recycle area. We keep no recycle area, so the honest answer
					 * is "no such file" rather than a success the modem would
					 * then build on. */
					LOGI("Main: Restore \"%s\" -- no recycle area, answering ENOENT",
					     path);
					resp_len = build_result_resp(txbuf, sizeof(txbuf), &hdr,
								      req.op_id, FS_ERR_ENOENT_MAPPED);
					goto send_resp;

				case FS_OP_GET_FILE_SIZE: {
					/* Handle-based, like stock FS_CCCI_GetFileSize(handle, &size). */
					struct stat st;
					int32_t h = 0, res, sz = 0;
					struct fs_seg segs[2];

					if (req.nseg < 1 || req.seglen[0] < 4)
						goto not_served;
					memcpy(&h, req.seg[0], sizeof(h));
					if (h <= 0 || h >= FS_HANDLE_MAX || g_fs_handles[h] < 0)
						res = FS_PARAM_ERROR;
					else if (fstat(g_fs_handles[h], &st) != 0)
						res = errno_to_fs_result(errno);
					else {
						res = FS_NO_ERROR;
						sz = (int32_t)st.st_size;
					}
					LOGI("Main: GetFileSize handle=%d -> %d (rc %d)", h, sz, res);
					segs[0].data = &res; segs[0].len = sizeof(res);
					segs[1].data = &sz;  segs[1].len = sizeof(sz);
					resp_len = build_resp(txbuf, sizeof(txbuf), &hdr, req.op_id,
							       segs, 2);
					goto send_resp;
				}

				case FS_OP_GET_FOLDER_SIZE: {
					int64_t total = fs_folder_size(real, 0);

					LOGI("Main: GetFolderSize \"%s\" -> %lld", path,
					     (long long)total);
					resp_len = build_result_resp(txbuf, sizeof(txbuf), &hdr,
								      req.op_id,
								      (total < 0) ? FS_ERR_ENOENT_MAPPED
										  : (int32_t)total);
					goto send_resp;
				}

				case FS_OP_COUNT: {
					int32_t cnt = fs_dir_count(real);

					LOGI("Main: Count \"%s\" -> %d", path, cnt);
					resp_len = build_result_resp(txbuf, sizeof(txbuf), &hdr,
								      req.op_id,
								      (cnt < 0) ? FS_ERR_ENOENT_MAPPED
										: cnt);
					goto send_resp;
				}

				case FS_OP_FIND_FIRST: {
					/* The path carries the search pattern in its last component,
					 * e.g. "Z:\NVRAM\*.nvd". Split it: directory for opendir,
					 * pattern for fnmatch. */
					char pattern[64];
					char *slash;
					int h;

					snprintf(pattern, sizeof(pattern), "*");
					slash = strrchr(real, '/');
					if (slash != NULL && strpbrk(slash + 1, "*?") != NULL) {
						snprintf(pattern, sizeof(pattern), "%s", slash + 1);
						*slash = '\0';
					}
					h = fs_find_open(real, pattern);
					LOGI("Main: FindFirst \"%s\" dir=%s pattern=%s -> %d", path,
					     real, pattern, h);
					resp_len = build_result_resp(txbuf, sizeof(txbuf), &hdr,
								      req.op_id, h);
					goto send_resp;
				}

				case FS_OP_FIND_NEXT: {
					/* Three segments (dispatcher case 0x1013): result, name
					 * length, name bytes. */
					int32_t h = 0;
					char name[256];
					struct stat st;
					int32_t res, len32;
					struct fs_seg segs[3];

					if (req.nseg < 1 || req.seglen[0] < 4)
						goto not_served;
					memcpy(&h, req.seg[0], sizeof(h));
					if (fs_find_next(h, name, sizeof(name), &st) != 0) {
						LOGI("Main: FindNext %d -> end of directory", h);
						resp_len = build_result_resp(txbuf, sizeof(txbuf),
									      &hdr, req.op_id,
									      FS_ERR_ENOENT_MAPPED);
						goto send_resp;
					}
					res = FS_NO_ERROR;
					len32 = (int32_t)strlen(name);
					LOGI("Main: FindNext %d -> \"%s\"", h, name);
					segs[0].data = &res;   segs[0].len = sizeof(res);
					segs[1].data = &len32; segs[1].len = sizeof(len32);
					segs[2].data = name;   segs[2].len = (size_t)len32;
					resp_len = build_resp(txbuf, sizeof(txbuf), &hdr, req.op_id,
							       segs, 3);
					goto send_resp;
				}

				case FS_OP_FIND_CLOSE: {
					int32_t h = 0;

					if (req.nseg < 1 || req.seglen[0] < 4)
						goto not_served;
					memcpy(&h, req.seg[0], sizeof(h));
					rc = fs_find_close(h);
					LOGI("Main: FindClose %d -> %d", h, rc);
					resp_len = build_result_resp(txbuf, sizeof(txbuf), &hdr,
								      req.op_id, rc);
					goto send_resp;
				}

				case FS_OP_GET_DRIVE: {
					/* NOT a path op: the request is three integers
					 * (type, serial, altMask). The stock validates them and, for
					 * type == 4 (FS_DRIVE_I_SYSTEM), returns 90 -- the ASCII letter
					 * 'Z'. Any other type is a parameter error (-2). Mirrored
					 * exactly, because the modem uses the answer as the drive
					 * letter it then builds paths from. */
					uint32_t type = 0, serial = 0, alt = 0;
					int32_t res;

					if (req.nseg >= 1 && req.seglen[0] >= 4)
						memcpy(&type, req.seg[0], sizeof(type));
					if (req.nseg >= 2 && req.seglen[1] >= 4)
						memcpy(&serial, req.seg[1], sizeof(serial));
					if (req.nseg >= 3 && req.seglen[2] >= 4)
						memcpy(&alt, req.seg[2], sizeof(alt));
					res = (type == 4) ? 'Z' : FS_PARAM_ERROR;
					LOGI("Main: GetDrive type=0x%x serial=0x%x alt=0x%x -> %d",
					     type, serial, alt, res);
					resp_len = build_result_resp(txbuf, sizeof(txbuf), &hdr,
								      req.op_id, res);
					goto send_resp;
				}

				case FS_OP_GET_CLUSTER_SIZE: {
					/* NOT a path op either: the request carries one integer, the
					 * drive LETTER. The stock accepts 'Q'..'Z' (81..90), indexes
					 * its mount table with it and returns statfs.f_bsize; anything
					 * outside that range is -4. */
					uint32_t drive = 0;
					char dpath[4];
					struct statfs sfs;
					int32_t res;

					if (req.nseg >= 1 && req.seglen[0] >= 4)
						memcpy(&drive, req.seg[0], sizeof(drive));
					if (drive < 'Q' || drive > 'Z') {
						res = FS_ERR_GENERIC_MAPPED;
					} else {
						snprintf(dpath, sizeof(dpath), "%c:\\", (char)drive);
						res = (statfs(fs_drive_dir(dpath), &sfs) == 0)
							      ? (int32_t)sfs.f_bsize
							      : FS_ERR_GENERIC_MAPPED;
					}
					LOGI("Main: GetClusterSize drive='%c' -> %d",
					     (drive >= 32 && drive < 127) ? (char)drive : '?', res);
					resp_len = build_result_resp(txbuf, sizeof(txbuf), &hdr,
								      req.op_id, res);
					goto send_resp;
				}

				case FS_OP_GET_FILE_DETAIL: {
					/* 24 bytes in the second segment (stock: v46[4] = 24). Laid
					 * out as size, attributes and the three timestamps the stat
					 * we already do provides; the modem's own field order beyond
					 * the size is not decoded, so anything past it is zeroed
					 * rather than filled with plausible-looking numbers. */
					unsigned char detail[FS_FILE_DETAIL_BYTES];
					struct stat st;
					int32_t res;
					uint32_t v;

					memset(detail, 0, sizeof(detail));
					if (stat(real, &st) != 0) {
						res = FS_ERR_ENOENT_MAPPED;
					} else {
						res = FS_NO_ERROR;
						v = (uint32_t)st.st_size;
						memcpy(detail, &v, sizeof(v));
						v = S_ISDIR(st.st_mode) ? FS_ATTR_DIRECTORY : 0;
						if (access(real, W_OK) != 0)
							v |= FS_ATTR_READONLY;
						memcpy(detail + 4, &v, sizeof(v));
						v = (uint32_t)st.st_mtime;
						memcpy(detail + 8, &v, sizeof(v));
					}
					LOGI("Main: GetFileDetail \"%s\" -> rc %d", path, res);
					resp_len = build_data_resp(txbuf, sizeof(txbuf), &hdr,
								    req.op_id, res, detail,
								    sizeof(detail));
					goto send_resp;
				}

				case FS_OP_GET_DISK_INFO: {
					uint32_t info[FS_DISK_INFO_DWORDS];
					struct statfs sfs;
					const char *dir = fs_drive_dir(path);

					memset(info, 0, sizeof(info));
					if (statfs(dir, &sfs) == 0) {
						info[12] = 512;
						info[13] = (uint32_t)(sfs.f_bsize / 512);
						info[14] = (uint32_t)sfs.f_blocks;
						info[16] = 512;
						LOGI("Main: GetDiskInfo \"%s\" -> %s: clusters=%u",
						     path, dir, info[14]);
						resp_len = build_data_resp(txbuf, sizeof(txbuf), &hdr,
									    req.op_id, FS_NO_ERROR,
									    info, sizeof(info));
					} else {
						LOGE("Main: GetDiskInfo statfs(%s): %s", dir,
						     strerror(errno));
						resp_len = build_data_resp(txbuf, sizeof(txbuf), &hdr,
									    req.op_id,
									    FS_ERR_GENERIC_MAPPED,
									    info, sizeof(info));
					}
					goto send_resp;
				}

				case FS_OP_OTP_QUERY_LENGTH:
				case FS_OP_OTP_READ:
					/* Reading one-time-programmable fuses is harmless, but this
					 * board exposes no OTP node to userspace that we have found,
					 * so report "not present" rather than fabricate a length the
					 * modem would then read against. */
					LOGI("Main: OTP op 0x%x -- no OTP backing on this board",
					     (unsigned)req.op_id);
					resp_len = build_result_resp(txbuf, sizeof(txbuf), &hdr,
								      req.op_id, FS_ERR_ENOENT_MAPPED);
					goto send_resp;

				case FS_OP_OTP_WRITE:
				case FS_OP_OTP_LOCK:
#if MINDONE_FS_ALLOW_OTP_WRITE
					/* Intentionally still unimplemented even when enabled: the
					 * write path must be brought up against a known-sacrificial
					 * part, never against the daily driver. */
					LOGE("Main: OTP write/lock requested and the build allows it, "
					     "but no backing implementation exists -- refusing");
#else
					LOGW("Main: OTP write/lock (op 0x%x) refused: fuses cannot be "
					     "restored from any backup (MINDONE_FS_ALLOW_OTP_WRITE=0)",
					     (unsigned)req.op_id);
#endif
					resp_len = build_result_resp(txbuf, sizeof(txbuf), &hdr,
								      req.op_id, FS_ERR_GENERIC_MAPPED);
					goto send_resp;

				case FS_OP_CMPT_READ: {
					struct cmpt_read_out o;
					struct ccci_fs_cmpt_read_req creq;
					struct fs_seg segs[4];

					if (req.nseg < 2 || req.seglen[1] < sizeof(creq))
						goto not_served;
					memcpy(&creq, req.seg[1], sizeof(creq));
					rc = handle_cmpt_read(&creq, real, rdbuf, sizeof(rdbuf), &o);
					LOGI("Main: CMPT_Read \"%s\" -> %s opid_map=0x%x flag=0x%x: "
					     "done=0x%x err=%d size=%u len=%u ret=%d",
					     path, real, creq.opid_map, creq.flag, o.done, o.err,
					     o.size, o.read_len, rc);
					segs[0] = (struct fs_seg){ &o.done, 8 };
					segs[1] = (struct fs_seg){ &o.size, 4 };
					segs[2] = (struct fs_seg){ &o.read_len, 4 };
					segs[3] = (struct fs_seg){ rdbuf, o.read_len };
					resp_len = build_resp(txbuf, sizeof(txbuf), &hdr, req.op_id, segs, 4);
					goto send_resp;
				}

				case FS_OP_CMPT_WRITE: {
					struct cmpt_write_out o;
					const struct ccci_fs_cmpt_write_req *wr;
					struct fs_seg segs[3];

					if (req.nseg < 2 ||
					    req.seglen[1] < sizeof(struct ccci_fs_cmpt_write_req))
						goto not_served;
					wr = (const struct ccci_fs_cmpt_write_req *)req.seg[1];
					o.err = handle_cmpt_write(wr, req.seglen[1], real, &o);
					LOGW("Main: CMPT_Write \"%s\" -> %s opid_map=0x%x flag=0x%x: "
					     "done=0x%x err=%d handle=%d written=%u",
					     path, real, wr->opid_map, wr->flag, o.done, o.err,
					     o.handle, o.written);
					segs[0] = (struct fs_seg){ &o.done, 8 };
					segs[1] = (struct fs_seg){ &o.handle, 4 };
					segs[2] = (struct fs_seg){ &o.written, 4 };
					resp_len = build_resp(txbuf, sizeof(txbuf), &hdr, req.op_id, segs, 3);
					goto send_resp;
				}

				case FS_OP_LF:
				case FS_OP_CDF:
				case FS_OP_SDF:
				case FS_OP_UK: {
					/* Four constant-answer operations. Not a stub on our side --
					 * the STOCK handler is the constant: each of these branches in
					 * fsd_main does no filesystem work at all, logs one line and
					 * replies with a single segment holding a fixed value
					 * (dispatcher cases 0x1015/0x1016/0x1019/0x101c). The names are
					 * the stock's own log prefixes; their meaning is not documented
					 * anywhere we can see, and reproducing the constant is exactly
					 * as correct as knowing it would be.
					 */
					int32_t val = (req.op_id == FS_OP_UK) ? 1 : 0;
					const char *tag = (req.op_id == FS_OP_LF)  ? "LF"  :
							  (req.op_id == FS_OP_UK)  ? "UK"  :
							  (req.op_id == FS_OP_CDF) ? "CDF" : "SDF";

					LOGI("Main: %s: %d (constant, as the stock answers)", tag, val);
					resp_len = build_result_resp(txbuf, sizeof(txbuf), &hdr,
								      req.op_id, val);
					goto send_resp;
				}

				case FS_OP_BIN_REGION: {
					/* The NVRAM bin region -- the surface this project has always
					 * refused to guess at, because a wrong write there corrupts
					 * IMEI and calibration silently.
					 *
					 * It turns out nothing needs to be guessed: the stock handler
					 * (dispatcher case 0x1023) calls FS_BinRegion_Access(), THROWS
					 * AWAY its return value, and answers a single segment holding a
					 * hardcoded -2. So "always refuse with a parameter error" IS the
					 * stock behaviour, and answering it is strictly better than our
					 * previous ENOENT: it is the exact code the modem's own error
					 * paths were written against.
					 */
					uint32_t which = 0;

					if (req.nseg >= 1 && req.seglen[0] >= 4)
						memcpy(&which, req.seg[0], sizeof(which));
					LOGI("Main: BinRegion access (arg=0x%x) -> -2, as the stock answers",
					     which);
					resp_len = build_result_resp(txbuf, sizeof(txbuf), &hdr,
								      req.op_id, FS_PARAM_ERROR);
					goto send_resp;
				}

				default:
					break;
				}

not_served:
				LOGW("Main: op 0x%x (%u segments) not served -- answering ENOENT",
				     (unsigned)req.op_id, req.nseg);
			}
		}


		LOGW("Main: request did not match a decoded CMPT shape -- answering ENOENT");
		result = FS_ERR_ENOENT_MAPPED;
		resp_len = build_result_resp(txbuf, sizeof(txbuf), &hdr, req_op_id, result);
send_resp:
		if (resp_len == 0) {
			LOGE("Main: no response built for op 0x%x", (unsigned)req_op_id);
			continue;
		}
		log_hexdump("tx", txbuf, resp_len);
		if (fs_write_stream(fd, txbuf, resp_len) < 0)
			LOGE("write(%s) response of %zu bytes failed: %s", CCCI_DEV_FS, resp_len,
			     strerror(errno));
	}

	close(fd);
	return 1;
}
