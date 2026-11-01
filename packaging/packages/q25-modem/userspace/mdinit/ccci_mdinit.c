/*
 * SPDX-FileCopyrightText: 2026 The LineageOS Project
 * SPDX-License-Identifier: Apache-2.0
 */
/*
 * mindone_mdinit -- open replacement for the stock /vendor/bin/ccci_mdinit
 * blob (191 KB, ELF64, stripped) that boots and supervises the on-die MT6789
 * cellular modem (MD1) over our own CCCI kernel driver
 * (the kernel tree's mindone/modules/ccci_md_all/).
 *
 * Shipped under the SAME name and SAME path (/vendor/bin/ccci_mdinit) as the
 * blob it replaces -- see common/ccci_ioctl.h's "DESIGN CHOICE" comment on
 * CCCI_IOC_DO_START_MD for why (kernel comm-gate + SELinux file_contexts +
 * existing init.rc service stanza all key off this exact name/path).
 *
 * Every ioctl/struct/property/path used here is cited against either our
 * own kernel source (the kernel repository's mindone/modules/ccci_md_all/) or a read-only string/disassembly
 * pull from the stock binary in the build environment -- see the common headers for the
 * per-symbol citations. Nothing here is a "best guess with no citation."
 *
 * BUILT-IN SCOPE LIMITS (documented, not silent):
 *   - SIM hot-plug / SIM-switch ioctls (CCCI_IOC_SIM_SWITCH & friends) are
 *     NOT implemented: fsm/ccci_fsm_ioctl.c:29-39 shows switch_sim_mode()/
 *     get_sim_switch_type() are __weak stubs that just log "not supported"
 *     and return 0 -- i.e. this is dead code on our platform (no
 *     board-specific override is linked into our kernel), and our board is
 *     physically single-SIM. Implementing a real client for a kernel-side
 *     no-op would be simulating functionality that provably does not exist.
 *   - The NVRAM bin-region restore step is implemented but DISABLED BY
 *     DEFAULT -- see common/nvram_shim.h's block comment on
 *     NVM_RestoreFromBinRegion_OneFile for the full risk writeup.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/timerfd.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#include <android/log.h>
#include <cutils/properties.h>

#include "ccci_ioctl.h"
#include "nvram_shim.h"

#ifndef MINDONE_ENABLE_BINREGION_RESTORE
#define MINDONE_ENABLE_BINREGION_RESTORE 0
#endif

#define LOG_TAG "mindone_mdinit"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

/* ------------------------------------------------------------------ */
/* Small helpers                                                       */
/* ------------------------------------------------------------------ */

static int g_md_id;			/* 0 = MD_SYS1 (argv[1], matches stock "ccci_mdinit 0") */
static int g_monitor_fd = -1;		/* /dev/ccci_monitor -- held open for our whole lifetime */
static int g_ioctl_fd = -1;		/* /dev/ccci_ioctl0 -- FSM ioctl port */
static volatile sig_atomic_t g_terminate;

static void handle_sigterm(int sig)
{
	(void)sig;
	g_terminate = 1;
}

/* vendor.mtk.md%d.status / vendor.mtk.md%d.starttime -- property names
 * recovered verbatim from the stock ccci_mdinit binary's string table
 * ("vendor.mtk.md%d.status", "vendor.mtk.md%d.starttime"). Status values
 * ("invalid"/"ready"/"reset"/"exception") are the literal tokens present
 * in the same string table; no "booting" token exists there (checked), so
 * the transitional boot period is left at "invalid" until the first HS2/
 * READY transition, matching the only 4 tokens actually observed.
 */
static void set_md_status_prop(const char *value)
{
	char key[PROPERTY_KEY_MAX];

	snprintf(key, sizeof(key), "vendor.mtk.md%hhu.status", (unsigned char)(g_md_id + 1));
	if (property_set(key, value) != 0)
		LOGW("property_set(%s=%s) failed: %s", key, value, strerror(errno));
	else
		LOGI("%s = %s", key, value);
}

static void set_md_starttime_prop(void)
{
	char key[PROPERTY_KEY_MAX];
	char val[PROPERTY_VALUE_MAX];
	struct timespec ts;

	clock_gettime(CLOCK_BOOTTIME, &ts);
	snprintf(key, sizeof(key), "vendor.mtk.md%hhu.starttime", (unsigned char)(g_md_id + 1));
	snprintf(val, sizeof(val), "%ld", (long)ts.tv_sec);
	property_set(key, val);
}

/* ------------------------------------------------------------------ */
/* /dev/ccci_monitor -- the liveness tie.                               */
/* fsm/ccci_fsm_monitor.c:35-52 (dev_char_close): if the fd we open here */
/* is ever closed (including on our own crash/exit), the kernel's        */
/* .release handler calls force_md_stop() UNCONDITIONALLY. We must hold  */
/* this fd for the whole process lifetime and never close it ourselves   */
/* except as part of a deliberate, controlled shutdown.                  */
/* ------------------------------------------------------------------ */
static int g_ccb_ctrl_fd = -1;
static int g_ipc5_fd = -1;

static int open_monitor(void)
{
	int fd = open(CCCI_DEV_MONITOR, O_RDONLY);

	if (fd < 0) {
		LOGE("open(%s) failed: %s", CCCI_DEV_MONITOR, strerror(errno));
		return -1;
	}
	LOGI("opened %s fd=%d (held for process lifetime)", CCCI_DEV_MONITOR, fd);
	return fd;
}

static int open_held_port(const char *path)
{
	int fd = open(path, O_RDWR | O_NONBLOCK);

	if (fd < 0) {
		LOGW("open(%s) failed: %s -- continuing without it", path, strerror(errno));
		return -1;
	}
	LOGI("opened %s fd=%d (held for process lifetime)", path, fd);
	return fd;
}

static int open_ioctl_port(void)
{
	int fd = open(CCCI_DEV_IOCTL0, O_RDWR);

	if (fd < 0) {
		LOGE("open(%s) failed: %s", CCCI_DEV_IOCTL0, strerror(errno));
		return -1;
	}
	return fd;
}

/* ------------------------------------------------------------------ */
/* Boot sequence                                                        */
/* ------------------------------------------------------------------ */

/*
 * Report which per-RAT firmware image variants exist on the vendor
 * partition, via CCCI_IOC_SET_MD_IMG_EXIST. This unblocks any other reader
 * of CCCI_IOC_GET_MD_IMG_EXIST (per the kernel comment, "META" -- the
 * factory test tool): fsm/ccci_fsm_ioctl.c:219-234 shows GET blocks in a
 * msleep(200) loop until per_md_data->md_img_type_is_set is set by SET.
 *
 * Filenames + bit order are read verbatim from the stock ccci_mdinit
 * binary's own string table (modem_1_2g_n.img .. modem_1_ltg_n.img); the
 * ORDER we assign to bits 0..5 matches the order those strings appear in
 * the table, which is INFERRED to be the real bit order, not proven by
 * disassembly of the bitmap-building code itself. This is pure
 * existence-reporting metadata (no NVRAM/IMEI content), so a wrong bit
 * order here is a low-risk, easily-visible-in-getprop/logcat mistake, not
 * a silent data-corruption one.
 */
static const char *const kImgSuffix[] = {
	"2g", "3g", "wg", "tg", "lwg", "ltg",
};
#define N_IMG_SUFFIX (sizeof(kImgSuffix) / sizeof(kImgSuffix[0]))

static unsigned int probe_and_report_img_exist(void)
{
	unsigned int bitmap = 0;
	size_t i;
	char path[128];

	for (i = 0; i < N_IMG_SUFFIX; i++) {
		snprintf(path, sizeof(path), "/vendor/firmware/modem_%d_%s_n.img",
			 g_md_id + 1, kImgSuffix[i]);
		if (access(path, F_OK) == 0)
			bitmap |= (1u << i);
	}
	LOGI("md%d image-exist bitmap = 0x%x (probed /vendor/firmware/modem_%d_*_n.img)",
	     g_md_id + 1, bitmap, g_md_id + 1);

	if (ioctl(g_ioctl_fd, CCCI_IOC_SET_MD_IMG_EXIST, &bitmap) < 0)
		LOGW("CCCI_IOC_SET_MD_IMG_EXIST failed: %s", strerror(errno));
	return bitmap;
}

static void log_md_boot_mode(void)
{
	unsigned int mode = 0;

	if (ioctl(g_ioctl_fd, CCCI_IOC_GET_MD_BOOT_MODE, &mode) < 0) {
		LOGW("fail to ioctl CCCI_IOC_GET_MD_BOOT_MODE err_no=%d", errno);
		return;
	}
	LOGI("md%d boot mode = %u (0=normal,1=meta)", g_md_id + 1, mode);
}

#define NVRAM_READY_POLL_MS 200
#define NVRAM_READY_MAX_RETRY 50 /* 10s total, matches the class of timeout
				   * mdinit itself uses elsewhere (BOOT_TIMEOUT
				   * is 30s kernel-side; we do not need to wait
				   * anywhere near that long for a property a
				   * same-boot-stage daemon sets) */

static int wait_nvram_ready(void)
{
	char val[PROPERTY_VALUE_MAX];
	int retry;

	for (retry = 0; retry < NVRAM_READY_MAX_RETRY; retry++) {
		property_get("vendor.service.nvram_restore", val, "");
		LOGI("property_get(\"vendor.service.nvram_restore\") = %s, read_nvram_ready_retry = %d",
		     val, retry);
		if (val[0] != '\0' && strcmp(val, "0") != 0)
			return 0;
		usleep(NVRAM_READY_POLL_MS * 1000);
	}
	LOGW("Get nvram restore ready faild !!!");
	return -1;
}

/* Best-effort MD_SBP read. Returns the sbp code, or 0 (MD_LOAD_TYPE
 * "invalid"/unset, ccci_modem.h enum MD_LOAD_TYPE starts at 1) on any
 * failure -- a missing/unreadable SBP file is not fatal, the kernel will
 * still boot the modem with sbp=0.
 */
static int read_md_sbp(void)
{
	int lid, size = 0, sbp = 0;
	struct nvm_file_desc d;
	unsigned char buf[4];

	lid = NVM_GetLIDByName("/mnt/vendor/nvdata/APCFG/APRDCL/MD_SBP");
	if (lid < 0) {
		char prop[PROPERTY_VALUE_MAX];

		/* Q25 musl: no libnvram; take the operator-set SBP code if any */
		property_get("persist.vendor.mtk_usp_md_sbp_code", prop, "0");
		LOGW("NVM_GetLIDByName(MD_SBP) unavailable, sbp from property = %s", prop);
		return atoi(prop);
	}
	d = NVM_GetFileDesc(lid, &size, buf /* reserved, non-NULL scratch */, 0 /* read */);
	if (d.fd < 0) {
		LOGW("get_nvram_ef_data: Fail to get nvram file descriptor!! fid:%d, errno:0x%x",
		     lid, errno);
		return 0;
	}
	if (size <= 0 || (size_t)size > sizeof(buf))
		size = sizeof(buf);
	if (read(d.fd, buf, (size_t)size) != size) {
		LOGW("get_nvram_ef_data: Fail to read nvram file!! fid:%d, errno:0x%x",
		     lid, errno);
	} else {
		sbp = buf[0];
	}
	if (!NVM_CloseFileDesc(d.fd, d.token))
		LOGW("get_nvram_ef_data: Fail to close nvram file!! fid:%d, errno:0x%x",
		     lid, errno);
	return sbp;
}

#if MINDONE_ENABLE_BINREGION_RESTORE
static void maybe_restore_bin_region(void)
{
	int ret = NVM_RestoreFromBinRegion_OneFile(-1,
			"/mnt/vendor/nvdata/APCFG/APRDCL/MD_SBP");
	if (ret == 0)
		LOGW("%s restore bin_region unsupport", "MD_SBP"); /* verbatim stock string */
	else
		LOGI("NVM_RestoreFromBinRegion_OneFile ok");
}
#endif

static void nvram_sync_step(int *out_sbp)
{
	*out_sbp = 0;
	if (wait_nvram_ready() != 0)
		return; /* non-fatal: proceed to boot anyway, see block comment above */
	*out_sbp = read_md_sbp();
	LOGI("Get: nvram_sbp=%d, set sbp=%d", *out_sbp, *out_sbp);
#if MINDONE_ENABLE_BINREGION_RESTORE
	maybe_restore_bin_region();
#else
	LOGI("bin-region restore step compiled out (MINDONE_ENABLE_BINREGION_RESTORE=0) -- see nvram_shim.h risk writeup");
#endif
}

/* MD_DBG_DUMP_ALL / MD_DBG_DUMP_INVALID come from inc/ccci_modem.h but we
 * do not include that kernel-internal header (it is not part of the
 * userspace ABI, only the ioctl+array layout is) -- reproduce the two
 * sentinel values we actually use, cited by the same file:line as
 * common/ccci_ioctl.h's MD_DBG_DUMP_INVALID.
 */
#define MD_DBG_DUMP_INVALID_LOCAL MD_DBG_DUMP_INVALID
#define MD_DBG_DUMP_ALL_LOCAL 0x7FFFFFFF /* inc/ccci_modem.h:82 */

static int set_boot_data(int sbp, unsigned int md_type)
{
	unsigned int boot_data[MD_BOOT_DATA_LEN];
	char prop[PROPERTY_VALUE_MAX];
	char rat[MD_CFG_RAT_STR_BYTES];
	int dbg_dump = 0;

	memset(boot_data, 0, sizeof(boot_data));

	property_get("persist.vendor.ccci.md1.dbg_dump", prop, "0");
	dbg_dump = atoi(prop);

	boot_data[MD_CFG_MDLOG_MODE] = 0;
	boot_data[MD_CFG_SBP_CODE] = (unsigned int)sbp;
	boot_data[MD_CFG_DUMP_FLAG] = (unsigned int)(dbg_dump ? MD_DBG_DUMP_ALL_LOCAL : MD_DBG_DUMP_INVALID_LOCAL);
	boot_data[MD_CFG_SBP_SUB_ID] = 0;

	property_get("persist.vendor.md_c2k_cap_dep_check", prop, "0");
	boot_data[MD_CFG_RAT_CHK_FLAG] = (unsigned int)atoi(prop);

	/* String field, 24 bytes across slots 5..10. Truncate rather than overrun; the stock
	 * leaves the field zeroed when the property is unset, so do the same. */
	memset(rat, 0, sizeof(rat));
	if (property_get("ro.vendor.mtk_protocol1_rat_config", prop, "") > 0) {
		strncpy(rat, prop, sizeof(rat) - 1);
		memcpy(&boot_data[MD_CFG_RAT_STR0], rat, sizeof(rat));
	}

	boot_data[MD_CFG_WM_IDX] = md_type;

	LOGI("set md boot data:mdl=%u sbp=%u dbg_dump=%u sbp_sub=%u rat_chk=%u rat='%s' wm_idx=%u",
	     boot_data[MD_CFG_MDLOG_MODE], boot_data[MD_CFG_SBP_CODE],
	     boot_data[MD_CFG_DUMP_FLAG], boot_data[MD_CFG_SBP_SUB_ID],
	     boot_data[MD_CFG_RAT_CHK_FLAG], rat, boot_data[MD_CFG_WM_IDX]);

	if (ioctl(g_ioctl_fd, CCCI_IOC_SET_BOOT_DATA, boot_data) < 0) {
		LOGE("CCCI_IOC_SET_BOOT_DATA failed: %s", strerror(errno));
		return -1;
	}
	return 0;
}

static unsigned int store_md_type(void)
{
	unsigned int type = 0;

	if (ioctl(g_ioctl_fd, CCCI_IOC_GET_MD_TYPE, &type) < 0) {
		LOGW("CCCI_IOC_GET_MD_TYPE failed: %s -- not storing a type", strerror(errno));
		return 0;
	}
	LOGI("md type = %u", type);
	if (ioctl(g_ioctl_fd, CCCI_IOC_STORE_MD_TYPE, &type) < 0)
		LOGW("CCCI_IOC_STORE_MD_TYPE(%u) failed: %s", type, strerror(errno));
	else
		LOGI("stored md type %u (matches the stock store_modem_type_val step)", type);
	return type;
}

static void send_battery_info(void)
{
	/* The message goes TO the modem, so it only lands once the modem can receive one: sending
	 * it before the start returns CCCI error 304. Called after the start instead. */
	if (ioctl(g_ioctl_fd, CCCI_IOC_SEND_BATTERY_INFO) < 0)
		LOGW("CCCI_IOC_SEND_BATTERY_INFO failed: %s", strerror(errno));
	else
		LOGI("sent battery info to md%d (stock V2 boot step)", g_md_id + 1);
}

#define TIME_SRV_REARM_SECS (365 * 24 * 3600) /* horizon; re-armed each loop, never meant to expire */

static int g_ipc_fd = -1;

/* Minutes west of UTC. gettimeofday()'s tz is the stock's source, but on Android the kernel's
 * sys_tz is often left at zero, in which case it says "UTC" for a device that is not on UTC.
 * Fall back to the offset the C library actually knows, and say which source was used -- a
 * correct offset cannot be worse for the modem than a wrong one ("the stock does it" is not a
 * justification).
 */
static int current_tz_minuteswest(const char **src)
{
	struct timezone tz;
	struct timeval tv;
	time_t now;
	struct tm lt;

	/* tv is unused, but bionic marks the first parameter non-null (the stock passes NULL and
	 * gets away with it; -Werror here would not). */
	memset(&tz, 0, sizeof(tz));
	memset(&tv, 0, sizeof(tv));
	if (gettimeofday(&tv, &tz) == 0 && tz.tz_minuteswest != 0) {
		*src = "kernel sys_tz";
		return tz.tz_minuteswest;
	}

	now = time(NULL);
	memset(&lt, 0, sizeof(lt));
	if (localtime_r(&now, &lt) != NULL) {
		*src = "localtime gmtoff";
		return (int)(-lt.tm_gmtoff / 60); /* gmtoff is seconds EAST, this wants minutes WEST */
	}

	*src = "unknown, assuming UTC";
	return 0;
}

static void *time_update_thread(void *unused)
{
	int tfd;

	(void)unused;
	prctl(PR_SET_NAME, "mindone_timesrv", 0, 0, 0);

	tfd = timerfd_create(CLOCK_REALTIME, TFD_CLOEXEC);
	if (tfd < 0) {
		LOGW("timerfd_create failed: %s -- no clock-step notifications for the modem",
		     strerror(errno));
		return NULL;
	}

	for (;;) {
		struct itimerspec its;
		uint64_t ticks;
		ssize_t n;
		const char *src = "";
		int tz;

		memset(&its, 0, sizeof(its));
		its.it_value.tv_sec = time(NULL) + TIME_SRV_REARM_SECS;
		if (timerfd_settime(tfd, TFD_TIMER_ABSTIME | TFD_TIMER_CANCEL_ON_SET,
				    &its, NULL) < 0) {
			LOGW("timerfd_settime failed: %s -- stopping the time watch", strerror(errno));
			break;
		}

		n = read(tfd, &ticks, sizeof(ticks));
		if (n == (ssize_t)sizeof(ticks))
			continue; /* horizon reached, nothing happened -- just re-arm */
		if (n < 0 && errno == EINTR)
			continue;
		if (n < 0 && errno != ECANCELED) {
			LOGW("timerfd read failed: %s -- stopping the time watch", strerror(errno));
			break;
		}

		/* ECANCELED: someone stepped the wall clock. Tell the modem. */
		tz = current_tz_minuteswest(&src);
		if (g_ipc_fd < 0)
			continue;
		if (ioctl(g_ipc_fd, CCCI_IPC_UPDATE_TIME, (unsigned long)tz) < 0)
			LOGW("CCCI_IPC_UPDATE_TIME(%d) failed: %s", tz, strerror(errno));
		else
			LOGI("wall clock stepped -- sent time to md%d (tz %d min west, from %s)",
			     g_md_id + 1, tz, src);
	}

	close(tfd);
	return NULL;
}

/* Non-fatal throughout: a modem without a timezone still boots, and refusing to boot over the
 * time service would be a worse failure than running without it. */
static void time_srv_init(void)
{
	pthread_t th;
	const char *src = "";
	int tz, rc;

	/* The port is exclusive: reuse the fd held since startup. */
	g_ipc_fd = (g_ipc5_fd >= 0) ? g_ipc5_fd : open(CCCI_DEV_IPC_5, O_RDWR);
	if (g_ipc_fd < 0) {
		LOGW("open %s failed: %s -- no time service", CCCI_DEV_IPC_5, strerror(errno));
		return;
	}

	tz = current_tz_minuteswest(&src);
	if (ioctl(g_ipc_fd, CCCI_IPC_UPDATE_TIMEZONE, (unsigned long)tz) < 0) {
		LOGW("CCCI_IPC_UPDATE_TIMEZONE(%d) failed: %s", tz, strerror(errno));
		return;
	}
	LOGI("time service: timezone %d min west sent to md%d (source: %s)", tz, g_md_id + 1, src);

	rc = pthread_create(&th, NULL, time_update_thread, NULL);
	if (rc != 0) {
		LOGW("pthread_create(time_update_thread) failed: %s -- timezone sent once, "
		     "clock steps will not be forwarded", strerror(rc));
		return;
	}
	pthread_detach(th);
}

/* Modem image version, for the boot log. CCCI_IOC_GET_MD_INFO returns
 * img_info[IMG_MD].img_info.version (fsm/ccci_fsm_ioctl.c:115-118). The stock reads it in its
 * main loop; we had no equivalent, so a mismatched or stale modem image was invisible in our
 * logs. Purely informational -- never gates the boot.
 */
static void log_md_info(void)
{
	unsigned int version = 0;

	if (ioctl(g_ioctl_fd, CCCI_IOC_GET_MD_INFO, &version) < 0) {
		LOGW("CCCI_IOC_GET_MD_INFO failed: %s", strerror(errno));
		return;
	}
	LOGI("md%d image version = %u (0x%08x)", g_md_id + 1, version, version);
}

/* Stock libccci_util ccci_ccb_init_users(), called by stock mdinit before every
 * start: write one 64-byte descriptor per kernel ccb_configs[] entry into the
 * CCB_CTRL smem, {DL: page_size@0x14 buff_size@0x18 0xEEFF0011@0x1c,
 * UL: the same at +0x20}, the rest zero. The modem's ccci_shm_bm reads this
 * table at boot and asserts on an all-zero one.
 */
#define CCB_USER_NUM		3
#define CCB_DESC_SIZE		64
#define CCB_DESC_PATTERN	0xEEFF0011u

static void ccb_init_users(void)
{
	struct ccci_ccb_config *cfg = NULL;
	struct ccb_ctrl_info ci;
	unsigned int n = 0, i, u, k, written = 0;
	uint32_t *base;
	void *map;

	if (g_ccb_ctrl_fd < 0)
		return;
	memset(&ci, 0, sizeof(ci));
	if (ioctl(g_ccb_ctrl_fd, CCCI_IOC_GET_CCB_CONFIG_LENGTH, &n) < 0 || n == 0 ||
	    ioctl(g_ccb_ctrl_fd, CCCI_IOC_CCB_CTRL_INFO, &ci) < 0 || ci.ctrl_length == 0) {
		LOGE("ccb: config length/ctrl info failed: %s", strerror(errno));
		return;
	}
	cfg = calloc(n, sizeof(*cfg));
	if (!cfg)
		return;
	for (i = 0; i < n; i++) {
		cfg[i].user_id = i;
		if (ioctl(g_ccb_ctrl_fd, CCCI_IOC_GET_CCB_CONFIG, &cfg[i]) < 0) {
			LOGE("ccb: GET_CCB_CONFIG %u failed: %s", i, strerror(errno));
			goto out;
		}
	}
	map = mmap(NULL, ci.ctrl_length, PROT_READ | PROT_WRITE, MAP_SHARED, g_ccb_ctrl_fd, 0);
	if (map == MAP_FAILED) {
		LOGE("ccb: mmap ctrl (%u bytes) failed: %s", ci.ctrl_length, strerror(errno));
		goto out;
	}
	for (u = 0; u < CCB_USER_NUM; u++) {
		memset(&ci, 0, sizeof(ci));
		ci.user_id = u;
		if (ioctl(g_ccb_ctrl_fd, CCCI_IOC_CCB_CTRL_INFO, &ci) < 0) {
			LOGW("ccb: CTRL_INFO user%u failed: %s", u, strerror(errno));
			continue;
		}
		for (i = 0, k = ci.ctrl_offset; i < n; i++) {
			if (cfg[i].user_id != u)
				continue;
			if ((size_t)(k + 1) * CCB_DESC_SIZE > ci.ctrl_length)
				break;
			base = (uint32_t *)((char *)map + (size_t)k * CCB_DESC_SIZE);
			memset(base, 0, CCB_DESC_SIZE);
			base[5] = cfg[i].dl_page_size;
			base[6] = cfg[i].dl_buff_size;
			base[7] = CCB_DESC_PATTERN;
			base[13] = cfg[i].ul_page_size;
			base[14] = cfg[i].ul_buff_size;
			base[15] = CCB_DESC_PATTERN;
			k++;
			written++;
		}
	}
	munmap(map, ci.ctrl_length);
	LOGI("ccb: %u of %u buffer descriptors written to the ctrl smem", written, n);
out:
	free(cfg);
}

static int do_start_md(void)
{
	ccb_init_users();
	LOGI("issuing CCCI_IOC_DO_START_MD (comm=%s)", CCCI_MDINIT_COMM);
	if (ioctl(g_ioctl_fd, CCCI_IOC_DO_START_MD) < 0) {
		LOGE("CCCI_IOC_DO_START_MD failed: %s", strerror(errno));
		return -1;
	}
	send_battery_info();
	set_md_starttime_prop();
	return 0;
}

static int do_stop_md(unsigned int flight_flag)
{
	LOGI("issuing CCCI_IOC_DO_STOP_MD flight=%u", flight_flag);
	if (ioctl(g_ioctl_fd, CCCI_IOC_DO_STOP_MD, &flight_flag) < 0) {
		LOGE("CCCI_IOC_DO_STOP_MD failed: %s", strerror(errno));
		return -1;
	}
	return 0;
}

/* ------------------------------------------------------------------ */
/* Exception / reset / flight-mode reaction loop.                      */
/* hard requirement for any ccci_mdinit replacement: it must actually   */
/* watch for and react to exception/reset notifications, not just      */
/* fire-and-forget the initial boot."                                  */
/* ------------------------------------------------------------------ */

#define RESTART_BACKOFF_BASE_MS 1000
#define RESTART_BACKOFF_MAX_MS 30000
#define RESTART_GIVEUP_COUNT 5 /* our own policy: stop auto-restarting and
				 * just keep logging after this many
				 * consecutive failures -- not a stock value,
				 * no evidence recovered for one */

static int g_flight_mode;
static int g_consecutive_failures;

static void log_exception_type(void)
{
	unsigned int ex_type = 0;

	if (ioctl(g_ioctl_fd, CCCI_IOC_GET_MD_EX_TYPE, &ex_type) < 0) {
		LOGW("CCCI_IOC_GET_MD_EX_TYPE failed: %s", strerror(errno));
		return;
	}
	static const char *const kExReason[] = {
		"NONE", "HS1_TIMEOUT", "HS2_TIMEOUT", "WDT", "EE", "MD_NO_RESPONSE",
	};
	const char *label = (ex_type < sizeof(kExReason) / sizeof(kExReason[0]))
				? kExReason[ex_type] : "UNKNOWN";
	LOGE("modem exception type=%u (%s) [mdee_dumper_v3 board, dump handoff is kernel AEE, not this daemon]",
	     ex_type, label);
}

static void restart_md_with_backoff(const char *reason)
{
	unsigned int backoff_ms = RESTART_BACKOFF_BASE_MS;
	int i;

	set_md_status_prop("reset");
	LOGE("%s -- restarting md%d", reason, g_md_id + 1);

	if (g_consecutive_failures >= RESTART_GIVEUP_COUNT) {
		LOGE("giving up auto-restart after %d consecutive failures; manual CCCI_IOC_MD_RESET or service restart required",
		     g_consecutive_failures);
		return;
	}

	for (i = 0; i < g_consecutive_failures && backoff_ms < RESTART_BACKOFF_MAX_MS; i++)
		backoff_ms *= 2;
	if (backoff_ms > RESTART_BACKOFF_MAX_MS)
		backoff_ms = RESTART_BACKOFF_MAX_MS;

	do_stop_md(g_flight_mode ? 1 : 0);
	usleep(backoff_ms * 1000);

	if (g_flight_mode) {
		LOGI("flight mode active, not restarting md%d", g_md_id + 1);
		return;
	}
	if (do_start_md() == 0) {
		g_consecutive_failures = 0;
		set_md_status_prop("invalid"); /* back to "booting", see property comment above */
	} else {
		g_consecutive_failures++;
	}
}

static void handle_monitor_message(uint32_t msg, uint32_t reserved)
{
	switch (msg) {
	case CCCI_MD_MSG_RESET_REQUEST:
		log_exception_type();
		restart_md_with_backoff("CCCI_MD_MSG_RESET_REQUEST");
		break;
	case CCCI_MD_MSG_EXCEPTION:
		set_md_status_prop("exception");
		log_exception_type();
		restart_md_with_backoff("CCCI_MD_MSG_EXCEPTION");
		break;
	case CCCI_MD_MSG_FORCE_STOP_REQUEST:
		LOGI("MD force stop request ioctl called by muxreport-equivalent (msg=0x%x)", msg);
		do_stop_md(0);
		set_md_status_prop("reset");
		break;
	case CCCI_MD_MSG_FORCE_START_REQUEST:
		LOGI("MD force start request received (msg=0x%x)", msg);
		if (do_start_md() == 0)
			set_md_status_prop("invalid");
		break;
	case CCCI_MD_MSG_FLIGHT_STOP_REQUEST:
		LOGI("MD%d enter flight mode", g_md_id + 1); /* verbatim stock log string */
		g_flight_mode = 1;
		do_stop_md(1);
		set_md_status_prop("reset");
		break;
	case CCCI_MD_MSG_FLIGHT_START_REQUEST:
		LOGI("MD%d leave flight mode", g_md_id + 1); /* verbatim stock log string */
		g_flight_mode = 0;
		if (do_start_md() == 0)
			set_md_status_prop("invalid");
		break;
	case CCCI_MD_MSG_SEND_BATTERY_INFO:
		LOGI("md%d monitor reported a battery-info request (unexpected on this kernel -- "
		     "it answers MD_GET_BATTERY_INFO in-kernel); answering anyway", g_md_id + 1);
		send_battery_info();
		break;
	case CCCI_MD_MSG_STORE_NVRAM_MD_TYPE:
	case CCCI_MD_MSG_CFG_UPDATE:
	case CCCI_MD_MSG_RANDOM_PATTERN:
		LOGI("observed monitor msg=0x%x reserved=0x%x -- no action taken (see source comment)",
		     msg, reserved);
		break;
	default:
		LOGW("unrecognized monitor msg=0x%x reserved=0x%x", msg, reserved);
		break;
	}
}

static int poll_md_state_until_ready(int timeout_ms)
{
	unsigned int state = MD_STATE_INVALID;
	int waited = 0;

	while (waited < timeout_ms) {
		if (ioctl(g_ioctl_fd, CCCI_IOC_GET_MD_STATE, &state) == 0) {
			if (state == MD_STATE_READY) {
				set_md_status_prop("ready");
				LOGI("md%d state = READY", g_md_id + 1);
				return 0;
			}
			if (state == MD_STATE_EXCEPTION) {
				set_md_status_prop("exception");
				LOGW("md%d state = EXCEPTION while waiting for boot", g_md_id + 1);
				return -1;
			}
		}
		usleep(200 * 1000);
		waited += 200;
	}
	LOGW("md%d did not reach READY within %d ms of boot", g_md_id + 1, timeout_ms);
	return -1;
}

static void exception_loop(void)
{
	struct pollfd pfd;
	struct ccci_header hdr;
	ssize_t n;

	pfd.fd = g_monitor_fd;
	pfd.events = POLLIN;

	while (!g_terminate) {
		/* Nothing periodic happens here - the branch below says so itself. The
		 * exception arrives as POLLIN, so block instead of waking every five
		 * seconds for the life of the daemon. */
		int pr = poll(&pfd, 1, -1);

		if (pr < 0) {
			if (errno == EINTR)
				continue;
			LOGE("poll(%s) failed: %s", CCCI_DEV_MONITOR, strerror(errno));
			break;
		}
		if (pr == 0)
			continue; /* periodic wakeup, nothing to do */

		n = read(g_monitor_fd, &hdr, sizeof(hdr));
		if (n < 0) {
			if (errno == EINTR)
				continue;
			LOGE("read(%s) failed: %s", CCCI_DEV_MONITOR, strerror(errno));
			break;
		}
		if ((size_t)n < sizeof(hdr)) {
			LOGW("short read on %s: %zd/%zu bytes", CCCI_DEV_MONITOR, n, sizeof(hdr));
			continue;
		}
		if (hdr.data[0] != CCCI_MAGIC_NUM) {
			LOGW("unexpected monitor packet magic=0x%x (want 0x%x)",
			     hdr.data[0], CCCI_MAGIC_NUM);
			continue;
		}
		handle_monitor_message(hdr.data[1], hdr.reserved);
	}
}

/* ------------------------------------------------------------------ */
/* main                                                                 */
/* ------------------------------------------------------------------ */

int main(int argc, char **argv)
{
	int sbp = 0;
	unsigned int md_type = 0;

	/* Defensive: our comm already IS "ccci_mdinit" (argv[0]/exec name),
	 * this is a belt-and-suspenders call in case some future init
	 * wrapper truncates or rewrites it before exec. See common/
	 * ccci_ioctl.h's block comment on CCCI_IOC_DO_START_MD.
	 */
	prctl(PR_SET_NAME, CCCI_MDINIT_COMM, 0, 0, 0);

	g_md_id = (argc > 1) ? atoi(argv[1]) : 0;
	LOGI("mindone_mdinit starting for md_id=%d (argv mirrors stock \"ccci_mdinit %d\" invocation)",
	     g_md_id, g_md_id);

	signal(SIGTERM, handle_sigterm);
	signal(SIGINT, handle_sigterm);

	set_md_status_prop("invalid");

	g_ccb_ctrl_fd = open_held_port(CCCI_DEV_CCB_CTRL);
	g_ipc5_fd = open_held_port(CCCI_DEV_IPC_5);

	g_monitor_fd = open_monitor();
	if (g_monitor_fd < 0)
		return 1;

	g_ioctl_fd = open_ioctl_port();
	if (g_ioctl_fd < 0) {
		close(g_monitor_fd);
		return 1;
	}

	probe_and_report_img_exist();
	log_md_boot_mode();
	nvram_sync_step(&sbp);

	/*
	 * The kernel resolves the runtime RAT (ccci_modem.c, md boot-data
	 * handler) only from SET_BOOT_DATA, and CCCI_IOC_GET_MD_TYPE spins up to
	 * 6000 x msleep(50) until that RAT index exists. Send the boot data
	 * first with wm_idx 0 (rat taken from ro.vendor.mtk_protocol1_rat_config),
	 * then read back and store the resolved type.
	 */
	if (set_boot_data(sbp, 0) != 0)
		LOGW("continuing despite CCCI_IOC_SET_BOOT_DATA failure (non-fatal per kernel FSM)");
	md_type = store_md_type();
	LOGI("md%d runtime type %u", g_md_id + 1, md_type);
	log_md_info();

	time_srv_init();

	if (do_start_md() != 0) {
		LOGE("initial CCCI_IOC_DO_START_MD failed, entering exception loop anyway to observe/react to any kernel-side notification");
	} else {
		poll_md_state_until_ready(35000); /* kernel BOOT_TIMEOUT is 30s, fsm/ccci_fsm_internal.h:156 */
	}

	exception_loop();

	LOGI("mindone_mdinit exiting -- closing %s will force-stop md%d (fsm/ccci_fsm_monitor.c dev_char_close)",
	     CCCI_DEV_MONITOR, g_md_id + 1);
	close(g_ioctl_fd);
	close(g_monitor_fd);
	return 0;
}
