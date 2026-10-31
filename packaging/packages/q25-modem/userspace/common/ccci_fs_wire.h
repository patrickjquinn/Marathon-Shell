/*
 * SPDX-License-Identifier: Apache-2.0
 * SPDX-FileCopyrightText: 2026 The LineageOS Project
 */

#ifndef MINDONE_CCCI_FS_WIRE_H
#define MINDONE_CCCI_FS_WIRE_H

#include <stdint.h>
#include "ccci_ioctl.h"		/* struct ccci_header, CCCI_DEV_FS */

/* ------------------------------------------------------------------ */
/* Physical/transport constants                                        */
/* ------------------------------------------------------------------ */
#define CCCI_FS_CHANNEL_RX	14	/* the kernel module tree port_cfg.c CCCI_FS_RX; validated
					 * live by the stock daemon itself,
					 * main+0x1e04 (VA 0xb5a8): `cmp r0,#0xe` */
#define CCCI_FS_READ_CHUNK	0xd94	/* 3476 -- single read(2) cap, main+0xc6c
					 * (VA 0xb410): `movw r2, #0xd94` */
#define CCCI_FS_INST_BUF_A	0x4014	/* per-instance reassembly buffer size,
					 * variant A (main+0xe38, VA 0xb5c4) */
#define CCCI_FS_INST_BUF_B	0x40dc	/* variant B, same call site, selected
					 * by a global byte flag not resolved
					 * in this pass */

/* ------------------------------------------------------------------ */
/* FS_CCCI_CMPT_Write request -- offsets verified against FS_CCCI_CMPT_ */
/* Write, VA 0xe0fc-0xe470. Base pointer used by fsd/ccci_fsd.c: PAYLOAD */
/* START (wire-buffer + sizeof(struct ccci_header)) -- see the CAVEAT    */
/* above the struct definitions on why the stock binary's own base      */
/* pointer (which overlaps the dead header bytes) is not reused as-is.  */
/* ------------------------------------------------------------------ */
struct ccci_fs_cmpt_write_req {
	uint32_t opid_map;	/* +0x00 BITMASK, not an enum. Bits observed  *
				 * live-tested in FS_CCCI_CMPT_Write:         *
				 *   bit0 (0x01) OPEN   -- FS_CCCI_Open+0x2e   *
				 *   bit2 (0x04) SEEK   -- +0x54                *
				 *   bit5 (0x20) WRITE  -- +0x7c (NOTE: bit5,  *
				 *                         not bit3 as in the *
				 *                         read-side bitmask) *
				 *   bit4 (0x10) CLOSE  -- +0xa8                */
	uint8_t  _reserved_04[8];	/* +0x04..+0x0b, not read by this handler */
	uint32_t flag;		/* +0x0c open() flags, passed verbatim as
				 * FS_CCCI_Open's 2nd arg (+0x14: `ldr r1,
				 * [r4,#0xc]; ... bl FS_CCCI_Open`) */
	uint32_t offset;	/* +0x10 seek offset (+0x64: `ldr r1,[r4,#0x10]`) */
	uint32_t whence;	/* +0x14 seek whence (+0x68: `ldr r2,[r4,#0x14]`) */
	uint8_t  _reserved_18[4];	/* +0x18..+0x1b */
	uint32_t length;	/* +0x1c write length (+0x86: `ldr r2,[r4,#0x1c]`),
				 * passed as FS_CCCI_Write's 2nd arg */
	int32_t  file_handle;	/* +0x20 EXISTING handle to reuse; if >= 0 the
				 * OPEN step (and its filename/flag fields) is
				 * SKIPPED entirely and this handle is used
				 * directly for seek/write/close (`ldr sl,
				 * [r7,#-8]` where r7==buf+0x28, i.e. reads
				 * +0x20; `cmn sl,#1; ble ...` = branch to the
				 * open path only if handle < 0) */
	uint32_t _reserved_24;	/* +0x24 zeroed by the daemon before dispatch
				 * (`str r5,[r7,#0x28]!` zeroes buf+0x28 as a
				 * side effect of computing the payload
				 * pointer, but +0x24 itself is set to 0 by an
				 * explicit local store earlier in the function
				 * prologue) */
	uint8_t  data[];	/* +0x28 payload bytes to write -- confirmed by
				 * `mov r3, r7` where r7 == buf+0x28, passed as
				 * FS_CCCI_Write's 4th arg (data pointer) */
} __attribute__((packed));

/* ------------------------------------------------------------------ */
/* FS_CCCI_CMPT_Read request -- base = reassembled buffer OFFSET 0x30   */
/* (0x30 bytes further in than the write-side struct above; the gap    */
/* is presumed to hold the inline wide-char filename for read-shaped   */
/* requests, but the exact filename offset was NOT independently       */
/* confirmed in this pass -- see OPEN item above).                     */
/* Verified against FS_CCCI_CMPT_Read, VA 0xdc24-0xe0fc.                */
/* ------------------------------------------------------------------ */
struct ccci_fs_cmpt_read_req {
	uint32_t opid_map;	/* +0x00 (buffer+0x30) BITMASK. Bits observed:  *
				 *   bit0 (0x01) OPEN     -- +0x44 (VA 0xdc68)  *
				 *   bit1 (0x02) GET_SIZE -- +0x104 (VA 0xdd28) *
				 *   bit2 (0x04) SEEK     -- +0x1a4 (VA 0xddc8) *
				 *   bit3 (0x08) READ     -- +0x1c4 (VA 0xdde8) *
				 *   bit4 (0x10) CLOSE    -- +0x1f0 (VA 0xde14) */
	uint8_t  _reserved_04[8];	/* +0x04..+0x0b (buffer+0x34..0x3b) */
	uint32_t flag;		/* +0x0c (buffer+0x3c) open() flags, 2nd arg to
				 * FS_CCCI_Open */
	uint32_t size_out;	/* +0x10 (buffer+0x40) destination for
				 * FS_CCCI_GetFileSize's 2nd arg (an out-param
				 * pointer, per that function's own signature --
				 * NOT itself the size value) */
	uint32_t offset;	/* +0x14 (buffer+0x44) seek offset */
	uint32_t whence;	/* +0x18 (buffer+0x48) seek whence */
	uint32_t read_arg1;	/* +0x1c (buffer+0x4c) FS_CCCI_Read's 2nd arg;
				 * exact semantics (a 2nd length bound? a flags
				 * word?) not resolved in this pass (OPEN) */
	uint32_t length;	/* +0x20 (buffer+0x50) FS_CCCI_Read's 3rd arg
				 * (read length) */
	/* +0x24 (buffer+0x54): read PAYLOAD DATA starts here. The daemon
	 * zeroes the first word here before calling FS_CCCI_Read
	 * (`str r0,[r6,#0x24]!` at FS_CCCI_CMPT_Read+0x38, VA 0xdc5c, where
	 * r0==0 at that point) and passes this same address as
	 * FS_CCCI_Read's 4th arg (destination buffer). Not represented as a
	 * named field here because C can't express "zero-length array
	 * starting mid-struct with a leading zeroed word" cleanly; a
	 * consumer should treat bytes [0x24, 0x24+length) as the payload. */
} __attribute__((packed));

/* ------------------------------------------------------------------ */
/* Fixed-size ack response -- confirmed at main+0x1894-0x1900           */
/* (VA 0xcbd0-0xcc08), used for the ~25 "modern" individual-op path.    */
/* The SAME reassembled buffer is reused in place for the response:     */
/* the leading ccci_header's data[0] has its top bit cleared (was the   */
/* with the total response size below, then write(2)'d back verbatim.  */
/* ------------------------------------------------------------------ */
struct ccci_fs_ack_resp {
	struct ccci_header header;	/* data[1] set to sizeof(this struct) == 0x18 (24) */
	int32_t  result;		/* +0x10 FS_NO_ERROR..<see result codes below> */
	uint32_t _unused;		/* +0x14 always 0 in the traced ack path */
} __attribute__((packed));		/* total 0x18 (24) bytes -- matches the
					 * `mov r7,#0x18` / `cmp r0,r7` write(2)
					 * size check at main+0x1898 (VA 0xcbd4) */

/* ------------------------------------------------------------------ */
/* Variable-size data response -- confirmed at main+0x18f0-0x1970       */
/* (VA 0xcf40-0xcf88), used for the CMPT_Read payload-bearing reply.    */
/* total size = 0x14 (20) + <bytes actually returned>. 20 = 16-byte     */
/* header + one 4-byte result/status word, i.e. NO secondary field      */
/* before the payload on this path (unlike the fixed ack above, which   */
/* carries an extra always-0 word) -- both are proven independently,    */
/* the difference is real, not a transcription error.                  */
/* ------------------------------------------------------------------ */
struct ccci_fs_data_resp {
	struct ccci_header header;	/* data[1] set to 0x14 + data_len */
	int32_t  result;		/* +0x10 */
	uint8_t  data[];		/* +0x14, data_len bytes, data_len taken
					 * from the byte count FS_CCCI_Read (or
					 * the equivalent handler) actually
					 * returned */
} __attribute__((packed));

/* ------------------------------------------------------------------ */
/* Result codes.
 * -1..-7 are the SAME enum already declared in ccci_rpc.h (shared
 * between /dev/ccci_rpc and /dev/ccci_fs per that header's own comment --
 * both wire protocols are answered from the same kernel header, no
 * FS-specific variant exists). The additional codes below were found by
 * scanning every FS_CCCI_ and OTP_ function's `mvn` (bitwise-NOT-immediate)
 * result-building instructions; only four are independently pinned to a
 * specific errno by FS_ErrorConv (VA 0x1af38-0x1afd0) -- the rest are
 * confirmed to EXIST as distinct result values (with the cited call site
 * as evidence) but their correct symbolic NAME was not established in
 * this pass, so they are listed as OPEN numeric constants rather than
 * guessed at.
 * ------------------------------------------------------------------ */
/* Already known (ccci_rpc.h), repeated here only in a comment for
 * locality -- do NOT redefine, include ccci_rpc.h for these:
 *   FS_NO_ERROR=0 FS_NO_OP=-1 FS_PARAM_ERROR=-2 FS_NO_FEATURE=-3
 *   FS_NO_MATCH=-4 FS_FUNC_FAIL=-5 FS_ERROR_RESERVED=-6 FS_MEM_OVERFLOW=-7
 */
#define FS_ERR_ENOENT_MAPPED	(-9)	/* FS_ErrorConv: errno==ENOENT(2) -> -9,
					 * VA 0x1afac-0x1afb8 */
#define FS_ERR_EACCES_MAPPED	(-16)	/* FS_ErrorConv: errno==EACCES(13) -> -16,
					 * VA 0x1afa0-0x1afa8 */
#define FS_ERR_EMFILE_MAPPED	(-5)	/* FS_ErrorConv: errno==EMFILE(24) -> -5
					 * (coincides with FS_FUNC_FAIL), VA
					 * 0x1af94-0x1af9c */
#define FS_ERR_GENERIC_MAPPED	(-18)	/* FS_ErrorConv: any other errno -> -18,
					 * VA 0x1afac-0x1afb4 (default arm) */

#endif /* MINDONE_CCCI_FS_WIRE_H */
