/*
 * SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note
 * Copyright (c) 2016 MediaTek Inc.
 * SPDX-FileCopyrightText: 2026 The LineageOS Project
 */
/*
 * mind_one CCCI userspace ABI shim.
 *
 * This header is a faithful, hand-transcribed copy of the ioctl numbers,
 * enums and wire structs that OUR kernel's CCCI driver
 * (the kernel tree's mindone/modules/ccci_md_all/) exposes to userspace.  It is
 * not a stock MediaTek header (we never had one) -- every definition below
 * is cited against the exact file:line in our own git-tracked kernel source
 * that it was copied or derived from, so the citation can be re-checked
 * against a diff of that tree.
 *
 * Do NOT "clean up" the numeric values here to look more idiomatic -- they
 * are ABI and must match the kernel exactly.
 */
#ifndef MINDONE_CCCI_IOCTL_H
#define MINDONE_CCCI_IOCTL_H

#include <linux/ioctl.h>
#include <linux/types.h>

/* ------------------------------------------------------------------ */
/* Device nodes (port table)                                           */
/* Source: the kernel repository's mindone/modules/ccci_md_all/port/port_cfg.c, md1_ccci_ports[] entries */
/* (general MT6789/Gen9x table -- selected at runtime because our DT's  */
/* mediatek,md_generation = 0x1897 = 6295 != 6293, port_cfg.c:721-736,  */
/* the stock vendor_boot DTB, nodes at :1666 and :3296).               */
/* ------------------------------------------------------------------ */
#define CCCI_DEV_MONITOR	"/dev/ccci_monitor"	/* fsm/ccci_fsm_monitor.c, fsm_monitor_name[] */
#define CCCI_DEV_IOCTL0		"/dev/ccci_ioctl0"	/* port_cfg.c:137, CCCI_DUMMY_CH port, minor 12 */
#define CCCI_DEV_IOCTL1		"/dev/ccci_ioctl1"	/* port_cfg.c:140, minor 13 */
#define CCCI_DEV_IOCTL2		"/dev/ccci_ioctl2"	/* port_cfg.c:143, minor 14 */
#define CCCI_DEV_IOCTL3		"/dev/ccci_ioctl3"	/* port_cfg.c:146, minor 15 */
#define CCCI_DEV_IOCTL4		"/dev/ccci_ioctl4"	/* port_cfg.c:149, minor 16 */
#define CCCI_DEV_FS		"/dev/ccci_fs"		/* port_cfg.c:113, CCCI_FS_TX/RX, minor 4 */
#define CCCI_DEV_CCB_CTRL	"/dev/ccci_ccb_ctrl"	/* common circular buffer control */
#define CCCI_DEV_IPC_5		"/dev/ccci_ipc_5"	/* IPC channel 5 */

#define CCCI_DEV_RPC		"/dev/ccci_rpc"		/* port_cfg.c:161, CCCI_RPC_TX/RX, minor 20 */

/* ------------------------------------------------------------------ */
/* CCCI_IOC_* -- inc/ccci_core.h:100-289 (CCCI_IOC_MAGIC = 'C')         */
/* Any open char-port fd can issue these -- port_dev_ioctl() shares one */
/* file_operations across every char port (port/port_char.c:57-69);    */
/* the dummy ports (ccci_ioctl0..4) just exist to hand out an fd with   */
/* ------------------------------------------------------------------ */
#define CCCI_IOC_MAGIC			'C'

#define CCCI_IOC_MD_RESET		_IO(CCCI_IOC_MAGIC, 0)		/* ccci_core.h:102 */
#define CCCI_IOC_GET_MD_STATE		_IOR(CCCI_IOC_MAGIC, 1, unsigned int)	/* :104 */
#define CCCI_IOC_FORCE_MD_ASSERT	_IO(CCCI_IOC_MAGIC, 4)		/* :111 */
#define CCCI_IOC_SEND_STOP_MD_REQUEST	_IO(CCCI_IOC_MAGIC, 10)		/* :123 */
#define CCCI_IOC_SEND_START_MD_REQUEST	_IO(CCCI_IOC_MAGIC, 11)		/* :125 */
#define CCCI_IOC_DO_STOP_MD		_IO(CCCI_IOC_MAGIC, 12)		/* :127 */
#define CCCI_IOC_DO_START_MD		_IO(CCCI_IOC_MAGIC, 13)		/* :129 -- comm-gated, see below */
#define CCCI_IOC_ENTER_DEEP_FLIGHT	_IO(CCCI_IOC_MAGIC, 14)		/* :131 */

/* CCB (common circular buffer) control, ccci_core.h:72-91 and :257-268. */
struct ccci_ccb_config {
	unsigned int user_id;
	unsigned char core_id;
	unsigned int dl_page_size;
	unsigned int ul_page_size;
	unsigned int dl_buff_size;
	unsigned int ul_buff_size;
};

struct ccb_ctrl_info {
	unsigned int user_id;
	unsigned int ctrl_offset;
	unsigned int ctrl_addr;
	unsigned int ctrl_length;
};

#define CCCI_IOC_GET_CCB_CONFIG_LENGTH	_IOR(CCCI_IOC_MAGIC, 63, unsigned int)
#define CCCI_IOC_GET_CCB_CONFIG		_IOWR(CCCI_IOC_MAGIC, 64, struct ccci_ccb_config)
#define CCCI_IOC_CCB_CTRL_INFO		_IOWR(CCCI_IOC_MAGIC, 71, struct ccb_ctrl_info)
#define CCCI_IOC_LEAVE_DEEP_FLIGHT	_IO(CCCI_IOC_MAGIC, 15)		/* :133 */
#define CCCI_IOC_SEND_BATTERY_INFO	_IO(CCCI_IOC_MAGIC, 21)		/* :145 */
#define CCCI_IOC_RELOAD_MD_TYPE		_IO(CCCI_IOC_MAGIC, 25)		/* :156 */
#define CCCI_IOC_SET_MD_IMG_EXIST	_IOW(CCCI_IOC_MAGIC, 29, unsigned int)	/* :168 */
#define CCCI_IOC_GET_MD_IMG_EXIST	_IOR(CCCI_IOC_MAGIC, 30, unsigned int)	/* :171 -- blocks in-kernel until SET */
#define CCCI_IOC_GET_MD_TYPE		_IOR(CCCI_IOC_MAGIC, 31, unsigned int)	/* :174 */
#define CCCI_IOC_STORE_MD_TYPE		_IOW(CCCI_IOC_MAGIC, 32, unsigned int)	/* :177 */
#define CCCI_IOC_GET_MD_TYPE_SAVING	_IOR(CCCI_IOC_MAGIC, 33, unsigned int)	/* :180 */
#define CCCI_IOC_GET_EXT_MD_POST_FIX	_IOR(CCCI_IOC_MAGIC, 34, unsigned int)	/* :183 */
#define CCCI_IOC_AP_ENG_BUILD		_IOW(CCCI_IOC_MAGIC, 36, unsigned int)	/* :189 */
#define CCCI_IOC_RESET_MD1_MD3_PCCIF	_IO(CCCI_IOC_MAGIC, 45)		/* :213 */
#define CCCI_IOC_SET_BOOT_DATA		_IOW(CCCI_IOC_MAGIC, 47, unsigned int[16])	/* :218 */
#define CCCI_IOC_SET_EFUN		_IOW(CCCI_IOC_MAGIC, 55, unsigned int)	/* :239 -- landing point of AT+EFUN */
#define CCCI_IOC_MDLOG_DUMP_DONE	_IO(CCCI_IOC_MAGIC, 56)		/* :242 */
#define CCCI_IOC_GET_OTHER_MD_STATE	_IOR(CCCI_IOC_MAGIC, 57, unsigned int)	/* :245 */
#define CCCI_IOC_SET_MD_BOOT_MODE	_IOW(CCCI_IOC_MAGIC, 58, unsigned int)	/* :248 */
#define CCCI_IOC_GET_MD_BOOT_MODE	_IOR(CCCI_IOC_MAGIC, 59, unsigned int)	/* :251 */
#define CCCI_IOC_GET_AT_CH_NUM		_IOR(CCCI_IOC_MAGIC, 60, unsigned int)	/* :254 */
#define CCCI_IOC_ENTER_DEEP_FLIGHT_ENHANCED	_IO(CCCI_IOC_MAGIC, 123)	/* :283 */
#define CCCI_IOC_LEAVE_DEEP_FLIGHT_ENHANCED	_IO(CCCI_IOC_MAGIC, 124)	/* :286 */
#define CCCI_IOC_RILD_POWER_OFF_MD	_IO(CCCI_IOC_MAGIC, 125)	/* :289 */
#define CCCI_IOC_GET_MD_EX_TYPE		_IOR(CCCI_IOC_MAGIC, 9, unsigned int)	/* :121 */

#define CCCI_IOC_SEND_RUNTIME_DATA	_IO(CCCI_IOC_MAGIC, 7)			/* ccci_core.h:117 */
#define CCCI_IOC_GET_MD_INFO		_IOR(CCCI_IOC_MAGIC, 8, unsigned int)	/* :119, img_info[IMG_MD].version */
#define CCCI_IOC_SIM_LOCK_RANDOM_PATTERN _IOW(CCCI_IOC_MAGIC, 46, unsigned int)	/* :214 */

/*
 * IPC port ioctls -- a SEPARATE magic ('P'), issued on CCCI_DEV_IPC_5, not on the ioctl node.
 * ccci_core.h:292-299; handler port/port_ipc.c:104-176.
 *
 * This is the stock's "time service", which we had no counterpart for at all: it hands the
 * modem the timezone once at startup and the wall-clock time whenever the clock is stepped.
 * UPDATE_TIMEZONE only stores the value kernel-side; UPDATE_TIME stores it AND transmits
 * seconds+timezone+DST to the modem on port ccci_0_202 (port_proxy.c:97). The argument of both
 * is the timezone in MINUTES WEST of UTC, i.e. gettimeofday()'s tz_minuteswest -- confirmed
 * from the stock's time_srv_init(), which passes exactly that field.
 */
#define CCCI_IPC_MAGIC			'P'
#define CCCI_IPC_RESET_RECV		_IO(CCCI_IPC_MAGIC, 0)
#define CCCI_IPC_RESET_SEND		_IO(CCCI_IPC_MAGIC, 1)
#define CCCI_IPC_WAIT_MD_READY		_IO(CCCI_IPC_MAGIC, 2)
#define CCCI_IPC_UPDATE_TIME		_IO(CCCI_IPC_MAGIC, 4)
#define CCCI_IPC_WAIT_TIME_UPDATE	_IO(CCCI_IPC_MAGIC, 5)
#define CCCI_IPC_UPDATE_TIMEZONE	_IO(CCCI_IPC_MAGIC, 6)

/*
 * CCCI_IOC_DO_START_MD is gated: the kernel only accepts it from a process
 * whose current->comm (task name, at most TASK_COMM_LEN-1 = 15 chars)
 * *starts with* "ccci_mdinit" (strncmp(current->comm, "ccci_mdinit",
 * strlen("ccci_mdinit")) == 0 -- fsm/ccci_fsm_ioctl.c:403,459-462, function
 * ccci_fsm_ioctl()).  This is a caller-hygiene string check, not a real
 * capability/DAC/MAC boundary (the comment in that file itself calls a
 * mismatch merely "invalid user"), but it is load-bearing: get it wrong and
 * DO_START_MD silently does nothing (the kernel logs "drop invalid
 * user:%s call MD start ioctl" and returns without touching the FSM).
 *
 * DESIGN CHOICE (this project, mindone_mdinit): ship the replacement binary
 * literally named "ccci_mdinit", installed at the same path
 * /vendor/bin/ccci_mdinit, replacing the stock blob in place. This:
 *   (a) satisfies the comm check with zero extra code (argv[0]/exec name
 *       IS the comm the kernel reads, no prctl(PR_SET_NAME) needed -- we
 *       still call it defensively at startup, see main(), in case some
 *       future init wrapper truncates or rewrites argv[0]);
 *   (b) keeps the existing SELinux file_contexts label match, i.e. zero
 *       new sepolicy: device/mediatek/sepolicy_vndr/base/vendor/file_contexts
 *       maps the path "/(vendor|system/vendor)/bin/ccci_mdinit" to
 *       "u:object_r:ccci_mdinit_exec:s0", which init_daemon_domain()
 *       (ccci_mdinit.te) turns into the "ccci_mdinit" domain with every
 *       allow rule this daemon needs already granted;
 *   (c) keeps the existing init service stanza working unmodified
 *       (init.cccimdinit.rc: "service ccci_mdinit /vendor/bin/ccci_mdinit 0").
 * The alternative (ship under a different name and call
 * prctl(PR_SET_NAME,"ccci_mdinit") before the DO_START_MD ioctl) would work
 * for the kernel gate alone but would NOT get the matching sepolicy domain
 * for free (file_contexts matches by path, prctl doesn't change SELinux
 * type) -- so it is strictly worse for this project and not used.
 */
#define CCCI_MDINIT_COMM		"ccci_mdinit"

/* ------------------------------------------------------------------ */
/* MD_STATE_FOR_USER -- what CCCI_IOC_GET_MD_STATE actually returns.    */
/* Source: the kernel repository's mindone/modules/include/.../mt-plat/mtk_ccci_common.h:323-328         */
/* (mtk_ccci_common.h is outside the module tree proper -- shared platform       */
/* header pulled in via ccci_core.h:19 -- but is part of our build).    */
/* ------------------------------------------------------------------ */
enum md_state_for_user {
	MD_STATE_INVALID	= 0,
	MD_STATE_BOOTING	= 1,
	MD_STATE_READY		= 2,
	MD_STATE_EXCEPTION	= 3,
};

/* ------------------------------------------------------------------ */
/* struct ccci_header -- the 1:1 wire header on every CCCI channel,     */
/* INCLUDING the synthetic messages fsm_monitor_send_message() queues   */
/* for userspace to read() off /dev/ccci_monitor.                       */
/* Source: mtk_ccci_common.h:77-84, verbatim field list (bitfield       */
/* packing is left to the compiler on both kernel and userspace side of */
/* this exact same field list, so sizeof() matches without us having to */
/* hardcode a byte count -- see fsm/ccci_fsm_monitor.c:142-153 for how   */
/* the kernel itself constructs one of these by hand with skb_put()).   */
/* ------------------------------------------------------------------ */
struct ccci_header {
	__u32 data[2];		/* data[0]==CCCI_MAGIC_NUM, data[1]==msg id on /dev/ccci_monitor */
	__u16 channel : 16;
	__u16 seq_num : 15;
	__u16 assert_bit : 1;
	__u32 reserved;
} __attribute__((packed));

#define CCCI_MAGIC_NUM		0xFFFFFFFFu	/* ccci_core.h:26 */
#define CCCI_MONITOR_CH_ID	0xf0000000u	/* ccci_core.h:552, "for mdinit" */

enum ccci_md_msg {
	CCCI_MD_MSG_FORCE_STOP_REQUEST		= 0xFAF50001,
	CCCI_MD_MSG_FLIGHT_STOP_REQUEST	= 0xFAF50002,
	CCCI_MD_MSG_FORCE_START_REQUEST	= 0xFAF50003,
	CCCI_MD_MSG_FLIGHT_START_REQUEST	= 0xFAF50004,
	CCCI_MD_MSG_RESET_REQUEST		= 0xFAF50005,
	CCCI_MD_MSG_EXCEPTION			= 0xFAF50006,
	CCCI_MD_MSG_SEND_BATTERY_INFO		= 0xFAF50007,
	CCCI_MD_MSG_STORE_NVRAM_MD_TYPE	= 0xFAF50008,
	CCCI_MD_MSG_CFG_UPDATE			= 0xFAF50009,
	CCCI_MD_MSG_RANDOM_PATTERN		= 0xFAF5000A,
};

/*
 * md_boot_data[16] layout for CCCI_IOC_SET_BOOT_DATA.
 * Source: inc/ccci_modem.h:92-105 (anonymous enum) + fsm/ccci_fsm_ioctl.c:
 * 120-150 (CCCI_IOC_SET_BOOT_DATA handler, copies whole array verbatim into
 * per_md_data->md_boot_data[16]) -- index order below is the enum's
 * declaration order, confirmed against ccci_mdinit's own log string
 * "set md boot data:mdl=%d sbp=%d dbg_dump=%d sbp_sub=%d" (first 4 slots).
 */
enum md_boot_data_idx {
	MD_CFG_MDLOG_MODE	= 0,	/* "mdl" in mdinit's log string */
	MD_CFG_SBP_CODE		= 1,	/* "sbp" -- Sales/Branding code, see NVRAM step */
	MD_CFG_DUMP_FLAG	= 2,	/* "dbg_dump" -- bit MD_DBG_DUMP_PORT (ccci_modem.h) triggers port-traffic dump */
	MD_CFG_SBP_SUB_ID	= 3,	/* "sbp_sub" */
	MD_CFG_RAT_CHK_FLAG	= 4,
	MD_CFG_RAT_STR0		= 5,
	MD_CFG_RAT_STR1		= 6,
	MD_CFG_RAT_STR2		= 7,
	MD_CFG_RAT_STR3		= 8,
	MD_CFG_RAT_STR4		= 9,
	MD_CFG_RAT_STR5		= 10,
	MD_CFG_WM_IDX		= 11,
	MD_BOOT_DATA_LEN	= 16,	/* array is unsigned int[16], slots 12-15 unused/reserved */
};

#define MD_CFG_RAT_STR_BYTES	((MD_CFG_WM_IDX - MD_CFG_RAT_STR0) * sizeof(unsigned int))

#define MD_DBG_DUMP_INVALID	(-1)	/* inc/ccci_modem.h:65, sentinel meaning "not set" */
#define MD_DBG_DUMP_PORT	24	/* inc/ccci_modem.h:79, bit tested via (1 << MD_DBG_DUMP_PORT) in fsm/ccci_fsm_ioctl.c:132 */

#endif /* MINDONE_CCCI_IOCTL_H */
