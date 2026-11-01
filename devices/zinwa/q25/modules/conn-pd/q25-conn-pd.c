// SPDX-License-Identifier: GPL-2.0-only
/*
 * MT6789 CONN (connsys) power domain and CONN MCU reset for the Zinwa Q25.
 *
 * Same arrangement as q25-audio-pd: the SPM power-controller node is owned
 * by q25-mfg-only-v2 (MFG only); this registers a further genpd provider on
 * that node resolving only MT6789_POWER_DOMAIN_CONN (1). Providers whose
 * xlate fails are skipped, so the three never answer for each other.
 *
 * Data: stock mtk-scpsys-mt6789.c (LineageOS android_kernel_xelex_mt6789
 * 2a873a35): CONN ctl 0x304, sta bit 1 in 0x16c and 0x170, no SRAM, no
 * domain clocks, bus protect (infracfg) 13|18 then 14 via 0x2a0/0x2a4 sta
 * 0x228, then 10 via 0x2a8/0x2ac sta 0x258, clear-ack ignored.
 * Sequence: stock scpsys_power_on/off.
 *
 * The CONN MCU sits behind TOPRGU WDT_SWSYSRST bit 12. mtk-wdt binds the
 * toprgu node through the mt6589 fallback without reset data, so this also
 * registers a reset controller on that node exposing only bit 12.
 */
#include <linux/debugfs.h>
#include <linux/delay.h>
#include <linux/io.h>
#include <linux/iopoll.h>
#include <linux/mfd/syscon.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_address.h>
#include <linux/pm_domain.h>
#include <linux/regmap.h>
#include <linux/reset-controller.h>
#include <linux/spinlock.h>

#include <dt-bindings/power/mediatek,mt6789-power.h>

#define PWR_STA			0x16c
#define PWR_STA_2ND		0x170
#define CONN_PWR_CON		0x304
#define CONN_STA_MASK		BIT(1)

#define PWR_RST_B		BIT(0)
#define PWR_ISO			BIT(1)
#define PWR_ON			BIT(2)
#define PWR_ON_2ND		BIT(3)
#define PWR_CLK_DIS		BIT(4)

#define POLL_US			10
#define TIMEOUT_US		USEC_PER_SEC

#define WDT_SWSYSRST		0x18
#define WDT_SWSYS_KEY		0x88000000
#define TOPRGU_CONN_MCU		12

struct conn_bp {
	u32 set, clr, sta, mask;
};

/* Order as stock: set 0..2 on power-off, clear 2..0 on power-on. */
static const struct conn_bp conn_bp[] = {
	{ 0x2a0, 0x2a4, 0x228, BIT(13) | BIT(18) },
	{ 0x2a0, 0x2a4, 0x228, BIT(14) },
	{ 0x2a8, 0x2ac, 0x258, BIT(10) },
};

static struct q25_conn_pd {
	struct generic_pm_domain genpd;
	struct regmap *spm;
	struct regmap *infra;
	struct generic_pm_domain *domains[MT6789_POWER_DOMAIN_CONN + 1];
	struct genpd_onecell_data data;

	void __iomem *toprgu;
	spinlock_t rst_lock;
	struct reset_controller_dev rcdev;

	/*
	 * hw_lock serialises every CONN power sequence. genpd_on: the domain
	 * is on for genpd consumers; test_on: on for the debugfs test only.
	 * The two never overlap.
	 */
	struct mutex hw_lock;
	bool genpd_on;
	bool test_on;
} pd;

static bool conn_is_on(void)
{
	u32 a = 0, b = 0;

	regmap_read(pd.spm, PWR_STA, &a);
	regmap_read(pd.spm, PWR_STA_2ND, &b);
	return (a & CONN_STA_MASK) && (b & CONN_STA_MASK);
}

static bool conn_is_off(void)
{
	u32 a = 0, b = 0;

	regmap_read(pd.spm, PWR_STA, &a);
	regmap_read(pd.spm, PWR_STA_2ND, &b);
	return !(a & CONN_STA_MASK) && !(b & CONN_STA_MASK);
}

static void conn_bp_clear(int from)
{
	for (; from >= 0; from--)
		regmap_write(pd.infra, conn_bp[from].clr, conn_bp[from].mask);
}

static int conn_bp_set(void)
{
	unsigned int tmp;
	int i, ret;

	for (i = 0; i < ARRAY_SIZE(conn_bp); i++) {
		regmap_write(pd.infra, conn_bp[i].set, conn_bp[i].mask);
		ret = regmap_read_poll_timeout(pd.infra, conn_bp[i].sta, tmp,
					       (tmp & conn_bp[i].mask) == conn_bp[i].mask,
					       POLL_US, TIMEOUT_US);
		if (ret) {
			pr_err("q25-conn-pd: bus protect %d no ack, sta=%#x\n", i, tmp);
			conn_bp_clear(i);
			return ret;
		}
	}
	return 0;
}

static void conn_step(const char *step)
{
	unsigned int con = 0, a = 0, b = 0;

	regmap_read(pd.spm, CONN_PWR_CON, &con);
	regmap_read(pd.spm, PWR_STA, &a);
	regmap_read(pd.spm, PWR_STA_2ND, &b);
	pr_info("q25-conn-pd: %s: PWR_CON=%#x sta=%d sta2nd=%d\n", step, con,
		!!(a & CONN_STA_MASK), !!(b & CONN_STA_MASK));
}

/* Stock scpsys_power_on() for CONN. Caller holds hw_lock. */
static int conn_hw_on(void)
{
	unsigned int tmp;
	bool on;
	int ret;

	conn_step("on: start");
	regmap_set_bits(pd.spm, CONN_PWR_CON, PWR_ON);
	conn_step("on: PWR_ON");
	regmap_set_bits(pd.spm, CONN_PWR_CON, PWR_ON_2ND);
	conn_step("on: PWR_ON_2ND");
	ret = readx_poll_timeout(conn_is_on, , on, on, POLL_US, TIMEOUT_US);
	if (ret)
		goto err;
	conn_step("on: ack");

	udelay(100);
	regmap_clear_bits(pd.spm, CONN_PWR_CON, PWR_CLK_DIS);
	conn_step("on: CLK_DIS=0");
	regmap_clear_bits(pd.spm, CONN_PWR_CON, PWR_ISO);
	conn_step("on: ISO=0");
	regmap_set_bits(pd.spm, CONN_PWR_CON, PWR_RST_B);
	conn_step("on: RST_B=1");

	conn_bp_clear(ARRAY_SIZE(conn_bp) - 1);
	regmap_read(pd.infra, 0x228, &tmp);
	pr_info("q25-conn-pd: on: bus protect released, sta1=%#x\n", tmp);
	conn_step("conn on");
	return 0;

err:
	/* Undo the request so the domain is not left half-on. */
	regmap_clear_bits(pd.spm, CONN_PWR_CON, PWR_ON_2ND);
	regmap_clear_bits(pd.spm, CONN_PWR_CON, PWR_ON);
	conn_step("on: FAILED, request withdrawn");
	pr_err("q25-conn-pd: power on failed %d\n", ret);
	return ret;
}

/* Stock scpsys_power_off() for CONN. Caller holds hw_lock. */
static int conn_hw_off(void)
{
	bool off;
	int ret;

	conn_step("off: start");
	ret = conn_bp_set();
	if (ret)
		return ret;
	conn_step("off: bus protect set");

	regmap_set_bits(pd.spm, CONN_PWR_CON, PWR_ISO);
	regmap_clear_bits(pd.spm, CONN_PWR_CON, PWR_RST_B);
	regmap_set_bits(pd.spm, CONN_PWR_CON, PWR_CLK_DIS);
	conn_step("off: ISO=1 RST_B=0 CLK_DIS=1");
	regmap_clear_bits(pd.spm, CONN_PWR_CON, PWR_ON);
	regmap_clear_bits(pd.spm, CONN_PWR_CON, PWR_ON_2ND);
	ret = readx_poll_timeout(conn_is_off, , off, off, POLL_US, TIMEOUT_US);
	if (ret) {
		conn_step("off: FAILED, no status ack");
		return ret;
	}
	conn_step("conn off");
	return 0;
}

static int q25_conn_power_on(struct generic_pm_domain *genpd)
{
	int ret;

	mutex_lock(&pd.hw_lock);
	if (pd.test_on) {
		pr_err("q25-conn-pd: debugfs test holds CONN, refusing genpd power on\n");
		ret = -EBUSY;
	} else {
		ret = conn_hw_on();
		pd.genpd_on = !ret;
	}
	mutex_unlock(&pd.hw_lock);
	return ret;
}

static int q25_conn_power_off(struct generic_pm_domain *genpd)
{
	int ret;

	mutex_lock(&pd.hw_lock);
	ret = conn_hw_off();
	if (!ret)
		pd.genpd_on = false;
	mutex_unlock(&pd.hw_lock);
	return ret;
}

/* TOPRGU reset: only the CONN MCU line exists for consumers. */
static int toprgu_update(struct reset_controller_dev *rcdev, unsigned long id,
			 bool assert)
{
	unsigned long flags;
	u32 val;

	spin_lock_irqsave(&pd.rst_lock, flags);
	val = readl(pd.toprgu + WDT_SWSYSRST) & 0x00ffffff;
	if (assert)
		val |= BIT(id);
	else
		val &= ~BIT(id);
	writel(val | WDT_SWSYS_KEY, pd.toprgu + WDT_SWSYSRST);
	spin_unlock_irqrestore(&pd.rst_lock, flags);
	return 0;
}

static int toprgu_assert(struct reset_controller_dev *rcdev, unsigned long id)
{
	return toprgu_update(rcdev, id, true);
}

static int toprgu_deassert(struct reset_controller_dev *rcdev, unsigned long id)
{
	return toprgu_update(rcdev, id, false);
}

static int toprgu_status(struct reset_controller_dev *rcdev, unsigned long id)
{
	return !!(readl(pd.toprgu + WDT_SWSYSRST) & BIT(id));
}

static const struct reset_control_ops toprgu_ops = {
	.assert = toprgu_assert,
	.deassert = toprgu_deassert,
	.status = toprgu_status,
};

static int toprgu_xlate(struct reset_controller_dev *rcdev,
			const struct of_phandle_args *args)
{
	if (args->args[0] != TOPRGU_CONN_MCU)
		return -EINVAL;
	return TOPRGU_CONN_MCU;
}

static int q25_toprgu_reset_init(void)
{
	struct device_node *np;
	int ret;

	np = of_find_compatible_node(NULL, NULL, "mediatek,mt6789-wdt");
	if (!np)
		return -ENODEV;
	if (!of_property_present(np, "#reset-cells")) {
		pr_info("q25-conn-pd: %pOF has no #reset-cells, CONN MCU reset not provided\n", np);
		of_node_put(np);
		return 0;
	}

	/* mtk-wdt owns the region; map only, it never touches SWSYSRST here. */
	pd.toprgu = of_iomap(np, 0);
	if (!pd.toprgu) {
		of_node_put(np);
		return -ENOMEM;
	}
	spin_lock_init(&pd.rst_lock);
	pd.rcdev.owner = THIS_MODULE;
	pd.rcdev.ops = &toprgu_ops;
	pd.rcdev.of_node = np;
	pd.rcdev.of_reset_n_cells = 1;
	pd.rcdev.of_xlate = toprgu_xlate;
	pd.rcdev.nr_resets = 32;
	ret = reset_controller_register(&pd.rcdev);
	if (ret) {
		iounmap(pd.toprgu);
		pd.toprgu = NULL;
		of_node_put(np);
		return ret;
	}
	pr_info("q25-conn-pd: CONN MCU reset on %pOF bit %d (now %s)\n", np,
		TOPRGU_CONN_MCU, toprgu_status(&pd.rcdev, TOPRGU_CONN_MCU) ?
		"asserted" : "released");
	return 0;
}

/*
 * debugfs: stand-alone CONN power test, like the audio domain test. It runs
 * the same hardware sequence as the genpd callbacks, directly and only when
 * no genpd consumer is attached and the domain is off. While it holds CONN,
 * genpd power-on is refused, and the CONN MCU is held in reset.
 */
static int state_show(struct seq_file *s, void *unused)
{
	u32 con = 0, a = 0, b = 0, s1 = 0, s11 = 0;

	regmap_read(pd.spm, CONN_PWR_CON, &con);
	regmap_read(pd.spm, PWR_STA, &a);
	regmap_read(pd.spm, PWR_STA_2ND, &b);
	regmap_read(pd.infra, 0x228, &s1);
	regmap_read(pd.infra, 0x258, &s11);
	seq_printf(s, "PWR_CON=%#x sta=%d sta2nd=%d bp_sta1=%#x bp_sta1_1=%#x\n",
		   con, !!(a & CONN_STA_MASK), !!(b & CONN_STA_MASK),
		   s1 & (u32)(BIT(13) | BIT(14) | BIT(18)), s11 & (u32)BIT(10));
	seq_printf(s, "genpd consumers=%d genpd_on=%d test_on=%d mcu_reset=%s\n",
		   pd.genpd.device_count, pd.genpd_on, pd.test_on,
		   pd.toprgu ? (toprgu_status(&pd.rcdev, TOPRGU_CONN_MCU) ?
				"asserted" : "released") : "n/a");
	return 0;
}
DEFINE_SHOW_ATTRIBUTE(state);

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
	} else if (on) {
		/* Never under or beside a real consumer (WMT). */
		if (pd.genpd.device_count || pd.genpd_on ||
		    pd.genpd.status != GENPD_STATE_OFF) {
			pr_err("q25-conn-pd: test refused: genpd consumers=%d on=%d\n",
			       pd.genpd.device_count, pd.genpd_on);
			ret = -EBUSY;
		} else {
			if (pd.toprgu)
				toprgu_assert(&pd.rcdev, TOPRGU_CONN_MCU);
			ret = conn_hw_on();
			if (ret) {
				if (pd.toprgu)
					toprgu_deassert(&pd.rcdev, TOPRGU_CONN_MCU);
			} else {
				pd.test_on = true;
			}
		}
	} else {
		ret = conn_hw_off();
		if (!ret) {
			if (pd.toprgu)
				toprgu_deassert(&pd.rcdev, TOPRGU_CONN_MCU);
			pd.test_on = false;
		}
	}
	mutex_unlock(&pd.hw_lock);
	return ret ? ret : count;
}

static const struct file_operations test_power_fops = {
	.owner = THIS_MODULE,
	.write = test_power_write,
	.llseek = noop_llseek,
};

static void q25_conn_test_init(void)
{
	struct dentry *dir = debugfs_create_dir("q25-conn-pd", NULL);

	debugfs_create_file("state", 0400, dir, NULL, &state_fops);
	debugfs_create_file("test_power", 0200, dir, NULL, &test_power_fops);
}

static int __init q25_conn_pd_init(void)
{
	struct device_node *np, *child, *dn = NULL;
	u32 reg;
	int ret;

	np = of_find_compatible_node(NULL, NULL, "mediatek,mt6789-power-controller");
	if (!np)
		return -ENODEV;

	for_each_child_of_node(np, child) {
		if (!of_property_read_u32(child, "reg", &reg) &&
		    reg == MT6789_POWER_DOMAIN_CONN) {
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

	/* Expected off at boot (PWR_CON 0x12). Anything half-on is refused. */
	if (!conn_is_on() && !conn_is_off()) {
		regmap_read(pd.spm, CONN_PWR_CON, &reg);
		pr_err("q25-conn-pd: CONN status inconsistent, PWR_CON=%#x\n", reg);
		ret = -EIO;
		goto out_dn;
	}

	mutex_init(&pd.hw_lock);
	pd.genpd.name = "q25-conn";
	pd.genpd.power_on = q25_conn_power_on;
	pd.genpd.power_off = q25_conn_power_off;
	pd.genpd.flags = GENPD_FLAG_NO_STAY_ON;
	pd.genpd_on = conn_is_on();
	ret = pm_genpd_init(&pd.genpd, NULL, !pd.genpd_on);
	if (ret)
		goto out_dn;

	pd.domains[MT6789_POWER_DOMAIN_CONN] = &pd.genpd;
	pd.data.domains = pd.domains;
	pd.data.num_domains = ARRAY_SIZE(pd.domains);
	ret = of_genpd_add_provider_onecell(np, &pd.data);
	if (ret) {
		pm_genpd_remove(&pd.genpd);
		goto out_dn;
	}

	/* No unwind exists for a registered provider; reset is optional. */
	ret = q25_toprgu_reset_init();
	if (ret)
		pr_err("q25-conn-pd: CONN MCU reset unavailable: %d\n", ret);

	q25_conn_test_init();

	regmap_read(pd.spm, CONN_PWR_CON, &reg);
	pr_info("q25-conn-pd: provider for %pOF index %d, initially %s, PWR_CON=%#x\n",
		dn, MT6789_POWER_DOMAIN_CONN, conn_is_on() ? "on" : "off", reg);
	of_node_put(dn);
	of_node_put(np);
	return 0;

out_dn:
	of_node_put(dn);
out_np:
	of_node_put(np);
	pr_err("q25-conn-pd: init failed %d\n", ret);
	return ret;
}
module_init(q25_conn_pd_init);

MODULE_DESCRIPTION("Zinwa Q25 MT6789 CONN power domain and CONN MCU reset");
MODULE_LICENSE("GPL");
