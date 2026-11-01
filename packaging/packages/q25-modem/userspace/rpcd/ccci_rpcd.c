/*
 * SPDX-License-Identifier: Apache-2.0
 * SPDX-FileCopyrightText: 2026 The LineageOS Project
 * SPDX-FileCopyrightText: 2026 Marathon (Q25 musl port)
 */
/*
 * Open ccci_rpcd for the Q25 (MT6789 / MD6295), musl build.
 *
 * Derived from MindOne's mindone_rpcd. Framing and the AMMS DRDI protocol
 * follow the Q25 stock /vendor/bin/ccci_rpcd (aarch64, v2.00), read from the
 * owner's own vendor image:
 *  - every request/response argument is {u32 len; u8 data[len]; pad to 4};
 *  - replies carry op_id | 0xFFFF0000 and two arguments {4, ret}, {N, data};
 *  - IPC_RPC_AMMS_DRDI_CONTROL (0x4014): 0xbc-byte request, 8-byte reply.
 *    cmd 1 (init): ver must be 3, <= 15 sets of {start,size} within md1drdi;
 *    cmd 2 (copy): sets of {src,dst,len}, len <= 64 KiB, copied straight from
 *    the md1drdi record of the md1img partition into the 64 KiB DRDI window
 *    that /dev/ccci_rpc mmap()s (SMEM_USER_MD_DRDI).
 * Deviation from stock: dst + len is also bounded by the 64 KiB window.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#include <android/log.h>
#include <cutils/properties.h>

#include "ccci_ioctl.h"
#include "ccci_rpc.h"
#include "ccci_rpc_route.h"

#define LOG_TAG "q25_rpcd"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

#define MAX_ARGS		RPC_MAX_ARG_NUM
#define DRDI_REQ_LEN		0xbc
#define DRDI_REPLY_LEN		8
#define DRDI_WINDOW		0x10000
#define DRDI_MAX_SETS		15
#define DRDI_VERSION		3
#define MKIMG_MAGIC		0x58881688u
#define MKIMG_HDR		512

struct rpc_arg {
	uint32_t len;
	const uint8_t *data;
};

static int g_rpc_fd = -1;
static uint8_t *g_drdi_map;		/* 64 KiB DRDI smem window */
static off_t g_drdi_off;		/* md1drdi payload offset in md1img */
static uint32_t g_drdi_size;
static uint32_t g_drdi_sets;
static int g_drdi_copied;		/* 1 done, 0 not yet, -1 failed */
static char g_md1img[PROPERTY_VALUE_MAX];

static int unpack_args(const struct rpc_buffer *req, size_t buflen, struct rpc_arg *a)
{
	size_t off = 0;
	uint32_t i;

	if (req->para_num > MAX_ARGS)
		return -1;
	for (i = 0; i < req->para_num; i++) {
		uint32_t len;

		if (buflen - off < 4)
			return -1;
		memcpy(&len, req->buffer + off, 4);
		off += 4;
		if (len > buflen - off)
			return -1;
		a[i].len = len;
		a[i].data = req->buffer + off;
		off += (len + 3) & ~3u;
		if (off > buflen)
			off = buflen;
	}
	return (int)req->para_num;
}

static void reply2(uint32_t op_id, int32_t ret, const void *data, uint32_t len)
{
	uint8_t buf[RPC_MAX_BUF_SIZE];
	struct rpc_buffer *r = (struct rpc_buffer *)buf;
	size_t off = 0;
	uint32_t four = 4;

	if (sizeof(*r) + 8 + 4 + ((len + 3) & ~3u) > sizeof(buf)) {
		LOGE("reply for 0x%x too large (%u)", op_id, len);
		return;
	}
	memset(buf, 0, sizeof(buf));
	r->op_id = op_id | RPC_API_RESP_ID;
	r->para_num = 2;
	memcpy(r->buffer + off, &four, 4);
	memcpy(r->buffer + off + 4, &ret, 4);
	off += 8;
	memcpy(r->buffer + off, &len, 4);
	if (len)
		memcpy(r->buffer + off + 4, data, len);
	off += 4 + ((len + 3) & ~3u);
	if (write(g_rpc_fd, buf, sizeof(*r) + off) < 0)
		LOGE("write(%s) reply 0x%x failed: %s", CCCI_DEV_RPC, op_id, strerror(errno));
}

static void handle_query_property(uint32_t op, const struct rpc_arg *a, int n)
{
	char key[PROPERTY_VALUE_MAX], value[PROPERTY_VALUE_MAX];
	size_t kl;
	int ret;

	if (n < 1) {
		reply2(op, FS_PARAM_ERROR, NULL, 0);
		return;
	}
	kl = a[0].len < sizeof(key) - 1 ? a[0].len : sizeof(key) - 1;
	memcpy(key, a[0].data, kl);
	key[kl] = 0;
	ret = property_get(key, value, "");
	LOGI("Main: IPC_RPC_QUERY_AP_SYS_PROPERTY, key<%s>, value<%s>, %d", key, value, ret);
	reply2(op, ret, value, (uint32_t)strlen(value) + 1);
}

static void handle_sar_query(uint32_t op)
{
	char v[PROPERTY_VALUE_MAX];
	int32_t value;

	/* stock asks libsysenv's mtk_sar_table_id_get(); no sysenv here: default table */
	property_get("q25.modem.sar_table_idx", v, "0");
	value = atoi(v);
	LOGI("Main: IPC_RPC_SAR_TABLE_IDX_QUERY_OP, value: %d, ret: %d", value, 0);
	reply2(op, 0, &value, sizeof(value));
}

static void handle_save_md_capid(uint32_t op, const struct rpc_arg *a, int n)
{
	uint32_t v[2] = { 0, 0 };
	int32_t out = 0;

	if (n >= 1 && a[0].len >= sizeof(v))
		memcpy(v, a[0].data, sizeof(v));
	LOGI("ccci_rpc_mdcap_aac_ctl: md_capid 0x%x md_aac 0x%x (not persisted)", v[0], v[1]);
	reply2(op, 0, &out, sizeof(out));
}

static int find_md1drdi(void)
{
	uint8_t h[MKIMG_HDR];
	off_t off = 0;
	int fd, i, ret = -1;

	property_get("q25.modem.md1img", g_md1img, "/dev/disk/by-partlabel/md1img_a");
	fd = open(g_md1img, O_RDONLY | O_CLOEXEC);
	if (fd < 0) {
		LOGE("open %s: %s", g_md1img, strerror(errno));
		return -1;
	}
	for (i = 0; i < 64; i++) {
		uint32_t magic, dsize, hsz, align, end;
		char name[33];

		if (pread(fd, h, sizeof(h), off) != (ssize_t)sizeof(h))
			break;
		memcpy(&magic, h, 4);
		memcpy(&dsize, h + 4, 4);
		memcpy(&hsz, h + 52, 4);
		memcpy(&end, h + 64, 4);
		memcpy(&align, h + 68, 4);
		if (magic != MKIMG_MAGIC || hsz != MKIMG_HDR || !align || (align & (align - 1)))
			break;
		memcpy(name, h + 8, 32);
		name[32] = 0;
		if (!strcmp(name, "md1drdi")) {
			g_drdi_off = off + hsz;
			g_drdi_size = dsize;
			ret = 0;
			break;
		}
		if (end == 1)
			break;
		off = (off + hsz + dsize + align - 1) & ~(off_t)(align - 1);
	}
	close(fd);
	if (ret)
		LOGE("not find %s in partition", "md1drdi");
	else if ((g_drdi_size - 1) >> 29) {
		LOGE("MD image size abnormal %d", g_drdi_size);
		ret = -1;
	} else {
		LOGI("find img %s (size 0x%x) at 0x%x in partition", "md1drdi", g_drdi_size,
		     (unsigned int)g_drdi_off);
	}
	return ret;
}

static void prepare_drdi(void)
{
	void *m;

	if (find_md1drdi())
		return;
	m = mmap(NULL, DRDI_WINDOW, PROT_READ | PROT_WRITE, MAP_SHARED, g_rpc_fd, 0);
	if (m == MAP_FAILED) {
		LOGE("ccci_prepare_drdi_info:mmap failed, errno=%d", errno);
		return;
	}
	g_drdi_map = m;
	LOGI("ccci_prepare_drdi_info:drdi window mapped");
}

static int32_t drdi_init(const uint8_t *q, uint8_t *r)
{
	uint32_t i, n;

	r[1] = q[1];
	if (!g_drdi_map) {
		LOGE("amms_cmd_init_handler: prepare drdi_info fail");
		goto fail;
	}
	if (q[4] != DRDI_VERSION) {
		LOGE("amms_cmd_init_handler:version(%d) error, goto fail", q[4]);
		goto fail;
	}
	r[4] = DRDI_VERSION;
	n = q[5];
	if (n > DRDI_MAX_SETS) {
		LOGE("amms_cmd_init_handler:set_total_num error");
		goto fail;
	}
	g_drdi_sets = n;
	for (i = 0; i < n; i++) {
		uint32_t start, size;

		memcpy(&start, q + 8 + 8 * i, 4);
		memcpy(&size, q + 12 + 8 * i, 4);
		if ((uint64_t)start + size > g_drdi_size) {
			LOGE("amms_cmd_init_handler: cmd invalid: start_addr=0x%x, size=0x%x",
			     start, size);
			r[6] = 0xff;
			r[0] = 0xfe;
			return -1;
		}
	}
	r[6] = 0;
	r[0] = 0;
	r[5] = g_drdi_copied == 1 ? 0xff : 0;
	LOGI("stats=%d, seqid=%d, coypstat=%d, ver=%d,drdiinfostat=%d", 0, r[1], r[5], 3, 0);
	return 0;
fail:
	r[0] = 0xff;
	r[4] = 3;
	r[5] = 0;
	r[6] = 0xff;
	LOGE("amms_cmd_init_handler:init cmd fail");
	return -1;
}

static int32_t drdi_copy(const uint8_t *q, uint8_t *r)
{
	uint32_t i;
	int fd;

	r[1] = q[1];
	for (i = 0; i < g_drdi_sets; i++) {
		uint32_t src, dst, len;

		memcpy(&src, q + 8 + 12 * i, 4);
		memcpy(&dst, q + 12 + 12 * i, 4);
		memcpy(&len, q + 16 + 12 * i, 4);
		if (!len)
			continue;
		if (len > DRDI_WINDOW || (uint64_t)src + len > g_drdi_size ||
		    (uint64_t)dst + len > DRDI_WINDOW) {
			LOGE("set(%u) error,src=0x%x,dst=0x%x,len=0x%x", i, src, dst, len);
			goto fail;
		}
	}
	if (g_drdi_copied == 1) {
		LOGI("amms_cmd_drdi_copy_handler:already copy success, no need copy");
		r[0] = 0;
		return 0;
	}
	if (!g_drdi_map)
		goto fail;
	fd = open(g_md1img, O_RDONLY | O_CLOEXEC);
	if (fd < 0) {
		LOGE("amms_cmd_drdi_copy_handler:open drdi img(%s) fail,cmd exit", g_md1img);
		goto fail;
	}
	r[4] = q[4] == 1 ? 0 : 0xff;
	for (i = 0; i < g_drdi_sets; i++) {
		uint32_t src, dst, len;
		ssize_t got;

		memcpy(&src, q + 8 + 12 * i, 4);
		memcpy(&dst, q + 12 + 12 * i, 4);
		memcpy(&len, q + 16 + 12 * i, 4);
		if (!len)
			continue;
		got = pread(fd, g_drdi_map + dst, len, g_drdi_off + src);
		if (got < 0) {
			LOGE("read set(%u)fail,err=%d,src=0x%x,dst=0x%x,len=0x%x", i, errno, src,
			     dst, len);
			close(fd);
			goto fail;
		}
		g_drdi_copied = q[4] == 1;
		LOGI("copy set(%u) from 0x%x to 0x%x,len=0x%x success", i, src, dst, len);
	}
	msync(g_drdi_map, DRDI_WINDOW, MS_SYNC);
	close(fd);
	r[0] = g_drdi_copied == -1 ? 0xff : 0;
	return 0;
fail:
	g_drdi_copied = -1;
	LOGE("amms_cmd_drdi_copy_handler:copy fail");
	r[0] = 0xff;
	return -1;
}

static void handle_amms_drdi(uint32_t op, const struct rpc_arg *a, int n)
{
	uint8_t reply[DRDI_REPLY_LEN] = { 0 };
	int32_t ret;

	if (n < 1 || a[0].len != DRDI_REQ_LEN) {
		LOGE("Main:can't recognize rpc pkt size:%d!", n < 1 ? -1 : (int)a[0].len);
		reply2(op, -1, reply, sizeof(reply));
		return;
	}
	switch (a[0].data[0]) {
	case 1:
		ret = drdi_init(a[0].data, reply);
		break;
	case 2:
		ret = drdi_copy(a[0].data, reply);
		break;
	default:
		LOGW("ccci_rpc_amms_drdi_ctl: unknown cmd:%u", a[0].data[0]);
		reply[0] = 0xff;
		reply[1] = a[0].data[1];
		ret = -1;
	}
	LOGI("ccci_rpc_amms_drdi_ctl:req:%u done, ret=%d", a[0].data[0], ret);
	reply2(op, ret, reply, sizeof(reply));
}

int main(int argc, char **argv)
{
	static uint8_t rxbuf[RPC_MAX_BUF_SIZE];
	struct rpc_arg args[MAX_ARGS];

	(void)argc;
	(void)argv;
	LOGI("ccci_rpcd Ver:q25-musl-1, CCCI Ver:%d", 3);
	g_rpc_fd = open(CCCI_DEV_RPC, O_RDWR | O_CLOEXEC);
	if (g_rpc_fd < 0) {
		LOGE("Main: open ccci_rpc fail: %s", strerror(errno));
		return 1;
	}
	prepare_drdi();

	for (;;) {
		ssize_t n = read(g_rpc_fd, rxbuf, sizeof(rxbuf));
		const struct rpc_buffer *req = (const struct rpc_buffer *)rxbuf;
		int na;

		if (n < 0) {
			if (errno == EINTR)
				continue;
			LOGE("Failed to read from RPC device !! errno = %d", errno);
			return 1;
		}
		if ((size_t)n < sizeof(*req)) {
			LOGW("Main:can't recognize rpc pkt size:%zd!", n);
			continue;
		}
		na = unpack_args(req, (size_t)n - sizeof(*req), args);
		if (na < 0 || !ccci_rpc_is_userspace_op(req->op_id)) {
			LOGW("Main: Unknow RPC Operation ID (0x%x)", req->op_id);
			reply2(req->op_id, FS_NO_OP, NULL, 0);
			continue;
		}
		switch (req->op_id) {
		case IPC_RPC_QUERY_AP_SYS_PROPERTY:
			handle_query_property(req->op_id, args, na);
			break;
		case IPC_RPC_SAR_TABLE_IDX_QUERY_OP:
			handle_sar_query(req->op_id);
			break;
		case IPC_RPC_AMMS_DRDI_CONTROL:
			handle_amms_drdi(req->op_id, args, na);
			break;
		case IPC_RPC_SAVE_MD_CAPID:
			handle_save_md_capid(req->op_id, args, na);
			break;
		}
	}
}
