// SPDX-License-Identifier: GPL-2.0-only
/*
 * LK-stage hand-off for the MediaTek ECCCI kernel stack.
 *
 * Ported from Gigaset-dev/lk2 ab107ff351cb (MediaTek, MIT licence):
 *   platform/mediatek/common/md/ccci_ld_md_tag_dt.c   tag container
 *   platform/mediatek/common/md/ccci_ld_ap_md_smem.c  smem layout + tags
 *   platform/mediatek/common/md/ccci_ld_md_ass.c      header tags
 *   platform/mediatek/common/md/ccci_ld_md_core.c     hdr_count/hdr_tbl_inf
 *   platform/mediatek/mt6789/md/ccci_lk_plat.{c,h}    MT6789 tables
 * Consumer: eccci ccci_util_lib_fo.c collect_lk_boot_arguments().
 */
#include <linux/io.h>
#include <linux/kernel.h>
#include <linux/of.h>
#include <linux/slab.h>
#include <linux/string.h>
#include <linux/unaligned.h>

#include "q25-md1-owner.h"

#define TAG_MAX_SIZE		0x10000
#define TAG_NAME_LEN		64
#define LK_INFO_VER		3
#define MAX_MD_NUM		4

struct ccci_tag_s {
	char tag_name[TAG_NAME_LEN];
	u32 data_offset;
	u32 data_size;
	u32 next_tag_offset;
};

/* ccci_util_lib_fo.c struct _ccci_lk_info_v2 */
struct ccci_lk_info_s {
	u64 base_addr;
	u32 size;
	s32 lk_info_err_no;
	s32 version;
	s32 tag_num;
	u32 ld_flag;
	s32 ld_md_errno[MAX_MD_NUM];
};

/* smem user IDs, ccci_ld_md_smem_uid.h (kernel enum is identical) */
enum {
	SMEM_USER_RAW_DBM = 0, SMEM_USER_CCB_START = 1,
	SMEM_USER_RAW_CCB_CTRL = 4, SMEM_USER_RAW_NETD = 7, SMEM_USER_RAW_USB = 8,
	SMEM_USER_RAW_AUDIO = 9, SMEM_USER_RAW_DFD = 10, SMEM_USER_RAW_MDCCCI_DBG = 12,
	SMEM_USER_RAW_MDSS_DBG = 13, SMEM_USER_RAW_RUNTIME_DATA = 14,
	SMEM_USER_RAW_FORCE_ASSERT = 15, SMEM_USER_CCISM_SCP = 16,
	SMEM_USER_RAW_RESERVED = 18, SMEM_USER_CCISM_MCU = 19, SMEM_USER_CCISM_MCU_EXP = 20,
	SMEM_USER_RAW_MD_CONSYS = 22, SMEM_USER_RAW_PHY_CAP = 23, SMEM_USER_RAW_USIP = 24,
	SMEM_USER_RAW_UDC_DATA = 27, SMEM_USER_RAW_UDC_DESCTAB = 28,
	SMEM_USER_MD_WIFI_PROXY = 31, SMEM_USER_MD_NVRAM_CACHE = 32,
	SMEM_USER_MD_CDMR = 39, SMEM_USER_RESERVED = 40, SMEM_USER_MD_DRDI = 41,
	SMEM_USER_MD_DATA = 42,
};

#define SMEM_ATTR_MD_NC		BIT(0)
#define SMEM_ATTR_MD_C		BIT(1)
#define SMEM_ATTR_PADDING	BIT(2)
#define SMEM_ATTR_NO_MAP	BIT(3)
#define SMEM_ATTR_DEDICATED_MPU	BIT(6)

/* mt6789 ccci_lk_plat.h */
#define CCCI_SMEM_SIZE_DFD	SZ_8M
#define CCB_GEAR1_SIZE		(22 * SZ_1M)
#define SMEM_MD_CONSYS_SIZE	(43 * SZ_1M)
#define SMEM_MD_NVRAM_CACHE_SIZE (18 * SZ_1M)
#define SMEM_MD_USIP_SIZE	(384 * SZ_1K)
#define MAX_SMEM_SIZE		0x10000000
#define CACHABLE_SMEM_MAX_SIZE	SZ_128M
#define NC_SMEM_ALIGN		0x10000
#define C_SMEM_ALIGN		0x10000
#define SMEM_NC_OFFSET		0
#define SMEM_NC_MAX		(SZ_32M * 5)
#define SMEM_C_OFFSET		(SZ_32M * 4)
#define SMEM_C_MAX		(SZ_32M * 4)
#define SMEM_LIMIT		0x90000000ULL
#define AMMS_V3			3

struct smem_ref {
	u32 id, ap_offset, size, align, flags, md_offset;
};

struct rt_smem {
	u64 ap_phy;
	u64 ap_vir;
	s32 id;
	u32 ap_offset, size, align, flags, md_offset;
};

struct tag_buf {
	void __iomem *base;
	u32 size;
	u32 num;
};

static int tag_put(struct tag_buf *t, const char *name, const void *data, u32 size)
{
	struct ccci_tag_s tag = { };
	u32 total;

	if (!size)
		return 0;
	total = ALIGN(t->size + size + sizeof(tag), 8);
	if (total >= TAG_MAX_SIZE)
		return -ENOSPC;
	strscpy(tag.tag_name, name, sizeof(tag.tag_name));
	tag.data_offset = t->size + sizeof(tag);
	tag.data_size = size;
	tag.next_tag_offset = total;
	memcpy_toio(t->base + t->size, &tag, sizeof(tag));
	memcpy_toio(t->base + tag.data_offset, data, size);
	t->size = total;
	t->num++;
	return 0;
}

static int tag_u32(struct tag_buf *t, const char *name, u32 v)
{
	return tag_put(t, name, &v, sizeof(v));
}

static int calc(struct smem_ref *ref, int n, u32 block_align, u32 *total)
{
	u32 off = 0, a;
	int i, pads = 0;

	for (i = 0; i < n; i++) {
		a = ref[i].align ? ALIGN(off, ref[i].align) : off;
		if (a != off) {
			pads++;
			off = a;
		}
		ref[i].ap_offset = off;
		ref[i].md_offset = off;
		off += ref[i].size;
	}
	*total = ALIGN(off, block_align);
	return n + pads;
}

static struct rt_smem *rt_tbl(struct smem_ref *ref, int num, u64 base, u32 bank_off)
{
	struct rt_smem *rt = kcalloc(num, sizeof(*rt), GFP_KERNEL);
	u32 off = 0;
	int i = 0, j;

	if (!rt)
		return NULL;
	for (j = 0; j < num; j++) {
		rt[j].id = ref[i].id;
		rt[j].ap_phy = base + off;
		rt[j].ap_offset = off;
		rt[j].md_offset = off + bank_off;
		if (off != ref[i].ap_offset) {
			rt[j].flags = SMEM_ATTR_PADDING;
			rt[j].size = ref[i].ap_offset - off;
		} else {
			rt[j].flags = ref[i].flags;
			rt[j].size = ref[i].size;
			i++;
		}
		off += rt[j].size;
	}
	return rt;
}

struct q25_v6 {
	u32 img_type, mem_size, img_size;
	u32 amms_pos, consys, udc, nv_cache, drdi_ver;
};

static void v6_fields(const u8 *h, struct q25_v6 *v)
{
	v->img_type = get_unaligned_le32(h + 20);
	v->mem_size = get_unaligned_le32(h + 172);
	v->img_size = get_unaligned_le32(h + 176);
	v->amms_pos = get_unaligned_le32(h + 380);
	v->consys = get_unaligned_le32(h + 384);
	v->udc = get_unaligned_le32(h + 388);
	v->nv_cache = get_unaligned_le32(h + 396);
	v->drdi_ver = get_unaligned_le32(h + 400);
}

static int header_tags(struct tag_buf *t, const u8 *h, const struct q25_v6 *v)
{
	static const struct { const char *name; u32 off, len; } str[] = {
		{ "md_platform", 24, 16 }, { "md_build_time", 40, 64 }, { "md_build_ver", 104, 64 },
	};
	unsigned int i;
	int ret;

	ret = tag_u32(t, "udc_en", v->udc);
	ret = ret ?: tag_u32(t, "consys_size", v->consys);
	ret = ret ?: tag_u32(t, "nv_cache_shm_size", v->nv_cache);
	ret = ret ?: tag_u32(t, "drdi_version", v->drdi_ver);
	for (i = 0; !ret && i < ARRAY_SIZE(str); i++)
		ret = tag_put(t, str[i].name, h + str[i].off, str[i].len);
	ret = ret ?: tag_u32(t, "md_capability", v->img_type);
	ret = ret ?: tag_put(t, "md1_chk", h, Q25_CHK_V6_SIZE);
	return ret ?: tag_u32(t, "md1img", v->img_size);
}

/* nc_smem_legacy_compatible() with CCCI_NO_NEED_CHANGE_MDSS */
static int nc_tags(struct tag_buf *t, struct rt_smem *rt, int num, u32 total)
{
	struct { u32 ap_offset, md_offset, size, id; } ext[] = {
		{ 0, 0, 0, SMEM_USER_RAW_DFD }, { 0, 0, 0, SMEM_USER_RAW_UDC_DATA },
		{ 0, 0, 0, SMEM_USER_MD_WIFI_PROXY }, { 0, 0, 0, SMEM_USER_MD_DATA },
	};
	struct {
		u64 base_addr;
		u32 ap_md1_off, ap_md1_size, ap_md3_off, ap_md3_size, md1_md3_off, md1_md3_size;
		u32 total;
	} smem = { .ap_md1_size = total, .total = total };
	unsigned int i, k;
	u32 n = ARRAY_SIZE(ext);
	int ret;

	smem.base_addr = rt[0].ap_phy;
	for (i = 0; i < num; i++) {
		for (k = 0; k < ARRAY_SIZE(ext); k++) {
			if (rt[i].id != ext[k].id)
				continue;
			ext[k].ap_offset = rt[i].ap_offset;
			ext[k].md_offset = rt[i].md_offset;
			ext[k].size = rt[i].size;
		}
		if (rt[i].id == SMEM_USER_RAW_PHY_CAP && rt[i].size > SZ_2M)
			smem.ap_md1_size = total - (rt[i].size - SZ_2M);
	}
	ret = tag_put(t, "nc_smem_info_ext", ext, sizeof(ext));
	ret = ret ?: tag_put(t, "nc_smem_info_ext_num", &n, sizeof(n));
	return ret ?: tag_put(t, "smem_layout", &smem, sizeof(smem));
}

/* c_smem_legacy_compatible() + add_c_smem_to_tag_inf() */
static int c_tags(struct tag_buf *t, struct rt_smem *rt, int num, u32 offset, u32 total)
{
	struct cs { u64 addr; u32 md_offset, size, id; } lay[] = {
		{ 0, 0, SMEM_MD_CONSYS_SIZE, SMEM_USER_RAW_MD_CONSYS },
		{ 0, 0, SMEM_MD_NVRAM_CACHE_SIZE, SMEM_USER_MD_NVRAM_CACHE },
		{ 0, 0, 22 * SZ_1M, SMEM_USER_CCB_START },
		{ 0, 0, 0, SMEM_USER_RAW_UDC_DESCTAB },
		{ 0, 0, SMEM_MD_USIP_SIZE, SMEM_USER_RAW_USIP },
		{ 0, 0, 0, SMEM_USER_MD_CDMR },
	};
	struct cs info;
	struct { u64 addr; u32 size; } ccb = { };
	u32 cache_off = MAX_SMEM_SIZE - CACHABLE_SMEM_MAX_SIZE;
	unsigned int i, k;
	int ret;

	for (i = 0; i < num; i++) {
		for (k = 0; k < ARRAY_SIZE(lay); k++) {
			if (rt[i].id != lay[k].id)
				continue;
			lay[k].addr = rt[i].ap_phy;
			lay[k].md_offset = rt[i].md_offset - offset;
			lay[k].size = rt[i].size;
		}
		if (rt[i].id == SMEM_USER_CCB_START) {
			ccb.addr = rt[i].ap_phy;
			ccb.size = rt[i].size;
		}
	}
	info = (struct cs){ rt[0].ap_phy, offset, total, ARRAY_SIZE(lay) };
	ret = tag_put(t, "md1_bank4_cache_info", &info, sizeof(info));
	ret = ret ?: tag_put(t, "md1_bank4_cache_layout", lay, sizeof(lay));
	ret = ret ?: tag_u32(t, "md1_smem_cahce_offset", cache_off);
	ret = ret ?: tag_put(t, "ccb_info", &ccb, sizeof(ccb));
	return ret ?: tag_u32(t, "ccb_gear_id", 1);
}

static int tag_rt(struct tag_buf *t, const char *name, const char *num_name,
		  struct rt_smem *rt, int num)
{
	struct { u32 id, ap_offset, size, align, flags, md_offset; } e;
	u8 *buf;
	size_t sz = num * (16 + sizeof(e));
	int i, ret;

	/* LK copies struct rt_smem_region verbatim: u64 ap_phy, u64 ap_vir, smem_region */
	buf = kzalloc(sz, GFP_KERNEL);
	if (!buf)
		return -ENOMEM;
	for (i = 0; i < num; i++) {
		u8 *p = buf + i * (16 + sizeof(e));

		e = (typeof(e)){ rt[i].id, rt[i].ap_offset, rt[i].size, rt[i].align,
				 rt[i].flags, rt[i].md_offset };
		put_unaligned_le64(rt[i].ap_phy, p);
		memcpy(p + 16, &e, sizeof(e));
	}
	ret = tag_put(t, name, buf, sz);
	kfree(buf);
	return ret ?: tag_u32(t, num_name, num);
}

int q25_md1_build_lkinfo(struct q25_md1_lkinfo_in *in, struct q25_md1_layout *out)
{
	struct smem_ref nc[] = {
		{ SMEM_USER_RAW_DFD, 0, CCCI_SMEM_SIZE_DFD, 0x800000,
		  SMEM_ATTR_MD_NC | SMEM_ATTR_NO_MAP },
		{ SMEM_USER_RAW_MDCCCI_DBG, 0, 2 * SZ_1K, 0, SMEM_ATTR_MD_NC },
		{ SMEM_USER_RAW_MDSS_DBG, 0, 10 * SZ_1K, 0, SMEM_ATTR_MD_NC },
		{ SMEM_USER_RAW_RESERVED, 0, 46 * SZ_1K, 0, SMEM_ATTR_MD_NC },
		{ SMEM_USER_RAW_RUNTIME_DATA, 0, 4 * SZ_1K, 0, SMEM_ATTR_MD_NC },
		{ SMEM_USER_RAW_FORCE_ASSERT, 0, SZ_1K, 0, SMEM_ATTR_MD_NC },
		{ SMEM_USER_RAW_RESERVED, 0, 848, 0, SMEM_ATTR_MD_NC },
		{ SMEM_USER_RAW_DBM, 0, 176, 0, SMEM_ATTR_MD_NC },
		{ SMEM_USER_CCISM_SCP, 0, 32 * SZ_1K, 0, SMEM_ATTR_MD_NC },
		{ SMEM_USER_RAW_CCB_CTRL, 0, 4 * SZ_1K, 0, SMEM_ATTR_MD_NC },
		{ SMEM_USER_RAW_NETD, 0, 4 * SZ_1K, 0, SMEM_ATTR_MD_NC },
		{ SMEM_USER_RAW_USB, 0, 4 * SZ_1K, 0, SMEM_ATTR_MD_NC },
		{ SMEM_USER_RAW_AUDIO, 0, 52 * SZ_1K, 0, SMEM_ATTR_MD_NC },
		{ SMEM_USER_CCISM_MCU, 0, 721 * SZ_1K, 0, SMEM_ATTR_MD_NC },
		{ SMEM_USER_CCISM_MCU_EXP, 0, 121 * SZ_1K, 0, SMEM_ATTR_MD_NC },
		{ SMEM_USER_RESERVED, 0, 22 * SZ_1K, 0, SMEM_ATTR_MD_NC },
		{ SMEM_USER_MD_DRDI, 0, 0, 0, SMEM_ATTR_MD_NC },
		{ SMEM_USER_MD_DATA, 0, 5 * SZ_1M, 8, SMEM_ATTR_MD_NC },
		{ SMEM_USER_RAW_PHY_CAP, 0, 0, 16, SMEM_ATTR_NO_MAP | SMEM_ATTR_MD_NC },
	};
	struct smem_ref c[] = {
		{ SMEM_USER_CCB_START, 0, CCB_GEAR1_SIZE, SZ_1M, SMEM_ATTR_MD_C },
		{ SMEM_USER_RAW_MD_CONSYS, 0, 0, 0x10000,
		  SMEM_ATTR_NO_MAP | SMEM_ATTR_DEDICATED_MPU | SMEM_ATTR_MD_C },
		{ SMEM_USER_RAW_USIP, 0, SMEM_MD_USIP_SIZE, 128, SMEM_ATTR_MD_C },
	};
	struct ccci_lk_info_s inf = { .version = LK_INFO_VER, .ld_flag = 1 };
	struct {
		u64 base; u32 resv; s8 md_id, err, md_type, ver; s32 load_size, ro_rw;
	} hdr_tbl = { };
	struct tag_buf t = { .base = in->tag_va };
	struct rt_smem *nrt = NULL, *crt = NULL;
	struct q25_v6 v;
	struct property *prop;
	u32 ntot, ctot, one = 1;
	int nn, cn, ret;

	v6_fields(in->chk_hdr, &v);
	nc[16].size = v.drdi_ver == AMMS_V3 ? SZ_64K : 0;
	c[1].size = v.consys;
	if (v.udc)
		return -EOPNOTSUPP;	/* UDC regions not modelled for MT6789 */

	nn = calc(nc, ARRAY_SIZE(nc), NC_SMEM_ALIGN, &ntot);
	cn = calc(c, ARRAY_SIZE(c), C_SMEM_ALIGN, &ctot);
	if (ntot > in->nc_size || ntot > SMEM_NC_MAX || ctot > in->c_size || ctot > SMEM_C_MAX ||
	    in->nc_base + ntot > SMEM_LIMIT || in->c_base + ctot > SMEM_LIMIT)
		return -ENOSPC;
	out->nc_total = ntot;
	out->c_total = ctot;

	nrt = rt_tbl(nc, nn, in->nc_base, SMEM_NC_OFFSET);
	crt = rt_tbl(c, cn, in->c_base, SMEM_C_OFFSET);
	if (!nrt || !crt) {
		ret = -ENOMEM;
		goto out;
	}

	memset_io(t.base, 0, TAG_MAX_SIZE);
	ret = header_tags(&t, in->chk_hdr, &v);
	ret = ret ?: tag_rt(&t, "nc_smem_layout", "nc_smem_layout_num", nrt, nn);
	ret = ret ?: nc_tags(&t, nrt, nn, ntot);
	ret = ret ?: tag_rt(&t, "c_smem_layout", "c_smem_layout_num", crt, cn);
	ret = ret ?: c_tags(&t, crt, cn, SMEM_C_OFFSET, ctot);
	hdr_tbl.base = in->img_base;
	hdr_tbl.resv = v.mem_size;
	hdr_tbl.md_type = v.img_type;
	hdr_tbl.load_size = v.img_size;
	hdr_tbl.ro_rw = v.mem_size;
	ret = ret ?: tag_put(&t, "md_bank0_base", &in->img_base, sizeof(in->img_base));
	ret = ret ?: tag_put(&t, "hdr_count", &one, sizeof(one));
	ret = ret ?: tag_put(&t, "hdr_tbl_inf", &hdr_tbl, sizeof(hdr_tbl));
	if (ret)
		goto out;
	wmb(); /* blob complete before the pointer is published */

	inf.base_addr = in->tag_phys;
	inf.size = t.size;
	inf.tag_num = t.num;
	out->tag_bytes = t.size;
	out->tag_num = t.num;

	prop = kzalloc(sizeof(*prop) + sizeof(inf), GFP_KERNEL);
	if (!prop) {
		ret = -ENOMEM;
		goto out;
	}
	prop->name = "ccci,modem_info_v2";
	prop->length = sizeof(inf);
	prop->value = prop + 1;
	memcpy(prop->value, &inf, sizeof(inf));
	ret = of_add_property(in->mddriver, prop);
	if (ret)
		kfree(prop);
out:
	kfree(nrt);
	kfree(crt);
	return ret;
}
