/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef _Q25_MD1_OWNER_H
#define _Q25_MD1_OWNER_H
#include <linux/types.h>

#define Q25_CHK_V6_SIZE	512

struct device_node;

struct q25_md1_lkinfo_in {
	const u8 *chk_hdr;		/* v6 CHECK_HEADER copy */
	u64 img_base;
	u64 nc_base, c_base;
	u32 nc_size, c_size;
	void __iomem *tag_va;		/* 64 KiB tag carve-out */
	u64 tag_phys;
	struct device_node *mddriver;
};

struct q25_md1_layout {
	u32 nc_total, c_total;
	u32 tag_bytes, tag_num;
};

int q25_md1_build_lkinfo(struct q25_md1_lkinfo_in *in, struct q25_md1_layout *out);
#endif
