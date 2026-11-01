/*
 * SPDX-License-Identifier: GPL-2.0
 * Copyright (c) 2016 MediaTek Inc.
 * SPDX-FileCopyrightText: 2026 The LineageOS Project
 */

#include "ccci_rpc.h"
#include "ccci_rpc_route.h"

int ccci_rpc_is_userspace_op(unsigned int op_id)
{
	switch (op_id) {
	case IPC_RPC_QUERY_AP_SYS_PROPERTY:
	case IPC_RPC_SAR_TABLE_IDX_QUERY_OP:
	case IPC_RPC_AMMS_DRDI_CONTROL:
	case IPC_RPC_SAVE_MD_CAPID:
		return 1;
	default:
		return 0;
	}
}
