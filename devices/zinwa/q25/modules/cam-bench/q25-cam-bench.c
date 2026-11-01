// SPDX-License-Identifier: GPL-2.0-only
/*
 * Camera bench support for the Zinwa Q25 (MT6789) bring-up.
 *
 * With CAM already on, holds the CAM genpd, enables the camera clocks
 * through the CCF, allocates a coherent buffer below 4 GiB for CAMSV and
 * reports whether larb13's CAMSV ports bypass the (absent) IOMMU. Each step
 * is undone from debugfs; the module stays loaded.
 *
 * camsys and larb13 are read only while held and CAM is on: held keeps
 * q25-cam-pd from powering CAM off underneath.
 */
#include <linux/clk.h>
#include <linux/debugfs.h>
#include <linux/dma-mapping.h>
#include <linux/io.h>
#include <linux/mfd/syscon.h>
#include <linux/mm.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/pm_domain.h>
#include <linux/regmap.h>
#include <linux/sizes.h>

#include <dt-bindings/clock/mediatek,mt6789-clk.h>
#include <dt-bindings/power/mediatek,mt6789-power.h>

static bool enable;
module_param(enable, bool, 0444);
MODULE_PARM_DESC(enable, "Run the camera bench setup (default disabled)");

static unsigned int frame_bytes = 1920 * 1080 * 2;
module_param(frame_bytes, uint, 0644);
MODULE_PARM_DESC(frame_bytes, "Bytes filled with 0xa5 at allocation; the rest is the 0x5a guard");

#define PWR_STA			0x16c
#define PWR_STA_2ND		0x170
#define CAM_STA			BIT(23)

#define CAMSYS_BASE		0x1a000000
#define CAMSYS_CG_STA		0x0
#define LARB13_BASE		0x1a001000
#define LARB_NONSEC_CON(p)	(0x380 + 4 * (p))
#define F_MMU_EN		BIT(0)

/* MAX_PAGE_ORDER 10 and no CMA: 4 MiB is the largest contiguous block. */
#define BUF_SIZE		SZ_4M
#define FRAME_FILL		0xa5
#define GUARD_FILL		0x5a

static const unsigned int larb13_ports[] = { 6, 7, 8 };

static const struct {
	bool camsys;
	u32 id;
	const char *name;
} bench_clks[] = {
	{ false, CLK_TOP_CAM_SEL, "cam_sel" },
	{ false, CLK_TOP_CAMTM_SEL, "camtm_sel" },
	{ false, CLK_TOP_SENINF_SEL, "seninf_sel" },
	{ true, CLK_CAM_M_LARB13, "cam_m_larb13" },
	{ true, CLK_CAM_M_CAM, "cam_m_cam" },
	{ true, CLK_CAM_M_CAMTG, "cam_m_camtg" },
	{ true, CLK_CAM_M_SENINF, "cam_m_seninf" },
	{ true, CLK_CAM_M_CAMSV1, "cam_m_camsv1" },
	{ true, CLK_CAM_M_CAMSV2, "cam_m_camsv2" },
	{ true, CLK_CAM_M_CAMSV3, "cam_m_camsv3" },
	{ true, CLK_CAM_M_CAM2MM_GALS, "cam_m_cam2mm_gals" },
};

static struct q25_cam_bench {
	struct platform_device *pdev;
	struct regmap *spm;
	struct of_phandle_args pd_spec;
	void __iomem *camsys;
	void __iomem *larb13;
	struct clk_bulk_data clks[ARRAY_SIZE(bench_clks)];

	/* Serialises the setters; guards held, clks_on, cpu and dma. */
	struct mutex lock;
	bool held;
	bool clks_on;
	void *cpu;
	dma_addr_t dma;
	atomic_t users;
} b;

static bool cam_is_on(void)
{
	u32 a = 0, c = 0;

	regmap_read(b.spm, PWR_STA, &a);
	regmap_read(b.spm, PWR_STA_2ND, &c);
	return (a & CAM_STA) && (c & CAM_STA);
}

static bool camsys_readable(void)
{
	return b.held && cam_is_on();
}

static void larb13_log(void)
{
	int i;

	for (i = 0; i < ARRAY_SIZE(larb13_ports); i++) {
		unsigned int p = larb13_ports[i];
		u32 v = readl(b.larb13 + LARB_NONSEC_CON(p));

		if (v & F_MMU_EN)
			pr_warn("q25-cam-bench: larb13 port %u NONSEC_CON=%#x: MMU_EN set\n", p, v);
		else
			pr_info("q25-cam-bench: larb13 port %u NONSEC_CON=%#x MMU_EN=0\n", p, v);
	}
}

/* All setters run under b.lock. */
static int bench_hold(bool on)
{
	int ret;

	if (on == b.held)
		return 0;
	if (on) {
		if (!cam_is_on()) {
			pr_err("q25-cam-bench: CAM is off; power it with q25-cam-pd first\n");
			return -ENODEV;
		}
		ret = of_genpd_add_device(&b.pd_spec, &b.pdev->dev);
		if (ret) {
			pr_err("q25-cam-bench: CAM genpd attach failed %d\n", ret);
			return ret;
		}
	} else {
		if (b.clks_on) {
			pr_err("q25-cam-bench: clocks on; refusing to release CAM\n");
			return -EBUSY;
		}
		ret = pm_genpd_remove_device(&b.pdev->dev);
		if (ret)
			return ret;
	}
	b.held = on;
	pr_info("q25-cam-bench: CAM %s\n", on ? "held" : "released");
	return 0;
}

static int bench_clocks(bool on)
{
	int ret;

	if (on == b.clks_on)
		return 0;
	if (!camsys_readable()) {
		pr_err("q25-cam-bench: CAM not held and on; clocks unchanged\n");
		return -EBUSY;
	}
	if (on) {
		ret = clk_bulk_prepare_enable(ARRAY_SIZE(b.clks), b.clks);
		if (ret)
			return ret;
	} else {
		clk_bulk_disable_unprepare(ARRAY_SIZE(b.clks), b.clks);
	}
	b.clks_on = on;
	pr_info("q25-cam-bench: clocks %s, CG_STA=%#x\n", on ? "on" : "off",
		readl(b.camsys + CAMSYS_CG_STA));
	if (on)
		larb13_log();
	return 0;
}

static int bench_buffer(bool on)
{
	size_t frame = min_t(size_t, frame_bytes, BUF_SIZE);

	if (!on) {
		if (!b.cpu)
			return 0;
		if (atomic_read(&b.users)) {
			pr_err("q25-cam-bench: buffer in use; not freeing\n");
			return -EBUSY;
		}
		dma_free_coherent(&b.pdev->dev, BUF_SIZE, b.cpu, b.dma);
		b.cpu = NULL;
		pr_info("q25-cam-bench: buffer freed\n");
		return 0;
	}

	if (!b.cpu) {
		b.cpu = dma_alloc_coherent(&b.pdev->dev, BUF_SIZE, &b.dma,
					   GFP_KERNEL | __GFP_NOWARN);
		if (!b.cpu) {
			pr_err("q25-cam-bench: no contiguous %u bytes below 4 GiB\n", BUF_SIZE);
			return -ENOMEM;
		}
	}
	memset(b.cpu, FRAME_FILL, frame);
	memset(b.cpu + frame, GUARD_FILL, BUF_SIZE - frame);
	pr_info("q25-cam-bench: buffer phys=%pad size=%#x frame=%#zx guard=%#zx\n",
		&b.dma, BUF_SIZE, frame, BUF_SIZE - frame);
	return 0;
}

static ssize_t knob_write(const char __user *ubuf, size_t count, int (*set)(bool))
{
	bool on;
	int ret;

	ret = kstrtobool_from_user(ubuf, count, &on);
	if (ret)
		return ret;
	mutex_lock(&b.lock);
	ret = set(on);
	mutex_unlock(&b.lock);
	return ret ? ret : count;
}

static ssize_t hold_write(struct file *file, const char __user *ubuf,
			  size_t count, loff_t *ppos)
{
	return knob_write(ubuf, count, bench_hold);
}

static ssize_t clocks_write(struct file *file, const char __user *ubuf,
			    size_t count, loff_t *ppos)
{
	return knob_write(ubuf, count, bench_clocks);
}

static ssize_t buffer_write(struct file *file, const char __user *ubuf,
			    size_t count, loff_t *ppos)
{
	return knob_write(ubuf, count, bench_buffer);
}

static const struct file_operations hold_fops = {
	.owner = THIS_MODULE,
	.write = hold_write,
	.llseek = noop_llseek,
};

static const struct file_operations clocks_fops = {
	.owner = THIS_MODULE,
	.write = clocks_write,
	.llseek = noop_llseek,
};

static const struct file_operations buffer_fops = {
	.owner = THIS_MODULE,
	.write = buffer_write,
	.llseek = noop_llseek,
};

static int state_show(struct seq_file *s, void *unused)
{
	int i;

	mutex_lock(&b.lock);
	seq_printf(s, "cam_on=%d held=%d clocks=%d\n", cam_is_on(), b.held, b.clks_on);
	if (camsys_readable()) {
		seq_printf(s, "camsys CG_STA=%#x\n", readl(b.camsys + CAMSYS_CG_STA));
		for (i = 0; b.clks_on && i < ARRAY_SIZE(larb13_ports); i++)
			seq_printf(s, "larb13 port %u NONSEC_CON=%#x\n", larb13_ports[i],
				   readl(b.larb13 + LARB_NONSEC_CON(larb13_ports[i])));
	}
	if (b.cpu)
		seq_printf(s, "buffer phys=%pad size=%#x users=%d\n", &b.dma, BUF_SIZE,
			   atomic_read(&b.users));
	else
		seq_puts(s, "buffer none\n");
	mutex_unlock(&b.lock);
	return 0;
}
DEFINE_SHOW_ATTRIBUTE(state);

static int phys_show(struct seq_file *s, void *unused)
{
	mutex_lock(&b.lock);
	if (b.cpu)
		seq_printf(s, "%pad\n", &b.dma);
	mutex_unlock(&b.lock);
	return 0;
}
DEFINE_SHOW_ATTRIBUTE(phys);

static void frame_vm_open(struct vm_area_struct *vma)
{
	atomic_inc(&b.users);
}

static void frame_vm_close(struct vm_area_struct *vma)
{
	atomic_dec(&b.users);
}

static const struct vm_operations_struct frame_vm_ops = {
	.open = frame_vm_open,
	.close = frame_vm_close,
};

static int frame_mmap(struct file *file, struct vm_area_struct *vma)
{
	int ret = -ENOMEM;

	mutex_lock(&b.lock);
	if (b.cpu) {
		ret = dma_mmap_coherent(&b.pdev->dev, vma, b.cpu, b.dma, BUF_SIZE);
		if (!ret) {
			vma->vm_ops = &frame_vm_ops;
			atomic_inc(&b.users);
		}
	}
	mutex_unlock(&b.lock);
	return ret;
}

static ssize_t frame_read(struct file *file, char __user *ubuf, size_t count,
			  loff_t *ppos)
{
	void *cpu;
	ssize_t ret;

	/* No b.lock across the copy: mmap takes it under mmap_lock. */
	mutex_lock(&b.lock);
	cpu = b.cpu;
	if (cpu)
		atomic_inc(&b.users);
	mutex_unlock(&b.lock);
	if (!cpu)
		return -ENOMEM;
	ret = simple_read_from_buffer(ubuf, count, ppos, cpu, BUF_SIZE);
	atomic_dec(&b.users);
	return ret;
}

static const struct file_operations frame_fops = {
	.owner = THIS_MODULE,
	.read = frame_read,
	.mmap = frame_mmap,
	.llseek = default_llseek,
};

static int bench_get_clks(void)
{
	struct device_node *top, *cam;
	struct of_phandle_args args = { .args_count = 1 };
	int i, ret = 0;

	top = of_find_compatible_node(NULL, NULL, "mediatek,mt6789-topckgen");
	cam = of_find_compatible_node(NULL, NULL, "mediatek,mt6789-camsys");
	if (!top || !cam) {
		ret = -ENODEV;
		goto out;
	}
	for (i = 0; i < ARRAY_SIZE(bench_clks); i++) {
		args.np = bench_clks[i].camsys ? cam : top;
		args.args[0] = bench_clks[i].id;
		b.clks[i].id = bench_clks[i].name;
		b.clks[i].clk = of_clk_get_from_provider(&args);
		if (IS_ERR(b.clks[i].clk)) {
			ret = PTR_ERR(b.clks[i].clk);
			pr_err("q25-cam-bench: clock %s: %d\n", bench_clks[i].name, ret);
			clk_bulk_put(i, b.clks);
			break;
		}
	}
out:
	of_node_put(cam);
	of_node_put(top);
	return ret;
}

static int __init q25_cam_bench_init(void)
{
	struct device_node *np;
	struct dentry *dir;
	int ret;

	if (!enable) {
		pr_err("q25-cam-bench: review gate: enable=1 required\n");
		return -EPERM;
	}

	np = of_find_compatible_node(NULL, NULL, "mediatek,mt6789-power-controller");
	if (!np)
		return -ENODEV;
	b.spm = syscon_node_to_regmap(np->parent);
	if (IS_ERR(b.spm)) {
		ret = PTR_ERR(b.spm);
		goto out_np;
	}
	if (!cam_is_on()) {
		pr_err("q25-cam-bench: CAM is off; refusing\n");
		ret = -ENODEV;
		goto out_np;
	}
	b.pd_spec.np = np;
	b.pd_spec.args_count = 1;
	b.pd_spec.args[0] = MT6789_POWER_DOMAIN_CAM;

	ret = bench_get_clks();
	if (ret)
		goto out_np;

	b.camsys = ioremap(CAMSYS_BASE, SZ_4K);
	b.larb13 = ioremap(LARB13_BASE, SZ_4K);
	if (!b.camsys || !b.larb13) {
		ret = -ENOMEM;
		goto out_unmap;
	}

	b.pdev = platform_device_alloc("q25-cam-bench", PLATFORM_DEVID_NONE);
	if (!b.pdev) {
		ret = -ENOMEM;
		goto out_unmap;
	}
	/* No system-sleep callbacks: genpd must never resume CAM for it. */
	device_set_pm_not_required(&b.pdev->dev);
	ret = platform_device_add(b.pdev);
	if (ret) {
		platform_device_put(b.pdev);
		goto out_unmap;
	}
	ret = dma_set_mask_and_coherent(&b.pdev->dev, DMA_BIT_MASK(32));
	if (ret)
		goto out_pdev;

	mutex_init(&b.lock);
	mutex_lock(&b.lock);
	ret = bench_hold(true);
	if (!ret)
		ret = bench_clocks(true);
	if (!ret)
		ret = bench_buffer(true);
	if (ret) {
		bench_buffer(false);
		bench_clocks(false);
		bench_hold(false);
	}
	mutex_unlock(&b.lock);
	if (ret)
		goto out_pdev;

	dir = debugfs_create_dir("q25-cam-bench", NULL);
	debugfs_create_file("state", 0400, dir, NULL, &state_fops);
	debugfs_create_file("phys", 0400, dir, NULL, &phys_fops);
	debugfs_create_file("hold", 0200, dir, NULL, &hold_fops);
	debugfs_create_file("clocks", 0200, dir, NULL, &clocks_fops);
	debugfs_create_file("buffer", 0200, dir, NULL, &buffer_fops);
	/* The full proxy does not forward mmap; the module never unloads. */
	debugfs_create_file_unsafe("frame", 0400, dir, NULL, &frame_fops);

	pr_info("q25-cam-bench: ready\n");
	return 0;

out_pdev:
	platform_device_unregister(b.pdev);
out_unmap:
	if (b.larb13)
		iounmap(b.larb13);
	if (b.camsys)
		iounmap(b.camsys);
	clk_bulk_put(ARRAY_SIZE(b.clks), b.clks);
out_np:
	of_node_put(np);
	pr_err("q25-cam-bench: init failed %d\n", ret);
	return ret;
}
module_init(q25_cam_bench_init);

MODULE_DESCRIPTION("Zinwa Q25 MT6789 camera bench clocks and frame buffer");
MODULE_LICENSE("GPL");
