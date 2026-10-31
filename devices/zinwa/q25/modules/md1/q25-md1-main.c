// SPDX-License-Identifier: GPL-2.0-only
/*
 * Zinwa Q25 (MT6789) MD1 native boot owner, staged and operator-driven.
 *
 * Replaces the MD1 work the stock LK app stage did (U-Boot now occupies that
 * stage): image placement, bank remap, MD1 MTCMOS, boot trigger, then waits
 * for the modem's first CCIF SRAM handshake (HS1).
 *
 * Sequence sources:
 *   Gigaset-dev/lk2 ab107ff351cb (MIT): platform/mediatek/common/md,
 *     platform/mediatek/mt6789/{md,mtcmos}
 *   LineageOS android_kernel_xelex_mt6789 2a873a3511ee (GPL-2.0):
 *     eccci/hif/ccci_hif_ccif.c, eccci/platform/md_sys1_platform.c
 *   Installed ATF v2.4 8605b7e34f7: SiP dispatch decoded statically.
 *
 * Nothing touches hardware at probe. Each step is an explicit write to the
 * "command" sysfs attribute. CONFIG_MODULE_UNLOAD=n: the only full reset is
 * a reboot.
 */
#include <linux/arm-smccc.h>
#include <linux/clk.h>
#include <linux/delay.h>
#include <linux/firmware.h>
#include <linux/io.h>
#include <linux/iopoll.h>
#include <linux/mm.h>
#include <linux/mfd/syscon.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/of_address.h>
#include <linux/of_reserved_mem.h>
#include <linux/platform_device.h>
#include <linux/pm_domain.h>
#include <linux/regmap.h>
#include <linux/sizes.h>
#include <linux/slab.h>
#include <linux/string.h>
#include <linux/unaligned.h>

#include "q25-md1-owner.h"

/* ATF SiP IDs (AArch64 variants) as listed in the installed BL31 descriptor table. */
#define SIP_LK_CCCI		0xc200040bUL
#define SIP_KERNEL_CCCI		0xc2000505UL
#define SIP_BL_EMIMPU		0xc2000415UL
#define EMIMPU_SET		0
#define EMIMPU_READ		2
#define EMIMPU_READ_SA		0
#define EMIMPU_READ_EA		1
#define EMIMPU_READ_APC		2
#define MPU_FORBIDDEN		5
#define MPU_DOMAIN_MD1		1
#define MPU_DOMAIN_MDHW		7
#define MPU_ALIGN		SZ_64K

/* LK2 ccci_ld_md_sec.h */
#define MD_BANK0_HW_REMAP	1
#define MD_BANK1_HW_REMAP	2
#define MD_BANK4_HW_REMAP	3
#define MD_POWER_CONFIG		6
#define MD_LK_BOOT_UP		1
#define MD_LK_GET_BOOT_UP_STATUS 7
#define CCCI_SECURE_RET_LK	0xfffffffffffffff1UL

/* SPM, offsets from LK2 mt6789 mtcmos.c / ccci_lk_md_power_ctrl.c */
#define SPM_POWERON_CONFIG_EN	0x000
#define SPM_POWER_ON_VAL1	0x008
#define SPM_PWR_STATUS		0x16c
#define SPM_PWR_STATUS_2ND	0x170
#define SPM_MD1_PWR_CON		0x300
#define SPM_MD_EXT_BUCK_ISO	0x398
#define SPM_PROJECT_KEY		0x0b160001
#define SPM_SRCLKEN_O1		BIT(21)
#define PWR_RST_B		BIT(0)
#define PWR_ON			BIT(2)
#define MD1_PWR_STA		BIT(0)

/* infracfg_ao */
#define INFRA_CCIF_RST_SET	0x150
#define INFRA_CCIF_RST_CLR	0x154
#define INFRA_CCIF0_RST		BIT(8)
#define INFRA_PROT_SET		0x2a0
#define INFRA_PROT_CLR		0x2a4
#define INFRA_PROT_STA1		0x228
#define INFRA_VDNR_SET		0xb84
#define INFRA_VDNR_CLR		0xb88
#define INFRA_VDNR_STA1		0xb90
#define MD1_PROT_STEP0		BIT(7)
#define MD1_PROT_STEP1		(BIT(0) | BIT(10) | BIT(15))

/* CCIF, stock ccif_hif_reg.h */
#define CCIF_BUSY		0x04
#define CCIF_RCHNUM		0x10
#define CCIF_ACK		0x14
#define CCIF_CHDATA		0x100
#define CCIF_SRAM_SIZE		512
#define CCIF_D2H_SRAM		15

/* HS1, stock mtk_ccci_common.h / ccci_modem.h */
#define MD_INIT_CHK_ID		0x5555ffff
#define MD_FEATURE_PATTERN	0x49434343
#define MD_FEATURE_COUNT	64

/* MKIMG and CHECK_HEADER, stock ccci_util_lib_main.h */
#define MKIMG_MAGIC		0x58881688
#define MKIMG_EXT_MAGIC		0x58891689
#define MKIMG_HDR		512
#define MKIMG_MAX_RECORDS	64
#define CHK_V6_SIZE		512
#define CHK_V3_SIZE		284
#define DSP_DISABLED		0xcdcdcdaa

#define SMEM_SLOT		SZ_32M
#define NC_REMAP_SPAN		SZ_256M
#define C_SLOT_FIRST		4

enum md1_step {
	ST_LOADED	= BIT(0),
	ST_REMAPPED	= BIT(1),
	ST_CCIF		= BIT(2),
	ST_POWERED	= BIT(3),
	ST_BOOTED	= BIT(4),
	ST_BROM_PASS	= BIT(5),
	ST_HS1		= BIT(6),
	ST_MPU		= BIT(7),
	ST_HANDOFF	= BIT(8),
};

struct md1_owner {
	struct device *dev;
	struct mutex lock; /* serialises commands */
	struct regmap *spm;
	struct regmap *infra;
	void __iomem *ccif_ap;
	void __iomem *ccif_md;
	struct clk_bulk_data clks[2];
	bool clks_on;
	struct resource img, nc, c, tag;
	struct device_node *mddriver;
	struct generic_pm_domain pd;
	bool pd_registered;
	u8 chk[Q25_CHK_V6_SIZE];
	const char *fw_name;
	u32 state;
	u32 mem_size;
	u32 dsp_off;
	u32 dsp_size;
	u32 hs1_ms;
};

static void sip(unsigned long fid, unsigned long a1, unsigned long a2,
		unsigned long a3, unsigned long a4, struct arm_smccc_res *res)
{
	arm_smccc_smc(fid, a1, a2, a3, a4, 0, 0, 0, res);
}

static int spm_rd(struct md1_owner *md, u32 off, u32 *v)
{
	return regmap_read(md->spm, off, v);
}

static void cmd_report(struct md1_owner *md)
{
	u32 st = 0, st2 = 0, con = 0, iso = 0, p = 0, vd = 0, val1 = 0;

	spm_rd(md, SPM_PWR_STATUS, &st);
	spm_rd(md, SPM_PWR_STATUS_2ND, &st2);
	spm_rd(md, SPM_MD1_PWR_CON, &con);
	spm_rd(md, SPM_MD_EXT_BUCK_ISO, &iso);
	spm_rd(md, SPM_POWER_ON_VAL1, &val1);
	regmap_read(md->infra, INFRA_PROT_STA1, &p);
	regmap_read(md->infra, INFRA_VDNR_STA1, &vd);
	dev_info(md->dev,
		 "report: pwr_status=%#x/%#x md1=%s md1_pwr_con=%#x ext_buck_iso=%#x srclken_o1=%d prot_sta1=%#x vdnr_sta1=%#x state=%#x\n",
		 st, st2, (st & MD1_PWR_STA) ? "on" : "off", con, iso,
		 !!(val1 & SPM_SRCLKEN_O1), p, vd, md->state);
}

/*
 * No-MMIO dispatch probe. Invalid sub-commands return before any register
 * access in both CCCI handlers; only the return code shows which SiP table
 * (BL33 or kernel) ATF routed the call to.
 */
static void cmd_smc_probe(struct md1_owner *md)
{
	struct arm_smccc_res lk, kern;

	sip(SIP_LK_CCCI, 0, 0, 0, 0, &lk);
	sip(SIP_KERNEL_CCCI, 99, 0, 0, 0, &kern);
	dev_info(md->dev, "smc-probe: lk_ccci=%#lx (%s) kernel_ccci=%#lx (%s)\n",
		 lk.a0, lk.a0 == CCCI_SECURE_RET_LK ? "BL33 table reachable" : "not reachable",
		 kern.a0,
		 kern.a0 == CCCI_SECURE_RET_LK ? "kernel table reachable" : "not reachable");
}

static int fw_read(struct md1_owner *md, void *buf, size_t len, size_t off)
{
	const struct firmware *fw;
	int ret;

	ret = request_partial_firmware_into_buf(&fw, md->fw_name, md->dev, buf, len, off);
	if (ret)
		return ret;
	ret = fw->size == len ? 0 : -EIO;
	release_firmware(fw);
	return ret;
}

struct mkimg_rec {
	u64 data_off;
	u64 size;
};

static int mkimg_find(struct md1_owner *md, const char *name, struct mkimg_rec *out)
{
	u8 *h;
	u64 off = 0;
	int i, ret = -ENOENT;

	h = kmalloc(MKIMG_HDR, GFP_KERNEL);
	if (!h)
		return -ENOMEM;
	for (i = 0; i < MKIMG_MAX_RECORDS; i++) {
		u32 hsz, align, end;
		u64 size;
		char rec[33];

		ret = fw_read(md, h, MKIMG_HDR, off);
		if (ret)
			break;
		hsz = get_unaligned_le32(h + 52);
		align = get_unaligned_le32(h + 68);
		end = get_unaligned_le32(h + 64);
		if (get_unaligned_le32(h) != MKIMG_MAGIC ||
		    get_unaligned_le32(h + 48) != MKIMG_EXT_MAGIC ||
		    hsz != MKIMG_HDR || !align || align > SZ_4K || !is_power_of_2(align)) {
			ret = -EBADMSG;
			break;
		}
		size = get_unaligned_le32(h + 4) | (u64)get_unaligned_le32(h + 72) << 32;
		memcpy(rec, h + 8, 32);
		rec[32] = 0;
		if (!strcmp(rec, name)) {
			out->data_off = off + hsz;
			out->size = size;
			ret = 0;
			break;
		}
		ret = -ENOENT;
		if (end == 1)
			break;
		off = round_up(off + hsz + size, align);
	}
	kfree(h);
	return ret;
}

static int check_footer(struct md1_owner *md, const struct mkimg_rec *r, u32 want,
			u8 *buf)
{
	int ret;

	if (r->size < want)
		return -EBADMSG;
	ret = fw_read(md, buf, want, r->data_off + r->size - want);
	if (ret)
		return ret;
	if (memcmp(buf, "CHECK_HEADER", 12) || get_unaligned_le32(buf + want - 4) != want)
		return -EBADMSG;
	return 0;
}

static int cmd_load(struct md1_owner *md)
{
	struct mkimg_rec rom, dsp;
	u32 img_size, region_num;
	u8 *hdr;
	void *va;
	int ret;

	if (md->state & (ST_POWERED | ST_BOOTED))
		return -EBUSY;
	hdr = kmalloc(CHK_V6_SIZE, GFP_KERNEL);
	if (!hdr)
		return -ENOMEM;
	ret = mkimg_find(md, "md1rom", &rom);
	if (ret)
		goto out;
	ret = check_footer(md, &rom, CHK_V6_SIZE, hdr);
	if (ret)
		goto out;
	memcpy(md->chk, hdr, Q25_CHK_V6_SIZE);
	md->mem_size = get_unaligned_le32(hdr + 172);
	img_size = get_unaligned_le32(hdr + 176);
	md->dsp_off = get_unaligned_le32(hdr + 184);
	md->dsp_size = get_unaligned_le32(hdr + 188);
	region_num = get_unaligned_le32(hdr + 192);
	if (get_unaligned_le32(hdr + 12) != 6 || hdr[168] != 1 ||
	    !region_num || region_num > 8 || !img_size ||
	    md->mem_size > resource_size(&md->img) || rom.size > md->mem_size) {
		ret = -EBADMSG;
		goto out;
	}
	if (md->dsp_off == DSP_DISABLED)
		md->dsp_size = 0;
	if (md->dsp_size &&
	    (md->dsp_off < rom.size || md->dsp_off > md->mem_size ||
	     md->dsp_size > md->mem_size - md->dsp_off)) {
		ret = -EBADMSG;
		goto out;
	}

	va = memremap(md->img.start, md->mem_size, MEMREMAP_WC);
	if (!va) {
		ret = -ENOMEM;
		goto out;
	}
	/* LK copies the stored record verbatim, footer included; no transform. */
	ret = fw_read(md, va, rom.size, rom.data_off);
	if (!ret && md->dsp_size) {
		ret = mkimg_find(md, "md1dsp", &dsp);
		if (!ret)
			ret = check_footer(md, &dsp, CHK_V3_SIZE, hdr);
		if (!ret && dsp.size > md->dsp_size)
			ret = -E2BIG;
		if (!ret)
			ret = fw_read(md, va + md->dsp_off, dsp.size, dsp.data_off);
	}
	wmb(); /* image visible to the modem before any later step */
	memunmap(va);
	if (ret)
		goto out;

	/* Stock first boot clears all shared memory before the modem runs. */
	va = memremap(md->nc.start, resource_size(&md->nc), MEMREMAP_WC);
	if (!va) {
		ret = -ENOMEM;
		goto out;
	}
	memset(va, 0, resource_size(&md->nc));
	memunmap(va);
	va = memremap(md->c.start, resource_size(&md->c), MEMREMAP_WC);
	if (!va) {
		ret = -ENOMEM;
		goto out;
	}
	memset(va, 0, resource_size(&md->c));
	memunmap(va);
	wmb(); /* cleared smem visible before remap/boot */

	md->state |= ST_LOADED;
	dev_info(md->dev,
		 "load: md1rom %llu bytes, md1dsp %u bytes at +%#x, mem_size %#x, smem cleared\n",
		 rom.size, md->dsp_size ? (u32)dsp.size : 0, md->dsp_off, md->mem_size);
out:
	kfree(hdr);
	return ret;
}

static int bank4_map(struct md1_owner *md, phys_addr_t base, u32 span, u32 first)
{
	struct arm_smccc_res res;
	u32 slot, j = 0;

	for (slot = first; slot < 8 && (u64)j * SMEM_SLOT < span; slot++, j++) {
		u64 pa = base + (u64)j * SMEM_SLOT;

		sip(SIP_LK_CCCI, MD_BANK4_HW_REMAP, lower_32_bits(pa), upper_32_bits(pa),
		    slot, &res);
		if (res.a0 == CCCI_SECURE_RET_LK)
			return -EIO;
		dev_info(md->dev, "remap: bank4 slot %u -> %#llx (map=%#lx)\n", slot, pa, res.a1);
	}
	return 0;
}

static int cmd_remap(struct md1_owner *md)
{
	struct arm_smccc_res r0, r1;
	phys_addr_t b = md->img.start;

	if (!(md->state & ST_LOADED))
		return -EINVAL;
	if (!IS_ALIGNED(b, SZ_32M) || !IS_ALIGNED(md->nc.start, SZ_32M) ||
	    !IS_ALIGNED(md->c.start, SZ_32M))
		return -EINVAL;
	sip(SIP_LK_CCCI, MD_BANK0_HW_REMAP, lower_32_bits(b), upper_32_bits(b), 0, &r0);
	if (r0.a0 == CCCI_SECURE_RET_LK)
		return -EIO;
	sip(SIP_LK_CCCI, MD_BANK1_HW_REMAP, lower_32_bits(b), upper_32_bits(b), 0, &r1);
	if (r1.a0 == CCCI_SECURE_RET_LK)
		return -EIO;
	dev_info(md->dev, "remap: bank0 %#lx/%#lx/%#lx bank1 %#lx/%#lx/%#lx/%#lx\n",
		 r0.a1, r0.a2, r0.a3, r1.a0, r1.a1, r1.a2, r1.a3);
	/* LK smem_noncacheable_init then smem_cacheable_init. */
	if (bank4_map(md, md->nc.start, NC_REMAP_SPAN, 0) ||
	    bank4_map(md, md->c.start, (8 - C_SLOT_FIRST) * SMEM_SLOT, C_SLOT_FIRST))
		return -EIO;
	md->state |= ST_REMAPPED;
	return 0;
}

static int cmd_ccif_prep(struct md1_owner *md)
{
	unsigned int i;
	int ret;

	if (md->state & ST_POWERED)
		return -EBUSY;
	if (!md->ccif_ap)
		return -ENODEV;
	if (!md->clks_on) {
		ret = clk_bulk_prepare_enable(ARRAY_SIZE(md->clks), md->clks);
		if (ret)
			return ret;
		md->clks_on = true;
	}
	regmap_write(md->infra, INFRA_CCIF_RST_SET, INFRA_CCIF0_RST);
	regmap_write(md->infra, INFRA_CCIF_RST_CLR, INFRA_CCIF0_RST);
	for (i = 0; i < CCIF_SRAM_SIZE; i += 4) {
		writel(0, md->ccif_ap + CCIF_CHDATA + i);
		writel(0, md->ccif_md + CCIF_CHDATA + i);
	}
	dev_info(md->dev, "ccif-prep: busy=%#x rchnum=%#x after reset\n",
		 readl(md->ccif_ap + CCIF_BUSY), readl(md->ccif_ap + CCIF_RCHNUM));
	md->state |= ST_CCIF;
	return 0;
}

static int mtcmos_on(struct md1_owner *md)
{
	u32 v, o1 = 0;
	int ret;

	regmap_write(md->spm, SPM_POWERON_CONFIG_EN, SPM_PROJECT_KEY);
	regmap_read(md->spm, SPM_POWER_ON_VAL1, &o1);
	if (!(o1 & SPM_SRCLKEN_O1)) {
		regmap_set_bits(md->spm, SPM_POWER_ON_VAL1, SPM_SRCLKEN_O1);
		/* stock LK requests O1 long before MTCMOS; allow the 26 MHz source to settle */
		usleep_range(3000, 4000);
	}
	regmap_clear_bits(md->spm, SPM_MD_EXT_BUCK_ISO, 0x3);
	regmap_set_bits(md->spm, SPM_MD1_PWR_CON, PWR_RST_B);
	regmap_set_bits(md->spm, SPM_MD1_PWR_CON, PWR_ON);
	ret = regmap_read_poll_timeout(md->spm, SPM_PWR_STATUS, v, v & MD1_PWR_STA,
				       10, 100000);
	if (ret) {
		dev_err(md->dev, "power-on: MD1 status timeout; bus protection left set\n");
		return ret;
	}
	regmap_write(md->infra, INFRA_VDNR_CLR, MD1_PROT_STEP1);
	regmap_write(md->infra, INFRA_PROT_CLR, MD1_PROT_STEP0);
	return 0;
}

/* LK2 spm_mtcmos_ctrl_md1_disable(); optionally drop the O1 clock request. */
static int mtcmos_off(struct md1_owner *md, bool drop_o1)
{
	u32 v;
	int ret;

	regmap_write(md->infra, INFRA_PROT_SET, MD1_PROT_STEP0);
	ret = regmap_read_poll_timeout(md->infra, INFRA_PROT_STA1, v,
				       (v & MD1_PROT_STEP0) == MD1_PROT_STEP0, 10, 100000);
	if (ret)
		return ret;
	regmap_write(md->infra, INFRA_VDNR_SET, MD1_PROT_STEP1);
	ret = regmap_read_poll_timeout(md->infra, INFRA_VDNR_STA1, v,
				       (v & MD1_PROT_STEP1) == MD1_PROT_STEP1, 10, 100000);
	if (ret)
		return ret;
	regmap_clear_bits(md->spm, SPM_MD1_PWR_CON, PWR_ON);
	ret = regmap_read_poll_timeout(md->spm, SPM_PWR_STATUS, v, !(v & MD1_PWR_STA),
				       10, 100000);
	if (ret)
		return ret;
	regmap_set_bits(md->spm, SPM_MD_EXT_BUCK_ISO, 0x3);
	regmap_clear_bits(md->spm, SPM_MD1_PWR_CON, PWR_RST_B);
	if (drop_o1) {
		regmap_write(md->spm, SPM_POWERON_CONFIG_EN, SPM_PROJECT_KEY);
		regmap_clear_bits(md->spm, SPM_POWER_ON_VAL1, SPM_SRCLKEN_O1);
	}
	return 0;
}

static bool md1_is_on(struct md1_owner *md)
{
	u32 st = 0;

	spm_rd(md, SPM_PWR_STATUS, &st);
	return st & MD1_PWR_STA;
}

static int cmd_power_on(struct md1_owner *md)
{
	int ret;

	if (!(md->state & ST_REMAPPED) || (md->state & ST_POWERED))
		return -EINVAL;
	ret = mtcmos_on(md);
	if (ret)
		return ret;
	md->state |= ST_POWERED;
	cmd_report(md);
	return 0;
}

static int md1_power_off(struct md1_owner *md, bool drop_o1)
{
	int ret = mtcmos_off(md, drop_o1);

	if (ret) {
		dev_err(md->dev, "power-off: bounded wait expired (%d); state unchanged\n", ret);
		cmd_report(md);
		return ret;
	}
	md->state &= ~(ST_POWERED | ST_BOOTED | ST_HS1 | ST_CCIF);
	cmd_report(md);
	return 0;
}

static int cmd_power_off(struct md1_owner *md)
{
	return md1_power_off(md, true);
}

static void boot_status(struct md1_owner *md, struct arm_smccc_res *res)
{
	sip(SIP_LK_CCCI, MD_POWER_CONFIG, MD_LK_GET_BOOT_UP_STATUS, 0, 0, res);
}

/* Writes only the 0x1020E700 debug mux select inside ATF; no state gate. */
static void cmd_boot_status(struct md1_owner *md)
{
	struct arm_smccc_res res;

	boot_status(md, &res);
	dev_info(md->dev, "boot-status: ret=%#lx status=%#lx brom_flags=%#lx/%#lx\n",
		 res.a0, res.a1, res.a2, res.a3);
}

static int cmd_boot(struct md1_owner *md)
{
	struct arm_smccc_res res;

	if (!(md->state & ST_POWERED) || (md->state & ST_BOOTED))
		return -EINVAL;
	sip(SIP_LK_CCCI, MD_POWER_CONFIG, MD_LK_BOOT_UP, 0, 0, &res);
	dev_info(md->dev, "boot: ret=%#lx boot_slave=%#lx\n", res.a0, res.a3);
	if (res.a0)
		return -EIO;
	md->state |= ST_BOOTED;
	return 0;
}

static int cmd_poll_brom(struct md1_owner *md)
{
	struct arm_smccc_res res;
	unsigned int i;

	if (!(md->state & ST_BOOTED))
		return -EINVAL;
	for (i = 0; i < 50; i++) {
		boot_status(md, &res);
		/* a1: status regs, a2/a3: four BROM check flags (all 1 = pass). */
		if (res.a2 == 0x100000001UL && res.a3 == 0x100000001UL) {
			md->state |= ST_BROM_PASS;
			dev_info(md->dev, "poll-brom: pass after %u ms status=%#lx\n",
				 i * 100, res.a1);
			return 0;
		}
		msleep(100);
	}
	dev_err(md->dev, "poll-brom: no pass in 5 s ret=%#lx status=%#lx flags=%#lx/%#lx\n",
		res.a0, res.a1, res.a2, res.a3);
	return -ETIMEDOUT;
}

static int cmd_hs1_wait(struct md1_owner *md)
{
	void __iomem *sram = md->ccif_ap + CCIF_CHDATA;
	u32 rch, d0, d1, ch, rsv, head, tail;
	int ret;

	if (!(md->state & ST_CCIF) || !(md->state & ST_BOOTED))
		return -EINVAL;
	ret = readl_poll_timeout(md->ccif_ap + CCIF_RCHNUM, rch, rch & BIT(CCIF_D2H_SRAM),
				 20000, (u64)md->hs1_ms * 1000);
	if (ret) {
		dev_err(md->dev, "hs1-wait: no D2H_SRAM in %u ms rchnum=%#x\n",
			md->hs1_ms, readl(md->ccif_ap + CCIF_RCHNUM));
		return ret;
	}
	d0 = readl(sram + 0);
	d1 = readl(sram + 4);
	ch = readl(sram + 8);
	rsv = readl(sram + 12);
	head = readl(sram + 16);
	tail = readl(sram + 16 + 4 + MD_FEATURE_COUNT);
	writel(BIT(CCIF_D2H_SRAM), md->ccif_ap + CCIF_ACK);
	readl(md->ccif_ap + CCIF_RCHNUM);
	dev_info(md->dev,
		 "hs1-wait: rchnum=%#x hdr=%#x/%#x ch=%u seq=%u rsv=%#x feat=%#x/%#x\n",
		 rch, d0, d1, ch & 0xffff, (ch >> 16) & 0x7fff, rsv, head, tail);
	if (d1 != 0 || (ch & 0xffff) != 0 || rsv != MD_INIT_CHK_ID ||
	    head != MD_FEATURE_PATTERN || tail != MD_FEATURE_PATTERN)
		return -EPROTO;
	md->state |= ST_HS1;
	dev_info(md->dev, "HS1 received: modem firmware is running\n");
	return 0;
}

/*
 * MT6789 boots MD1 twice, as stock LK + kernel do: the first trigger runs the
 * boot ROM signature check only (flags at 0x1001A824..30), then MD1 must be
 * power-cycled and triggered again to run the firmware (md_start_platform()
 * then md_cd_start()). Verified on the Q25: one trigger never posts HS1, the
 * second posts HS1 within ~1 s.
 */
static int cmd_start(struct md1_owner *md)
{
	int ret;

	if (!(md->state & ST_LOADED))
		return -EINVAL;
	if (md1_is_on(md)) {
		ret = cmd_power_off(md);
		if (ret)
			return ret;
	}
	md->state &= ~ST_BROM_PASS;
	if (!(md->state & ST_REMAPPED)) {
		ret = cmd_remap(md);
		if (ret)
			return ret;
	}
	ret = cmd_ccif_prep(md);
	ret = ret ?: cmd_power_on(md);
	ret = ret ?: cmd_boot(md);
	ret = ret ?: cmd_poll_brom(md);
	ret = ret ?: md1_power_off(md, false);
	ret = ret ?: cmd_ccif_prep(md);
	ret = ret ?: cmd_power_on(md);
	ret = ret ?: cmd_boot(md);
	return ret ?: cmd_hs1_wait(md);
}

static unsigned long mpu_read(unsigned long type, unsigned long region, unsigned long group)
{
	struct arm_smccc_res res;

	sip(SIP_BL_EMIMPU, EMIMPU_READ, type, region, group, &res);
	return res.a0;
}

static bool mpu_region_free(unsigned int r)
{
	return !mpu_read(EMIMPU_READ_SA, r, 0) && !mpu_read(EMIMPU_READ_EA, r, 0) &&
	       !mpu_read(EMIMPU_READ_APC, r, 0) && !mpu_read(EMIMPU_READ_APC, r, 1);
}

static void cmd_mpu_scan(struct md1_owner *md)
{
	unsigned int r, used = 0;

	for (r = 0; r < 32; r++) {
		unsigned long sa = mpu_read(EMIMPU_READ_SA, r, 0);
		unsigned long ea = mpu_read(EMIMPU_READ_EA, r, 0);
		unsigned long a0 = mpu_read(EMIMPU_READ_APC, r, 0);
		unsigned long a1 = mpu_read(EMIMPU_READ_APC, r, 1);

		if (!sa && !ea && !a0 && !a1)
			continue;
		used |= BIT(r);
		dev_info(md->dev, "mpu-scan: region %2u sa=%#lx ea=%#lx apc=%#lx/%#lx\n",
			 r, sa, ea, a1, a0);
	}
	dev_info(md->dev, "mpu-scan: used mask %#x\n", used);
}

static char *mpu_regions = "20,21";
module_param(mpu_regions, charp, 0444);
MODULE_PARM_DESC(mpu_regions, "EMI MPU region IDs that mpu-bound may claim if free");

/* Forbid MD1 and MD HW masters on the non-smem parts of the bank4 windows. */
static int cmd_mpu_bound(struct md1_owner *md)
{
	u64 lo = min(md->c.start, md->nc.start);
	u64 hi = max(md->c.start, md->nc.start) + (u64)4 * SMEM_SLOT;
	u64 cend = ALIGN(md->c.start + resource_size(&md->c), MPU_ALIGN);
	u64 ncend = ALIGN(md->nc.start + resource_size(&md->nc), MPU_ALIGN);
	struct { u64 s, e; } gap[2];
	unsigned int ids[2], n = 0, i;
	char *list, *tok, *cur;
	u32 apc0, apc1 = 0;

	if (!(md->state & ST_REMAPPED) || md->c.start > md->nc.start || cend > md->nc.start)
		return -EINVAL;
	if (md->c.start != lo)
		return -EINVAL;
	gap[0].s = cend;
	gap[0].e = md->nc.start;
	gap[1].s = ncend;
	gap[1].e = hi;

	list = kstrdup(mpu_regions, GFP_KERNEL);
	if (!list)
		return -ENOMEM;
	cur = list;
	while ((tok = strsep(&cur, ",")) && n < ARRAY_SIZE(ids)) {
		unsigned int r;

		if (kstrtouint(tok, 0, &r) || r >= 32 || !mpu_region_free(r))
			continue;
		ids[n++] = r;
	}
	kfree(list);
	if (n < ARRAY_SIZE(gap)) {
		dev_err(md->dev, "mpu-bound: only %u free region(s) in \"%s\"\n", n, mpu_regions);
		return -EBUSY;
	}
	apc0 = MPU_FORBIDDEN << (3 * MPU_DOMAIN_MD1) | MPU_FORBIDDEN << (3 * MPU_DOMAIN_MDHW);
	for (i = 0; i < ARRAY_SIZE(gap); i++) {
		struct arm_smccc_res res;
		unsigned long sa = (gap[i].s >> 16) | ((unsigned long)ids[i] << 24);

		if (gap[i].e <= gap[i].s)
			continue;
		sip(SIP_BL_EMIMPU, EMIMPU_SET, sa, (gap[i].e >> 16) | (1UL << 24), apc1, &res);
		if (!res.a0)
			sip(SIP_BL_EMIMPU, EMIMPU_SET, sa, gap[i].e >> 16, apc0, &res);
		dev_info(md->dev, "mpu-bound: region %u [%#llx,%#llx) MD1+MDHW forbidden ret=%#lx\n",
			 ids[i], gap[i].s, gap[i].e, res.a0);
		if (res.a0)
			return -EIO;
	}
	md->state |= ST_MPU;
	return 0;
}

/*
 * LK hand-off for the ECCCI stack: image placed, remapped, MPU bounded, boot ROM
 * check passed (first trigger), tag blob written and published on /mddriver.
 * The kernel md_start_platform() then power-cycles MD1 through our genpd.
 */
static int cmd_handoff(struct md1_owner *md)
{
	struct q25_md1_lkinfo_in in = { };
	struct q25_md1_layout lay = { };
	void __iomem *tag;
	int ret;

	if (!md->mddriver || !md->pd_registered || !md->tag.start)
		return -ENODEV;
	if (!(md->state & ST_LOADED) || (md->state & ST_HANDOFF))
		return -EINVAL;
	if (md1_is_on(md)) {
		ret = cmd_power_off(md);
		if (ret)
			return ret;
	}
	ret = (md->state & ST_REMAPPED) ? 0 : cmd_remap(md);
	ret = ret ?: (md->state & ST_MPU) ? 0 : cmd_mpu_bound(md);
	ret = ret ?: cmd_power_on(md);
	ret = ret ?: cmd_boot(md);
	ret = ret ?: cmd_poll_brom(md);
	if (ret)
		return ret;

	tag = ioremap_wc(md->tag.start, resource_size(&md->tag));
	if (!tag)
		return -ENOMEM;
	in = (struct q25_md1_lkinfo_in){
		.chk_hdr = md->chk, .img_base = md->img.start,
		.nc_base = md->nc.start, .nc_size = resource_size(&md->nc),
		.c_base = md->c.start, .c_size = resource_size(&md->c),
		.tag_va = tag, .tag_phys = md->tag.start, .mddriver = md->mddriver,
	};
	ret = q25_md1_build_lkinfo(&in, &lay);
	iounmap(tag);
	if (ret)
		return ret;
	md->state |= ST_HANDOFF;
	dev_info(md->dev,
		 "handoff: %u tags (%u bytes), nc %#x c %#x; load ccci_util_lib next\n",
		 lay.tag_num, lay.tag_bytes, lay.nc_total, lay.c_total);
	return 0;
}

static const struct {
	const char *name;
	int (*fn)(struct md1_owner *md);
} cmds[] = {
	{ "load", cmd_load },
	{ "remap", cmd_remap },
	{ "ccif-prep", cmd_ccif_prep },
	{ "power-on", cmd_power_on },
	{ "boot", cmd_boot },
	{ "poll-brom", cmd_poll_brom },
	{ "hs1-wait", cmd_hs1_wait },
	{ "power-off", cmd_power_off },
	{ "start", cmd_start },
	{ "mpu-bound", cmd_mpu_bound },
	{ "handoff", cmd_handoff },
};

static ssize_t command_store(struct device *dev, struct device_attribute *attr,
			     const char *buf, size_t count)
{
	struct md1_owner *md = dev_get_drvdata(dev);
	unsigned int i;
	int ret = -EINVAL;

	mutex_lock(&md->lock);
	if (sysfs_streq(buf, "report")) {
		cmd_report(md);
		ret = 0;
	} else if (sysfs_streq(buf, "smc-probe")) {
		cmd_smc_probe(md);
		ret = 0;
	} else if (sysfs_streq(buf, "boot-status")) {
		cmd_boot_status(md);
		ret = 0;
	} else if (sysfs_streq(buf, "mpu-scan")) {
		cmd_mpu_scan(md);
		ret = 0;
	} else if (md->state & ST_HANDOFF) {
		ret = -EBUSY;	/* ECCCI owns MD1 power now */
	} else {
		for (i = 0; i < ARRAY_SIZE(cmds); i++) {
			if (sysfs_streq(buf, cmds[i].name)) {
				ret = cmds[i].fn(md);
				if (ret)
					dev_err(dev, "%s failed: %d\n", cmds[i].name, ret);
				break;
			}
		}
	}
	mutex_unlock(&md->lock);
	return ret ? ret : count;
}
static DEVICE_ATTR_WO(command);

static ssize_t state_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	struct md1_owner *md = dev_get_drvdata(dev);

	return sysfs_emit(buf, "%#x\n", READ_ONCE(md->state));
}
static DEVICE_ATTR_RO(state);

static struct attribute *md1_attrs[] = {
	&dev_attr_command.attr,
	&dev_attr_state.attr,
	NULL,
};
ATTRIBUTE_GROUPS(md1);

/* Accepted-DTB layout, used only when no zinwa,q25-md1-owner node exists. */
#define SA_IMG_BASE		0xdc000000
#define SA_CCIF_AP		0x10209000
#define SA_CCIF_MD		0x1020a000
#define SA_FW			"q25-md1/md1img.img"
#define CLK_IFRAO_CCIF_AP	30
#define CLK_IFRAO_CCIF_MD	33

static bool standalone;
module_param(standalone, bool, 0444);
MODULE_PARM_DESC(standalone, "bind to the accepted DTB layout without an owner node");

static struct platform_device *sa_pdev;

static bool md_off_at_boot;
module_param(md_off_at_boot, bool, 0444);
MODULE_PARM_DESC(md_off_at_boot, "power MD1 off at probe (preloader leaves it on, unbooted)");

static int md1_pd_on(struct generic_pm_domain *pd)
{
	return mtcmos_on(container_of(pd, struct md1_owner, pd));
}

static int md1_pd_off(struct generic_pm_domain *pd)
{
	return mtcmos_off(container_of(pd, struct md1_owner, pd), false);
}

static void md1_pd_remove(void *data)
{
	struct md1_owner *md = data;

	of_genpd_del_provider(md->dev->of_node);
	pm_genpd_remove(&md->pd);
}

static int md1_register_pd(struct md1_owner *md)
{
	int ret;

	md->pd.name = "md1";
	md->pd.power_on = md1_pd_on;
	md->pd.power_off = md1_pd_off;
	ret = pm_genpd_init(&md->pd, NULL, !md1_is_on(md));
	if (ret)
		return ret;
	ret = of_genpd_add_provider_simple(md->dev->of_node, &md->pd);
	if (ret) {
		pm_genpd_remove(&md->pd);
		return ret;
	}
	md->pd_registered = true;
	return devm_add_action_or_reset(md->dev, md1_pd_remove, md);
}

static int sa_rmem(const char *path, struct resource *r)
{
	struct device_node *np = of_find_node_by_path(path);
	int ret;

	if (!np)
		return -ENODEV;
	ret = of_property_read_bool(np, "no-map") ? of_address_to_resource(np, 0, r) : -EINVAL;
	of_node_put(np);
	return ret;
}

static struct regmap *sa_syscon(const char *compat)
{
	struct device_node *np = of_find_compatible_node(NULL, NULL, compat);
	struct regmap *map;

	if (!np)
		return ERR_PTR(-ENODEV);
	map = syscon_node_to_regmap(np);
	of_node_put(np);
	return map;
}

static int sa_clocks(struct md1_owner *md)
{
	static const int idx[] = { CLK_IFRAO_CCIF_AP, CLK_IFRAO_CCIF_MD };
	struct of_phandle_args spec = { .args_count = 1 };
	unsigned int i;

	spec.np = of_find_compatible_node(NULL, NULL, "mediatek,mt6789-infracfg_ao");
	if (!spec.np)
		return -ENODEV;
	for (i = 0; i < ARRAY_SIZE(idx); i++) {
		spec.args[0] = idx[i];
		md->clks[i].clk = of_clk_get_from_provider(&spec);
		if (IS_ERR(md->clks[i].clk)) {
			int ret = PTR_ERR(md->clks[i].clk);

			while (i--)
				clk_put(md->clks[i].clk);
			of_node_put(spec.np);
			return ret;
		}
	}
	of_node_put(spec.np);
	return 0;
}

static void __iomem *sa_ioremap(struct device *dev, phys_addr_t pa)
{
	if (!devm_request_mem_region(dev, pa, SZ_4K, dev_name(dev)))
		return IOMEM_ERR_PTR(-EBUSY);
	return devm_ioremap(dev, pa, SZ_4K) ?: IOMEM_ERR_PTR(-ENOMEM);
}

static int md1_common_resources(struct md1_owner *md);

static int md1_probe_standalone(struct md1_owner *md)
{
	struct device *dev = md->dev;
	int ret;

	md->fw_name = SA_FW;
	ret = md1_common_resources(md);
	if (ret)
		return ret;
	md->ccif_ap = sa_ioremap(dev, SA_CCIF_AP);
	if (IS_ERR(md->ccif_ap))
		return PTR_ERR(md->ccif_ap);
	md->ccif_md = sa_ioremap(dev, SA_CCIF_MD);
	if (IS_ERR(md->ccif_md))
		return PTR_ERR(md->ccif_md);
	return sa_clocks(md);
}

static int md1_common_resources(struct md1_owner *md)
{
	struct device_node *np;
	int ret;

	md->img = DEFINE_RES_MEM(SA_IMG_BASE, SZ_128M);
	ret = sa_rmem("/reserved-memory/ap_md_nc_smem@8e000000", &md->nc);
	ret = ret ?: sa_rmem("/reserved-memory/ap_md_c_smem@8c000000", &md->c);
	if (ret)
		return dev_err_probe(md->dev, ret, "smem reservations not in DT\n");
	if (sa_rmem("/reserved-memory/ccci_tag@bf9f0000", &md->tag) ||
	    resource_size(&md->tag) < SZ_64K)
		md->tag = (struct resource){ };
	md->spm = sa_syscon("mediatek,mt6789-scpsys");
	if (IS_ERR(md->spm))
		return dev_err_probe(md->dev, PTR_ERR(md->spm), "spm syscon\n");
	md->infra = sa_syscon("mediatek,mt6789-infracfg_ao");
	if (IS_ERR(md->infra))
		return dev_err_probe(md->dev, PTR_ERR(md->infra), "infracfg_ao syscon\n");
	np = of_find_compatible_node(NULL, NULL, "mediatek,mddriver");
	md->mddriver = np;	/* reference kept for the module lifetime */
	return 0;
}

static int md1_probe_dt(struct platform_device *pdev, struct md1_owner *md)
{
	struct device *dev = &pdev->dev;
	struct device_node *np = dev->of_node;
	int ret;

	of_property_read_u32(np, "zinwa,hs1-timeout-ms", &md->hs1_ms);
	if (of_property_read_string(np, "firmware-name", &md->fw_name))
		md->fw_name = SA_FW;
	ret = md1_common_resources(md);
	if (ret)
		return ret;
	/* With the ECCCI stack, CCIF belongs to ccci_ccif; the node then has no reg. */
	if (of_property_match_string(np, "reg-names", "ccif-ap") < 0) {
		md->ccif_ap = NULL;
		return 0;
	}
	md->ccif_ap = devm_platform_ioremap_resource_byname(pdev, "ccif-ap");
	if (IS_ERR(md->ccif_ap))
		return PTR_ERR(md->ccif_ap);
	md->ccif_md = devm_platform_ioremap_resource_byname(pdev, "ccif-md");
	if (IS_ERR(md->ccif_md))
		return PTR_ERR(md->ccif_md);
	md->clks[0].id = "ccif-ap";
	md->clks[1].id = "ccif-md";
	ret = devm_clk_bulk_get(dev, ARRAY_SIZE(md->clks), md->clks);
	if (ret)
		return dev_err_probe(dev, ret, "ccif clocks\n");
	return 0;
}

static int md1_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct md1_owner *md;
	int ret;

	md = devm_kzalloc(dev, sizeof(*md), GFP_KERNEL);
	if (!md)
		return -ENOMEM;
	md->dev = dev;
	mutex_init(&md->lock);
	md->hs1_ms = 15000;
	ret = dev->of_node ? md1_probe_dt(pdev, md) : md1_probe_standalone(md);
	if (ret)
		return ret;
	md->hs1_ms = clamp(md->hs1_ms, 100U, 60000U);

	/* The image span must never be Linux RAM; smem must be no-map carve-outs. */
	if (resource_size(&md->img) < SZ_128M ||
	    region_intersects(md->img.start, resource_size(&md->img), IORESOURCE_SYSTEM_RAM,
			      IORES_DESC_NONE) != REGION_DISJOINT ||
	    region_intersects(md->nc.start, resource_size(&md->nc), IORESOURCE_SYSTEM_RAM,
			      IORES_DESC_NONE) != REGION_DISJOINT ||
	    region_intersects(md->c.start, resource_size(&md->c), IORESOURCE_SYSTEM_RAM,
			      IORES_DESC_NONE) != REGION_DISJOINT) {
		if (!dev->of_node)
			clk_bulk_put(ARRAY_SIZE(md->clks), md->clks);
		return dev_err_probe(dev, -EADDRINUSE, "modem memory overlaps System RAM\n");
	}

	platform_set_drvdata(pdev, md);
	if (md_off_at_boot && md1_is_on(md)) {
		ret = mtcmos_off(md, true);
		dev_info(dev, "md_off_at_boot: MD1 %s (%d)\n", ret ? "left on" : "powered off", ret);
	}
	if (dev->of_node && of_property_present(dev->of_node, "#power-domain-cells")) {
		ret = md1_register_pd(md);
		if (ret)
			return dev_err_probe(dev, ret, "MD1 power domain\n");
	}
	dev_info(dev, "MD1 owner idle (%s%s): image %pR nc %pR c %pR fw %s md1=%s\n",
		 dev->of_node ? "dt" : "standalone", md->pd_registered ? ", genpd" : "",
		 &md->img, &md->nc, &md->c, md->fw_name, md1_is_on(md) ? "on" : "off");
	return 0;
}

static const struct of_device_id md1_match[] = {
	{ .compatible = "zinwa,q25-md1-owner" },
	{ }
};
MODULE_DEVICE_TABLE(of, md1_match);

static struct platform_driver md1_driver = {
	.probe = md1_probe,
	.driver = {
		.name = "q25-md1-owner",
		.of_match_table = md1_match,
		.dev_groups = md1_groups,
		.suppress_bind_attrs = true,
	},
};

static int __init md1_init(void)
{
	struct device_node *np;
	int ret = platform_driver_register(&md1_driver);

	if (ret || !standalone)
		return ret;
	np = of_find_compatible_node(NULL, NULL, "zinwa,q25-md1-owner");
	if (np) {
		of_node_put(np);
		pr_info("q25-md1-owner: DT owner node present, standalone ignored\n");
		return 0;
	}
	sa_pdev = platform_device_register_simple("q25-md1-owner", PLATFORM_DEVID_NONE,
						  NULL, 0);
	return PTR_ERR_OR_ZERO(sa_pdev);
}
module_init(md1_init);

MODULE_DESCRIPTION("Zinwa Q25 MT6789 MD1 staged boot owner");
MODULE_LICENSE("GPL");
