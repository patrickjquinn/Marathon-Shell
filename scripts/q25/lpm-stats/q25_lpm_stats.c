// SPDX-License-Identifier: GPL-2.0
/*
 * Reads the MT6789 BL31's low-power statistics: for each SPM constraint
 * (bus26m, syspll, dram, cpu-buck-ldo) whether it is enabled, how often the
 * SoC entered it and what currently blocks it. Read-only firmware calls, as
 * MediaTek's lpm debug driver makes them. /sys/kernel/debug/q25_lpm_stats.
 */
#include <linux/arm-smccc.h>
#include <linux/debugfs.h>
#include <linux/module.h>
#include <linux/seq_file.h>

#define SIP_LPM_CONTROL		ARM_SMCCC_CALL_VAL(ARM_SMCCC_FAST_CALL, ARM_SMCCC_SMC_64, \
						   ARM_SMCCC_OWNER_SIP, 0x507)
#define LPM_USER_SPM_DBG	1
#define LPM_ID(uid)		(0xDA000000 | (LPM_USER_SPM_DBG << 16) | (uid))
#define ACT_GET			BIT(2)

enum { IDLE_CNT = 1, RC_SWITCH = 5, RC_CNT = 6, COND_CHECK = 7, COND_BLOCK = 8,
       BLOCK_DETAIL = 10 };

static const char * const rc_name[] = { "bus26m", "syspll", "dram", "cpu-buck-ldo" };
static const char * const cg_name[] = { "MTCMOS_0", "INFRA_0", "INFRA_1", "INFRA_2",
					"INFRA_3", "INFRA_4", "MMSYS_0", "MMSYS_3" };
static const char * const pll_name[] = { "UNIVPLL", "MFGPLL", "MSDCPLL", "TVDPLL", "MMPLL" };

static unsigned long lpm_get(u32 uid, unsigned long a, unsigned long b)
{
	struct arm_smccc_res res;

	arm_smccc_smc(SIP_LPM_CONTROL, LPM_ID(uid), ACT_GET, a, b, 0, 0, 0, &res);
	return res.a0;
}

static int stats_show(struct seq_file *s, void *unused)
{
	int rc, i;

	seq_printf(s, "idle: count=%lu duration=%lu\n", lpm_get(IDLE_CNT, 0, 0),
		   lpm_get(IDLE_CNT, 1, 0));
	for (rc = 0; rc < ARRAY_SIZE(rc_name); rc++) {
		u32 block = lpm_get(COND_BLOCK, rc, 0);

		seq_printf(s, "%s: switch=%#lx count=%lu blocked=%lu block=%#010x\n",
			   rc_name[rc], lpm_get(RC_SWITCH, rc, 0), lpm_get(RC_CNT, rc, 0),
			   lpm_get(COND_CHECK, rc, 0), block);
		for (i = 0; i < ARRAY_SIZE(cg_name); i++)
			if (block & BIT(i))
				seq_printf(s, "  %s=%#010lx\n", cg_name[i],
					   lpm_get(BLOCK_DETAIL, rc, i));
		for (i = 0; i < ARRAY_SIZE(pll_name); i++)
			if (block & BIT(16 + i))
				seq_printf(s, "  %s on\n", pll_name[i]);
	}
	return 0;
}
DEFINE_SHOW_ATTRIBUTE(stats);

static struct dentry *file;

static int __init q25_lpm_stats_init(void)
{
	file = debugfs_create_file("q25_lpm_stats", 0400, NULL, NULL, &stats_fops);
	return 0;
}

static void __exit q25_lpm_stats_exit(void)
{
	debugfs_remove(file);
}

module_init(q25_lpm_stats_init);
module_exit(q25_lpm_stats_exit);
MODULE_DESCRIPTION("MT6789 BL31 low-power statistics");
MODULE_LICENSE("GPL");
