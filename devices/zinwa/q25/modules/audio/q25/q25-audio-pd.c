// SPDX-License-Identifier: GPL-2.0-only
/*
 * MT6789 AUDIO power domain for the Zinwa Q25 bring-up kernel.
 *
 * The SPM power-controller node is owned by q25-mfg-only-v2, which only
 * provides the MFG domains. This adds a second genpd provider on the same
 * node that resolves index MT6789_POWER_DOMAIN_AUDIO (11) and nothing else;
 * genpd_get_from_provider() skips providers whose xlate fails.
 *
 * Sequence and data follow drivers/pmdomain/mediatek/mtk-pm-domains.c and
 * linux-mediatek mt6789-pm-domains.h (AUDIO: ctl 0x358, sta bit 22,
 * SRAM pdn bit 8 / ack bit 12, infra bus protect BIT(4) set 0x714 clr 0x718
 * sta 0x724, clear-ack ignored), cross-checked with the stock
 * mtk-scpsys-mt6789.c.
 */
#include <linux/clk.h>
#include <linux/clk-provider.h>
#include <linux/slab.h>
#include <linux/delay.h>
#include <linux/iopoll.h>
#include <linux/mfd/syscon.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/pm_domain.h>
#include <linux/regmap.h>

#include <dt-bindings/power/mediatek,mt6789-power.h>

#define PWR_STA			0x16c
#define PWR_STA_2ND		0x170
#define AUDIO_PWR_CON		0x358
#define AUDIO_STA_MASK		BIT(22)
#define SRAM_PDN		BIT(8)
#define SRAM_PDN_ACK		BIT(12)

#define PWR_RST_B		BIT(0)
#define PWR_ISO			BIT(1)
#define PWR_ON			BIT(2)
#define PWR_ON_2ND		BIT(3)
#define PWR_CLK_DIS		BIT(4)

#define INFRA_PROT_SET		0x714
#define INFRA_PROT_CLR		0x718
#define INFRA_PROT_STA		0x724
#define INFRA_PROT_AUDIO	BIT(4)

#define POLL_US			10
#define TIMEOUT_US		USEC_PER_SEC

static struct q25_audio_pd {
	struct generic_pm_domain genpd;
	struct regmap *spm;
	struct regmap *infra;
	struct clk_bulk_data *clks;
	int num_clks;
	struct generic_pm_domain *domains[MT6789_POWER_DOMAIN_AUDIO + 1];
	struct genpd_onecell_data data;
} pd;

static bool audio_is_on(void)
{
	u32 a = 0, b = 0;

	regmap_read(pd.spm, PWR_STA, &a);
	regmap_read(pd.spm, PWR_STA_2ND, &b);
	return (a & AUDIO_STA_MASK) && (b & AUDIO_STA_MASK);
}

static int q25_audio_power_on(struct generic_pm_domain *genpd)
{
	unsigned int tmp;
	bool on;
	int ret;

	ret = clk_bulk_prepare_enable(pd.num_clks, pd.clks);
	if (ret)
		return ret;

	regmap_set_bits(pd.spm, AUDIO_PWR_CON, PWR_ON);
	regmap_set_bits(pd.spm, AUDIO_PWR_CON, PWR_ON_2ND);
	ret = readx_poll_timeout(audio_is_on, , on, on, POLL_US, TIMEOUT_US);
	if (ret)
		goto err;

	regmap_clear_bits(pd.spm, AUDIO_PWR_CON, PWR_CLK_DIS);
	regmap_clear_bits(pd.spm, AUDIO_PWR_CON, PWR_ISO);
	regmap_set_bits(pd.spm, AUDIO_PWR_CON, PWR_RST_B);

	regmap_clear_bits(pd.spm, AUDIO_PWR_CON, SRAM_PDN);
	ret = regmap_read_poll_timeout(pd.spm, AUDIO_PWR_CON, tmp,
				       !(tmp & SRAM_PDN_ACK), POLL_US, TIMEOUT_US);
	if (ret)
		goto err;

	/* BUS_PROT_WR_IGN: release protection, ack not checked */
	regmap_write(pd.infra, INFRA_PROT_CLR, INFRA_PROT_AUDIO);

	pr_info("q25-audio-pd: audio on, PWR_CON=%#x\n",
		({ regmap_read(pd.spm, AUDIO_PWR_CON, &tmp); tmp; }));
	return 0;

err:
	regmap_read(pd.spm, AUDIO_PWR_CON, &tmp);
	pr_err("q25-audio-pd: power on failed %d, PWR_CON=%#x\n", ret, tmp);
	clk_bulk_disable_unprepare(pd.num_clks, pd.clks);
	return ret;
}

static int q25_audio_power_off(struct generic_pm_domain *genpd)
{
	unsigned int tmp;
	bool on;
	int ret;

	regmap_write(pd.infra, INFRA_PROT_SET, INFRA_PROT_AUDIO);
	ret = regmap_read_poll_timeout(pd.infra, INFRA_PROT_STA, tmp,
				       (tmp & INFRA_PROT_AUDIO) == INFRA_PROT_AUDIO,
				       POLL_US, TIMEOUT_US);
	if (ret)
		return ret;

	regmap_set_bits(pd.spm, AUDIO_PWR_CON, SRAM_PDN);
	ret = regmap_read_poll_timeout(pd.spm, AUDIO_PWR_CON, tmp,
				       tmp & SRAM_PDN_ACK, POLL_US, TIMEOUT_US);
	if (ret)
		return ret;

	regmap_set_bits(pd.spm, AUDIO_PWR_CON, PWR_ISO);
	regmap_set_bits(pd.spm, AUDIO_PWR_CON, PWR_CLK_DIS);
	regmap_clear_bits(pd.spm, AUDIO_PWR_CON, PWR_RST_B);
	regmap_clear_bits(pd.spm, AUDIO_PWR_CON, PWR_ON);
	regmap_clear_bits(pd.spm, AUDIO_PWR_CON, PWR_ON_2ND);
	ret = readx_poll_timeout(audio_is_on, , on, !on, POLL_US, TIMEOUT_US);
	if (ret)
		return ret;

	clk_bulk_disable_unprepare(pd.num_clks, pd.clks);
	pr_info("q25-audio-pd: audio off\n");
	return 0;
}

static int __init q25_audio_pd_init(void)
{
	struct device_node *np, *child, *dn = NULL;
	u32 reg;
	int i, ret;

	np = of_find_compatible_node(NULL, NULL, "mediatek,mt6789-power-controller");
	if (!np)
		return -ENODEV;

	for_each_child_of_node(np, child) {
		if (!of_property_read_u32(child, "reg", &reg) &&
		    reg == MT6789_POWER_DOMAIN_AUDIO) {
			dn = child;
			break;
		}
	}
	if (!dn) {
		ret = -ENODEV;
		goto out_np;
	}

	pd.spm = syscon_node_to_regmap(np->parent);
	if (IS_ERR(pd.spm)) {
		ret = PTR_ERR(pd.spm);
		goto out_dn;
	}
	pd.infra = syscon_regmap_lookup_by_phandle(dn, "mediatek,infracfg");
	if (IS_ERR(pd.infra)) {
		ret = PTR_ERR(pd.infra);
		goto out_dn;
	}

	pd.num_clks = of_clk_get_parent_count(dn);
	pd.clks = kcalloc(pd.num_clks, sizeof(*pd.clks), GFP_KERNEL);
	if (!pd.clks) {
		ret = -ENOMEM;
		goto out_dn;
	}
	for (i = 0; i < pd.num_clks; i++) {
		pd.clks[i].clk = of_clk_get(dn, i);
		if (IS_ERR(pd.clks[i].clk)) {
			ret = PTR_ERR(pd.clks[i].clk);
			pd.num_clks = i;
			goto out_clks;
		}
	}

	pd.genpd.name = "q25-audio";
	pd.genpd.power_on = q25_audio_power_on;
	pd.genpd.power_off = q25_audio_power_off;
	pd.genpd.flags = GENPD_FLAG_NO_STAY_ON;

	/* stock firmware leaves AUDIO off (PWR_CON 0x1112); keep refcounts honest if not */
	if (audio_is_on()) {
		ret = clk_bulk_prepare_enable(pd.num_clks, pd.clks);
		if (ret)
			goto out_clks;
	}
	ret = pm_genpd_init(&pd.genpd, NULL, !audio_is_on());
	if (ret)
		goto out_clks;

	pd.domains[MT6789_POWER_DOMAIN_AUDIO] = &pd.genpd;
	pd.data.domains = pd.domains;
	pd.data.num_domains = ARRAY_SIZE(pd.domains);
	ret = of_genpd_add_provider_onecell(np, &pd.data);
	if (ret) {
		pm_genpd_remove(&pd.genpd);
		goto out_clks;
	}

	pr_info("q25-audio-pd: provider for %pOF index %d (%d clocks), initially %s\n",
		dn, MT6789_POWER_DOMAIN_AUDIO, pd.num_clks,
		audio_is_on() ? "on" : "off");
	of_node_put(dn);
	of_node_put(np);
	return 0;

out_clks:
	while (pd.num_clks--)
		clk_put(pd.clks[pd.num_clks].clk);
	kfree(pd.clks);
out_dn:
	of_node_put(dn);
out_np:
	of_node_put(np);
	pr_err("q25-audio-pd: init failed %d\n", ret);
	return ret;
}
module_init(q25_audio_pd_init);

MODULE_DESCRIPTION("Zinwa Q25 MT6789 AUDIO power domain");
MODULE_LICENSE("GPL");
