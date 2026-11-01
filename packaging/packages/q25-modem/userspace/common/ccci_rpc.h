/*
 * SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note
 * Copyright (c) 2016 MediaTek Inc.
 * SPDX-FileCopyrightText: 2026 The LineageOS Project
 */

#ifndef MINDONE_CCCI_RPC_H
#define MINDONE_CCCI_RPC_H

#include <linux/types.h>
#include "ccci_ioctl.h"

/* port_rpc.h:11-58 -- full op-id enum. CONFIG_MTK_TC1_FEATURE (the LGE
 * China-market plugin block) is NOT set in our kernel config
 * (tools/kconfig/running-6.12-1209.config has no such symbol at all), so
 * those op-ids never reach userspace on our board and are omitted here;
 * they are listed in port_rpc.h if ever needed.
 */
enum ccci_rpc_op_id {
	IPC_RPC_CPSVC_SECURE_ALGO_OP	= 0x2001,
	IPC_RPC_GET_SECRO_OP		= 0x2002,
	IPC_RPC_GET_TDD_EINT_NUM_OP	= 0x4001,
	IPC_RPC_GET_GPIO_NUM_OP	= 0x4002,
	IPC_RPC_GET_ADC_NUM_OP		= 0x4003,
	IPC_RPC_GET_EMI_CLK_TYPE_OP	= 0x4004,
	IPC_RPC_GET_EINT_ATTR_OP	= 0x4005,
	IPC_RPC_GET_GPIO_VAL_OP	= 0x4006,
	IPC_RPC_GET_ADC_VAL_OP		= 0x4007,
	IPC_RPC_GET_RF_CLK_BUF_OP	= 0x4008,
	IPC_RPC_GET_GPIO_ADC_OP	= 0x4009,
	IPC_RPC_USIM2NFC_OP		= 0x400A,
	IPC_RPC_DSP_EMI_MPU_SETTING	= 0x400B,
	/* 0x400C reserved */
	IPC_RPC_CCCI_LHIF_MAPPING	= 0x400D,
	IPC_RPC_DTSI_QUERY_OP		= 0x400E,
	IPC_RPC_QUERY_AP_SYS_PROPERTY	= 0x400F,
	IPC_RPC_SAR_TABLE_IDX_QUERY_OP	= 0x4010,
	IPC_RPC_EFUSE_BLOWING		= 0x4011,
	IPC_RPC_TRNG			= 0x4012,
	IPC_RPC_QUERY_CARD_TYPE	= 0x4013,
	IPC_RPC_AMMS_DRDI_CONTROL	= 0x4014,
	IPC_RPC_SAVE_MD_CAPID		= 0x4015,
	IPC_RPC_IT_OP			= 0x4321,
};


/* port_rpc.h:60-70 */
struct rpc_pkt {
	unsigned int len;
	void *buf;
} __attribute__((packed));

struct rpc_buffer {
	struct ccci_header header;
	__u32 op_id;
	__u32 para_num;
	__u8 buffer[];
} __attribute__((packed));

#define RPC_REQ_BUFFER_NUM	2	/* port_rpc.h:190 */
#define RPC_MAX_ARG_NUM		6	/* port_rpc.h:191 */
#define RPC_MAX_BUF_SIZE	2048	/* port_rpc.h:192 */
#define RPC_API_RESP_ID		0xFFFF0000u	/* port_rpc.h:193 -- OR'd into op_id on the reply */

/* Generic CCCI file/rpc-service answer codes -- port_rpc.h:195-202.
 * Shared between the RPC and FS (ccci_fs) wire protocols; ccci_fsd uses the
 * same constants (see fsd/ccci_fsd.c), confirmed by both being declared in
 * the same kernel header with no FS-specific variant existing anywhere in
 * the tree.
 */
#define FS_NO_ERROR		0
#define FS_NO_OP		(-1)
#define FS_PARAM_ERROR		(-2)
#define FS_NO_FEATURE		(-3)
#define FS_NO_MATCH		(-4)
#define FS_FUNC_FAIL		(-5)
#define FS_ERROR_RESERVED	(-6)
#define FS_MEM_OVERFLOW		(-7)

#endif /* MINDONE_CCCI_RPC_H */
