// SPDX-License-Identifier: GPL-2.0-only
/*
 * MT6789 CAM power domain for the Zinwa Q25.
 *
 * Same arrangement as q25-conn-pd: a further genpd provider on the SPM
 * power-controller node resolving only MT6789_POWER_DOMAIN_CAM (12).
 * CAM is a child of DISP, which the firmware leaves on for the panel; DISP
 * must be on and is never written.
 *
 * Data: stock mtk-scpsys-mt6789.c and linux-mediatek mt6789-pm-domains.h:
 * CAM ctl 0x35c, sta bit 23 in 0x16c and 0x170, SRAM pdn bit 8 / ack bit
 * 12, infracfg bus protect BIT(0)|BIT(2) then BIT(1)|BIT(3) via 0x2d4/0x2d8
 * sta 0x2ec, clear-ack ignored. Sequence: stock scpsys_power_on/off.
 */
#include <linux/clk.h>
#include <linux/debugfs.h>
#include <linux/delay.h>
#include <linux/iopoll.h>
#include <linux/mfd/syscon.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/pm_domain.h>
#include <linux/regmap.h>

#include <dt-bindings/power/mediatek,mt6789-power.h>

static bool enable;
module_param(enable, bool, 0444);
MODULE_PARM_DESC(enable, "Provide the CAM power domain (default disabled)");

#define PWR_STA			0x16c
#define PWR_STA_2ND		0x170
#define DISP_PWR_CON		0x354
#define CAM_PWR_CON		0x35c
#define DISP_STA		BIT(21)
#define CAM_STA			BIT(23)
#define RAWA_STA		BIT(24)
#define RAWB_STA		BIT(25)

#define PWR_RST_B		BIT(0)
#define PWR_ISO			BIT(1)
#define PWR_ON			BIT(2)
#define PWR_ON_2ND		BIT(3)
#define PWR_CLK_DIS		BIT(4)
#define SRAM_PDN		BIT(8)
#define SRAM_PDN_ACK		BIT(12)

#define INFRA_PROT_SET		0x2d4
#define INFRA_PROT_CLR		0x2d8
#define INFRA_PROT_STA		0x2ec
#define INFRA_PROT_CAM		GENMASK_U32(3, 0)

#define POLL_US			10
#define TIMEOUT_US		USEC_PER_SEC

/* Set 0..1 on power-off, clear 1..0 on power-on. */
static const u32 cam_bp[] = { BIT(0) | BIT(2), BIT(1) | BIT(3) };

static struct q25_cam_pd {
	struct generic_pm_domain genpd;
	struct regmap *spm;
	struct regmap *infra;
	struct clk_bulk_data clks[1];
	struct clk_bulk_data subsys_clks[2];
	struct generic_pm_domain *domains[MT6789_POWER_DOMAIN_CAM + 1];
	struct genpd_onecell_data data;

	/*
	 * hw_lock serialises every CAM power sequence. genpd_on: on for genpd
	 * consumers; test_on: on for the debugfs test only. Never both.
	 */
	struct mutex hw_lock;
	bool genpd_on;
	bool test_on;
} pd = {
	.clks = { { .id = "cam" } },
	.subsys_clks = { { .id = "cam-0" }, { .id = "cam-1" } },
};

static void sta_read(u32 *a, u32 *b)
{
	*a = 0;
	*b = 0;
	regmap_read(pd.spm, PWR_STA, a);
	regmap_read(pd.spm, PWR_STA_2ND, b);
}

static bool dom_is_on(u32 mask)
{
	u32 a, b;

	sta_read(&a, &b);
	return (a & mask) == mask && (b & mask) == mask;
}

static bool dom_is_off(u32 mask)
{
	u32 a, b;

	sta_read(&a, &b);
	return !(a & mask) && !(b & mask);
}

static bool cam_is_on(void)
{
	return dom_is_on(CAM_STA);
}

static bool cam_is_off(void)
{
	return dom_is_off(CAM_STA);
}

static void cam_step(const char *step)
{
	u32 con = 0, bp = 0, a, b;

	regmap_read(pd.spm, CAM_PWR_CON, &con);
	sta_read(&a, &b);
	regmap_read(pd.infra, INFRA_PROT_STA, &bp);
	pr_info("q25-cam-pd: %s: PWR_CON=%#x sta=%d sta2nd=%d bp=%#x\n", step, con,
		!!(a & CAM_STA), !!(b & CAM_STA), bp & INFRA_PROT_CAM);
}

static void cam_bp_clear(int from)
{
	for (; from >= 0; from--)
		regmap_write(pd.infra, INFRA_PROT_CLR, cam_bp[from]);
}

static int cam_bp_set(void)
{
	unsigned int tmp;
	int i, ret;

	for (i = 0; i < ARRAY_SIZE(cam_bp); i++) {
		regmap_write(pd.infra, INFRA_PROT_SET, cam_bp[i]);
		ret = regmap_read_poll_timeout(pd.infra, INFRA_PROT_STA, tmp,
					       (tmp & cam_bp[i]) == cam_bp[i],
					       POLL_US, TIMEOUT_US);
		if (ret) {
			pr_err("q25-cam-pd: bus protect %d no ack, sta=%#x\n", i, tmp);
			cam_bp_clear(i);
			return ret;
		}
		cam_step(i ? "off: bus protect 1 set" : "off: bus protect 0 set");
	}
	return 0;
}

static int cam_pwrseq_off(void)
{
	bool off;
	int ret;

	regmap_set_bits(pd.spm, CAM_PWR_CON, PWR_ISO);
	regmap_clear_bits(pd.spm, CAM_PWR_CON, PWR_RST_B);
	regmap_set_bits(pd.spm, CAM_PWR_CON, PWR_CLK_DIS);
	cam_step("off: ISO=1 RST_B=0 CLK_DIS=1");
	regmap_clear_bits(pd.spm, CAM_PWR_CON, PWR_ON);
	regmap_clear_bits(pd.spm, CAM_PWR_CON, PWR_ON_2ND);
	ret = read_poll_timeout(cam_is_off, off, off, POLL_US, TIMEOUT_US, false);
	cam_step(ret ? "off: FAILED, no status ack" : "off: PWR_ON=0 PWR_ON_2ND=0");
	return ret;
}

/* Stock scpsys_power_on() for CAM. Caller holds hw_lock. */
static int cam_hw_on(void)
{
	unsigned int tmp;
	bool on;
	int ret;

	if (!dom_is_on(DISP_STA)) {
		regmap_read(pd.spm, DISP_PWR_CON, &tmp);
		pr_err("q25-cam-pd: DISP not on (PWR_CON=%#x), refusing CAM on\n", tmp);
		return -EBUSY;
	}
	if (!cam_is_off()) {
		cam_step("on: REFUSED, CAM not off");
		return -EIO;
	}

	cam_step("on: start");
	ret = clk_bulk_prepare_enable(ARRAY_SIZE(pd.clks), pd.clks);
	if (ret)
		return ret;

	regmap_set_bits(pd.spm, CAM_PWR_CON, PWR_ON);
	cam_step("on: PWR_ON");
	regmap_set_bits(pd.spm, CAM_PWR_CON, PWR_ON_2ND);
	cam_step("on: PWR_ON_2ND");
	ret = read_poll_timeout(cam_is_on, on, on, POLL_US, TIMEOUT_US, false);
	if (ret)
		goto err_withdraw;
	cam_step("on: ack");

	usleep_range(100, 200);
	regmap_clear_bits(pd.spm, CAM_PWR_CON, PWR_CLK_DIS);
	cam_step("on: CLK_DIS=0");
	regmap_clear_bits(pd.spm, CAM_PWR_CON, PWR_ISO);
	cam_step("on: ISO=0");
	regmap_set_bits(pd.spm, CAM_PWR_CON, PWR_RST_B);
	cam_step("on: RST_B=1");

	ret = clk_bulk_prepare_enable(ARRAY_SIZE(pd.subsys_clks), pd.subsys_clks);
	if (ret)
		goto err_pwr;
	cam_step("on: subsys clocks on");

	regmap_clear_bits(pd.spm, CAM_PWR_CON, SRAM_PDN);
	ret = regmap_read_poll_timeout(pd.spm, CAM_PWR_CON, tmp,
				       !(tmp & SRAM_PDN_ACK), POLL_US, TIMEOUT_US);
	if (ret)
		goto err_sram;
	cam_step("on: SRAM_PDN=0 ack");

	cam_bp_clear(ARRAY_SIZE(cam_bp) - 1);
	cam_step("cam on");
	return 0;

err_sram:
	cam_step("on: FAILED, no SRAM ack");
	regmap_set_bits(pd.spm, CAM_PWR_CON, SRAM_PDN);
	clk_bulk_disable_unprepare(ARRAY_SIZE(pd.subsys_clks), pd.subsys_clks);
err_pwr:
	if (cam_pwrseq_off())
		goto err_stuck;
	goto err_clk;
err_withdraw:
	regmap_clear_bits(pd.spm, CAM_PWR_CON, PWR_ON_2ND);
	regmap_clear_bits(pd.spm, CAM_PWR_CON, PWR_ON);
	cam_step("on: FAILED, request withdrawn");
err_clk:
	clk_bulk_disable_unprepare(ARRAY_SIZE(pd.clks), pd.clks);
err_stuck:
	pr_err("q25-cam-pd: power on failed %d\n", ret);
	return ret;
}

/* Stock scpsys_power_off() for CAM. Caller holds hw_lock. */
static int cam_hw_off(void)
{
	unsigned int tmp;
	int ret;

	cam_step("off: start");
	ret = cam_bp_set();
	if (ret)
		return ret;

	regmap_set_bits(pd.spm, CAM_PWR_CON, SRAM_PDN);
	ret = regmap_read_poll_timeout(pd.spm, CAM_PWR_CON, tmp,
				       tmp & SRAM_PDN_ACK, POLL_US, TIMEOUT_US);
	if (ret) {
		cam_step("off: FAILED, no SRAM ack, staying on");
		regmap_clear_bits(pd.spm, CAM_PWR_CON, SRAM_PDN);
		cam_bp_clear(ARRAY_SIZE(cam_bp) - 1);
		return ret;
	}
	cam_step("off: SRAM_PDN=1 ack");

	clk_bulk_disable_unprepare(ARRAY_SIZE(pd.subsys_clks), pd.subsys_clks);
	ret = cam_pwrseq_off();
	if (ret)
		return ret;

	clk_bulk_disable_unprepare(ARRAY_SIZE(pd.clks), pd.clks);
	cam_step("cam off");
	return 0;
}

static int q25_cam_power_on(struct generic_pm_domain *genpd)
{
	int ret;

	mutex_lock(&pd.hw_lock);
	if (pd.test_on) {
		pr_err("q25-cam-pd: debugfs test holds CAM, refusing genpd power on\n");
		ret = -EBUSY;
	} else {
		ret = cam_hw_on();
		pd.genpd_on = !ret;
	}
	mutex_unlock(&pd.hw_lock);
	return ret;
}

static int q25_cam_power_off(struct generic_pm_domain *genpd)
{
	int ret = 0;

	mutex_lock(&pd.hw_lock);
	/* genpd_sync_power_on() ignores a refused power on. */
	if (pd.genpd_on) {
		ret = cam_hw_off();
		if (!ret)
			pd.genpd_on = false;
	}
	mutex_unlock(&pd.hw_lock);
	return ret;
}

static int state_show(struct seq_file *s, void *unused)
{
	u32 con = 0, disp = 0, bp = 0, a, b;

	regmap_read(pd.spm, CAM_PWR_CON, &con);
	regmap_read(pd.spm, DISP_PWR_CON, &disp);
	regmap_read(pd.infra, INFRA_PROT_STA, &bp);
	sta_read(&a, &b);
	seq_printf(s, "PWR_CON=%#x sta=%d sta2nd=%d bp=%#x\n", con,
		   !!(a & CAM_STA), !!(b & CAM_STA), bp & INFRA_PROT_CAM);
	seq_printf(s, "DISP PWR_CON=%#x sta=%d sta2nd=%d rawa=%d/%d rawb=%d/%d\n",
		   disp, !!(a & DISP_STA), !!(b & DISP_STA),
		   !!(a & RAWA_STA), !!(b & RAWA_STA), !!(a & RAWB_STA), !!(b & RAWB_STA));
	seq_printf(s, "genpd consumers=%d genpd_on=%d test_on=%d\n",
		   pd.genpd.device_count, pd.genpd_on, pd.test_on);
	return 0;
}
DEFINE_SHOW_ATTRIBUTE(state);

/*
 * Stand-alone CAM power test: the genpd sequence, run directly, never while
 * genpd has consumers or owns the domain.
 */
static ssize_t test_power_write(struct file *file, const char __user *ubuf,
				size_t count, loff_t *ppos)
{
	bool on;
	int ret;

	ret = kstrtobool_from_user(ubuf, count, &on);
	if (ret)
		return ret;

	mutex_lock(&pd.hw_lock);
	if (on == pd.test_on) {
		ret = 0;
	} else if (pd.genpd.device_count || pd.genpd_on ||
		   pd.genpd.status != GENPD_STATE_OFF) {
		pr_err("q25-cam-pd: test refused: genpd consumers=%d on=%d\n",
		       pd.genpd.device_count, pd.genpd_on);
		ret = -EBUSY;
	} else if (on) {
		ret = cam_hw_on();
		pd.test_on = !ret;
	} else {
		ret = cam_hw_off();
		pd.test_on = !!ret;
	}
	mutex_unlock(&pd.hw_lock);
	return ret ? ret : count;
}

static const struct file_operations test_power_fops = {
	.owner = THIS_MODULE,
	.write = test_power_write,
	.llseek = noop_llseek,
};

static struct device_node *find_domain(struct device_node *parent, u32 id)
{
	struct device_node *child, *found;
	u32 reg;

	for_each_available_child_of_node(parent, child) {
		if (!of_property_read_u32(child, "reg", &reg) && reg == id)
			return child;
		found = find_domain(child, id);
		if (found) {
			of_node_put(child);
			return found;
		}
	}
	return NULL;
}

static int q25_cam_get_clks(struct device_node *dn, struct clk_bulk_data *c, int n)
{
	int i;

	for (i = 0; i < n; i++) {
		c[i].clk = of_clk_get_by_name(dn, c[i].id);
		if (IS_ERR(c[i].clk)) {
			int ret = PTR_ERR(c[i].clk);

			pr_err("q25-cam-pd: clock %s: %d\n", c[i].id, ret);
			while (i--)
				clk_put(c[i].clk);
			return ret;
		}
	}
	return 0;
}

static int q25_cam_check_boot_state(void)
{
	u32 con = 0, disp = 0, bp = 0, a, b;

	regmap_read(pd.spm, CAM_PWR_CON, &con);
	regmap_read(pd.spm, DISP_PWR_CON, &disp);
	regmap_read(pd.infra, INFRA_PROT_STA, &bp);
	sta_read(&a, &b);
	pr_info("q25-cam-pd: boot: CAM PWR_CON=%#x DISP PWR_CON=%#x sta=%#x sta2nd=%#x bp=%#x\n",
		con, disp, a, b, bp);

	if (cam_is_on()) {
		pr_err("q25-cam-pd: CAM is firmware-on; refusing ownership\n");
		return -EBUSY;
	}
	if (!cam_is_off()) {
		pr_err("q25-cam-pd: CAM status inconsistent; refusing ownership\n");
		return -EIO;
	}
	if (!dom_is_on(DISP_STA)) {
		pr_err("q25-cam-pd: DISP not on; refusing\n");
		return -EBUSY;
	}
	if (!dom_is_off(RAWA_STA | RAWB_STA)) {
		pr_err("q25-cam-pd: CAM_RAWA/RAWB not off; refusing\n");
		return -EBUSY;
	}
	return 0;
}

static int __init q25_cam_pd_init(void)
{
	struct device_node *np, *dn, *parent;
	struct dentry *dir;
	u32 reg = 0;
	int ret;

	if (!enable) {
		pr_err("q25-cam-pd: review gate: enable=1 required\n");
		return -EPERM;
	}

	np = of_find_compatible_node(NULL, NULL, "mediatek,mt6789-power-controller");
	if (!np)
		return -ENODEV;

	dn = find_domain(np, MT6789_POWER_DOMAIN_CAM);
	if (!dn) {
		ret = -ENODEV;
		goto out_np;
	}
	parent = of_get_parent(dn);
	ret = of_property_read_u32(parent, "reg", &reg);
	of_node_put(parent);
	if (ret || reg != MT6789_POWER_DOMAIN_DISP) {
		pr_err("q25-cam-pd: %pOF is not under DISP\n", dn);
		ret = -EINVAL;
		goto out_dn;
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

	ret = q25_cam_check_boot_state();
	if (ret)
		goto out_dn;

	ret = q25_cam_get_clks(dn, pd.clks, ARRAY_SIZE(pd.clks));
	if (ret)
		goto out_dn;
	ret = q25_cam_get_clks(dn, pd.subsys_clks, ARRAY_SIZE(pd.subsys_clks));
	if (ret)
		goto out_clks;

	mutex_init(&pd.hw_lock);
	pd.genpd.name = "q25-cam";
	pd.genpd.power_on = q25_cam_power_on;
	pd.genpd.power_off = q25_cam_power_off;
	pd.genpd.flags = GENPD_FLAG_NO_STAY_ON;
	ret = pm_genpd_init(&pd.genpd, NULL, true);
	if (ret)
		goto out_subsys;

	pd.domains[MT6789_POWER_DOMAIN_CAM] = &pd.genpd;
	pd.data.domains = pd.domains;
	pd.data.num_domains = ARRAY_SIZE(pd.domains);
	ret = of_genpd_add_provider_onecell(np, &pd.data);
	if (ret) {
		pm_genpd_remove(&pd.genpd);
		goto out_subsys;
	}

	dir = debugfs_create_dir("q25-cam-pd", NULL);
	debugfs_create_file("state", 0400, dir, NULL, &state_fops);
	debugfs_create_file("test_power", 0200, dir, NULL, &test_power_fops);

	pr_info("q25-cam-pd: provider for %pOF index %d, initially off\n",
		dn, MT6789_POWER_DOMAIN_CAM);
	of_node_put(dn);
	of_node_put(np);
	return 0;

out_subsys:
	clk_bulk_put(ARRAY_SIZE(pd.subsys_clks), pd.subsys_clks);
out_clks:
	clk_bulk_put(ARRAY_SIZE(pd.clks), pd.clks);
out_dn:
	of_node_put(dn);
out_np:
	of_node_put(np);
	pr_err("q25-cam-pd: init failed %d\n", ret);
	return ret;
}
module_init(q25_cam_pd_init);

MODULE_DESCRIPTION("Zinwa Q25 MT6789 CAM power domain");
MODULE_LICENSE("GPL");
