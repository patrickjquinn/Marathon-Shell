// SPDX-License-Identifier: GPL-2.0-only

#include <linux/aperture.h>
#include <linux/clk.h>
#include <linux/delay.h>
#include <linux/hrtimer.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/minmax.h>
#include <linux/of_address.h>
#include <linux/of_clk.h>
#include <linux/of_irq.h>
#include <linux/of_reserved_mem.h>
#include <linux/platform_data/simplefb.h>
#include <linux/platform_device.h>
#include <linux/pm_domain.h>
#include <linux/regulator/consumer.h>

#include <drm/clients/drm_client_setup.h>
#include <drm/drm_atomic.h>
#include <drm/drm_atomic_state_helper.h>
#include <drm/drm_connector.h>
#include <drm/drm_damage_helper.h>
#include <drm/drm_device.h>
#include <drm/drm_drv.h>
#include <drm/drm_fbdev_shmem.h>
#include <drm/drm_framebuffer.h>
#include <drm/drm_gem_atomic_helper.h>
#include <drm/drm_gem_framebuffer_helper.h>
#include <drm/drm_gem_shmem_helper.h>
#include <drm/drm_managed.h>
#include <drm/drm_modeset_helper_vtables.h>
#include <drm/drm_print.h>
#include <drm/drm_probe_helper.h>
#include <drm/drm_vblank.h>

#include "drm_sysfb_helper.h"

/* Mesa's loader and the shell key on the DRM driver name, so it stays "simpledrm". */
#define DRIVER_NAME	"simpledrm"
#define DRIVER_DESC	"simpledrm with Q25 scan-locked vblank"

/*
 * The firmware leaves the MT6789 OVL->RDMA->DSI pipeline scanning the framebuffer
 * in DSI video mode. RDMA's output line counter runs 1..vact through the active
 * area, holds vact through the front porch and reads 0 through sync and back
 * porch, which gives the scan position to a line.
 */
#define DSI_INTEN		0x08
#define DSI_INTSTA		0x0c
#define DSI_FRAME_DONE		BIT(4)
#define DSI_MODE_CTRL		0x14
#define DSI_VSA_NL		0x20
#define DSI_VBP_NL		0x24
#define DSI_VFP_NL		0x28
#define DSI_VACT_NL		0x2c
#define DSI_HSA_WC		0x50
#define DSI_HBP_WC		0x54
#define DSI_HFP_WC		0x58
#define RDMA_OUT_LINE_CNT	0x12c
#define Q25_LEAD_LINES		16	/* wake this far ahead of the front porch */
#define Q25_FETCH_LINES		16	/* rows fetched ahead of the counter */
#define Q25_PERIOD_FRAMES	16

static bool use_irq;
module_param(use_irq, bool, 0444);
MODULE_PARM_DESC(use_irq, "Signal vblank from the DSI FRAME_DONE interrupt (writes DSI_INTEN/INTSTA)");
#define DRIVER_MAJOR	1
#define DRIVER_MINOR	0

/*
 * Helpers for simplefb
 */

static int
simplefb_get_validated_int(struct drm_device *dev, const char *name,
			   uint32_t value)
{
	return drm_sysfb_get_validated_int(dev, name, value, INT_MAX);
}

static int
simplefb_get_validated_int0(struct drm_device *dev, const char *name,
			    uint32_t value)
{
	return drm_sysfb_get_validated_int0(dev, name, value, INT_MAX);
}

static const struct drm_format_info *
simplefb_get_validated_format(struct drm_device *dev, const char *format_name)
{
	static const struct simplefb_format formats[] = SIMPLEFB_FORMATS;
	const struct simplefb_format *fmt = formats;
	const struct simplefb_format *end = fmt + ARRAY_SIZE(formats);
	const struct drm_format_info *info;

	if (!format_name) {
		drm_err(dev, "simplefb: missing framebuffer format\n");
		return ERR_PTR(-EINVAL);
	}

	while (fmt < end) {
		if (!strcmp(format_name, fmt->name)) {
			info = drm_format_info(fmt->fourcc);
			if (!info)
				return ERR_PTR(-EINVAL);
			return info;
		}
		++fmt;
	}

	drm_err(dev, "simplefb: unknown framebuffer format %s\n",
		format_name);

	return ERR_PTR(-EINVAL);
}

static int
simplefb_get_width_pd(struct drm_device *dev,
		      const struct simplefb_platform_data *pd)
{
	return simplefb_get_validated_int0(dev, "width", pd->width);
}

static int
simplefb_get_height_pd(struct drm_device *dev,
		       const struct simplefb_platform_data *pd)
{
	return simplefb_get_validated_int0(dev, "height", pd->height);
}

static int
simplefb_get_stride_pd(struct drm_device *dev,
		       const struct simplefb_platform_data *pd)
{
	return simplefb_get_validated_int(dev, "stride", pd->stride);
}

static const struct drm_format_info *
simplefb_get_format_pd(struct drm_device *dev,
		       const struct simplefb_platform_data *pd)
{
	return simplefb_get_validated_format(dev, pd->format);
}

static int
simplefb_read_u32_of(struct drm_device *dev, struct device_node *of_node,
		     const char *name, u32 *value)
{
	int ret = of_property_read_u32(of_node, name, value);

	if (ret)
		drm_err(dev, "simplefb: cannot parse framebuffer %s: error %d\n",
			name, ret);
	return ret;
}

static int
simplefb_read_string_of(struct drm_device *dev, struct device_node *of_node,
			const char *name, const char **value)
{
	int ret = of_property_read_string(of_node, name, value);

	if (ret)
		drm_err(dev, "simplefb: cannot parse framebuffer %s: error %d\n",
			name, ret);
	return ret;
}

static int
simplefb_get_width_of(struct drm_device *dev, struct device_node *of_node)
{
	u32 width;
	int ret = simplefb_read_u32_of(dev, of_node, "width", &width);

	if (ret)
		return ret;
	return simplefb_get_validated_int0(dev, "width", width);
}

static int
simplefb_get_height_of(struct drm_device *dev, struct device_node *of_node)
{
	u32 height;
	int ret = simplefb_read_u32_of(dev, of_node, "height", &height);

	if (ret)
		return ret;
	return simplefb_get_validated_int0(dev, "height", height);
}

static int
simplefb_get_stride_of(struct drm_device *dev, struct device_node *of_node)
{
	u32 stride;
	int ret = simplefb_read_u32_of(dev, of_node, "stride", &stride);

	if (ret)
		return ret;
	return simplefb_get_validated_int(dev, "stride", stride);
}

static const struct drm_format_info *
simplefb_get_format_of(struct drm_device *dev, struct device_node *of_node)
{
	const char *format;
	int ret = simplefb_read_string_of(dev, of_node, "format", &format);

	if (ret)
		return ERR_PTR(ret);
	return simplefb_get_validated_format(dev, format);
}

static struct resource *
simplefb_get_memory_of(struct drm_device *dev, struct device_node *of_node)
{
	struct resource r, *res;
	int err;

	err = of_reserved_mem_region_to_resource(of_node, 0, &r);
	if (err)
		return NULL;

	res = devm_kmemdup(dev->dev, &r, sizeof(r), GFP_KERNEL);
	if (!res)
		return ERR_PTR(-ENOMEM);

	if (of_property_present(of_node, "reg"))
		drm_warn(dev, "preferring \"memory-region\" over \"reg\" property\n");

	return res;
}

/*
 * Simple Framebuffer device
 */

struct simpledrm_device {
	struct drm_sysfb_device sysfb;

	/* clocks */
#if defined CONFIG_OF && defined CONFIG_COMMON_CLK
	unsigned int clk_count;
	struct clk **clks;
#endif
	/* regulators */
#if defined CONFIG_OF && defined CONFIG_REGULATOR
	unsigned int regulator_count;
	struct regulator **regulators;
#endif
	/* power-domains */
#if defined CONFIG_OF && defined CONFIG_PM_GENERIC_DOMAINS
	int pwr_dom_count;
	struct device **pwr_dom_devs;
	struct device_link **pwr_dom_links;
#endif

	/* modesetting */
	u32 formats[DRM_SYSFB_PLANE_NFORMATS(1)];
	struct drm_plane primary_plane;
	struct drm_crtc crtc;
	struct drm_encoder encoder;
	struct drm_connector connector;

	/* scan timing */
	void __iomem *dsi;
	void __iomem *rdma;
	int dsi_irq;
	unsigned int vact;
	u64 period_ns, line_ns, lead_ns, blank_ns;
	struct hrtimer vbl_timer;
	spinlock_t vbl_lock;	/* guards vbl_ts */
	ktime_t vbl_ts;		/* first active line of the last signalled frame */
	ktime_t next_vbl;	/* predicted start of the next front porch */
	ktime_t last_blit;
};

static struct simpledrm_device *to_simpledrm_device(struct drm_device *dev)
{
	return container_of(to_drm_sysfb_device(dev), struct simpledrm_device, sysfb);
}

/*
 * Hardware
 */

#if defined CONFIG_OF && defined CONFIG_COMMON_CLK
/*
 * Clock handling code.
 *
 * Here we handle the clocks property of our "simple-framebuffer" dt node.
 * This is necessary so that we can make sure that any clocks needed by
 * the display engine that the bootloader set up for us (and for which it
 * provided a simplefb dt node), stay up, for the life of the simplefb
 * driver.
 *
 * When the driver unloads, we cleanly disable, and then release the clocks.
 *
 * We only complain about errors here, no action is taken as the most likely
 * error can only happen due to a mismatch between the bootloader which set
 * up simplefb, and the clock definitions in the device tree. Chances are
 * that there are no adverse effects, and if there are, a clean teardown of
 * the fb probe will not help us much either. So just complain and carry on,
 * and hope that the user actually gets a working fb at the end of things.
 */

static void simpledrm_device_release_clocks(void *res)
{
	struct simpledrm_device *sdev = res;
	unsigned int i;

	for (i = 0; i < sdev->clk_count; ++i) {
		if (sdev->clks[i]) {
			clk_disable_unprepare(sdev->clks[i]);
			clk_put(sdev->clks[i]);
		}
	}
}

static int simpledrm_device_init_clocks(struct simpledrm_device *sdev)
{
	struct drm_device *dev = &sdev->sysfb.dev;
	struct platform_device *pdev = to_platform_device(dev->dev);
	struct device_node *of_node = pdev->dev.of_node;
	struct clk *clock;
	unsigned int i;
	int ret;

	if (dev_get_platdata(&pdev->dev) || !of_node)
		return 0;

	sdev->clk_count = of_clk_get_parent_count(of_node);
	if (!sdev->clk_count)
		return 0;

	sdev->clks = drmm_kzalloc(dev, sdev->clk_count * sizeof(sdev->clks[0]),
				  GFP_KERNEL);
	if (!sdev->clks)
		return -ENOMEM;

	for (i = 0; i < sdev->clk_count; ++i) {
		clock = of_clk_get(of_node, i);
		if (IS_ERR(clock)) {
			ret = PTR_ERR(clock);
			if (ret == -EPROBE_DEFER)
				goto err;
			drm_err(dev, "clock %u not found: %d\n", i, ret);
			continue;
		}
		ret = clk_prepare_enable(clock);
		if (ret) {
			drm_err(dev, "failed to enable clock %u: %d\n",
				i, ret);
			clk_put(clock);
			continue;
		}
		sdev->clks[i] = clock;
	}

	return devm_add_action_or_reset(&pdev->dev,
					simpledrm_device_release_clocks,
					sdev);

err:
	while (i) {
		--i;
		if (sdev->clks[i]) {
			clk_disable_unprepare(sdev->clks[i]);
			clk_put(sdev->clks[i]);
		}
	}
	return ret;
}
#else
static int simpledrm_device_init_clocks(struct simpledrm_device *sdev)
{
	return 0;
}
#endif

#if defined CONFIG_OF && defined CONFIG_REGULATOR

#define SUPPLY_SUFFIX "-supply"

/*
 * Regulator handling code.
 *
 * Here we handle the num-supplies and vin*-supply properties of our
 * "simple-framebuffer" dt node. This is necessary so that we can make sure
 * that any regulators needed by the display hardware that the bootloader
 * set up for us (and for which it provided a simplefb dt node), stay up,
 * for the life of the simplefb driver.
 *
 * When the driver unloads, we cleanly disable, and then release the
 * regulators.
 *
 * We only complain about errors here, no action is taken as the most likely
 * error can only happen due to a mismatch between the bootloader which set
 * up simplefb, and the regulator definitions in the device tree. Chances are
 * that there are no adverse effects, and if there are, a clean teardown of
 * the fb probe will not help us much either. So just complain and carry on,
 * and hope that the user actually gets a working fb at the end of things.
 */

static void simpledrm_device_release_regulators(void *res)
{
	struct simpledrm_device *sdev = res;
	unsigned int i;

	for (i = 0; i < sdev->regulator_count; ++i) {
		if (sdev->regulators[i]) {
			regulator_disable(sdev->regulators[i]);
			regulator_put(sdev->regulators[i]);
		}
	}
}

static int simpledrm_device_init_regulators(struct simpledrm_device *sdev)
{
	struct drm_device *dev = &sdev->sysfb.dev;
	struct platform_device *pdev = to_platform_device(dev->dev);
	struct device_node *of_node = pdev->dev.of_node;
	struct property *prop;
	struct regulator *regulator;
	const char *p;
	unsigned int count = 0, i = 0;
	int ret;

	if (dev_get_platdata(&pdev->dev) || !of_node)
		return 0;

	/* Count the number of regulator supplies */
	for_each_property_of_node(of_node, prop) {
		p = strstr(prop->name, SUPPLY_SUFFIX);
		if (p && p != prop->name)
			++count;
	}

	if (!count)
		return 0;

	sdev->regulators = drmm_kzalloc(dev,
					count * sizeof(sdev->regulators[0]),
					GFP_KERNEL);
	if (!sdev->regulators)
		return -ENOMEM;

	for_each_property_of_node(of_node, prop) {
		char name[32]; /* 32 is max size of property name */
		size_t len;

		p = strstr(prop->name, SUPPLY_SUFFIX);
		if (!p || p == prop->name)
			continue;
		len = strlen(prop->name) - strlen(SUPPLY_SUFFIX) + 1;
		strscpy(name, prop->name, min(sizeof(name), len));

		regulator = regulator_get_optional(&pdev->dev, name);
		if (IS_ERR(regulator)) {
			ret = PTR_ERR(regulator);
			if (ret == -EPROBE_DEFER)
				goto err;
			drm_err(dev, "regulator %s not found: %d\n",
				name, ret);
			continue;
		}

		ret = regulator_enable(regulator);
		if (ret) {
			drm_err(dev, "failed to enable regulator %u: %d\n",
				i, ret);
			regulator_put(regulator);
			continue;
		}

		sdev->regulators[i++] = regulator;
	}
	sdev->regulator_count = i;

	return devm_add_action_or_reset(&pdev->dev,
					simpledrm_device_release_regulators,
					sdev);

err:
	while (i) {
		--i;
		if (sdev->regulators[i]) {
			regulator_disable(sdev->regulators[i]);
			regulator_put(sdev->regulators[i]);
		}
	}
	return ret;
}
#else
static int simpledrm_device_init_regulators(struct simpledrm_device *sdev)
{
	return 0;
}
#endif

#if defined CONFIG_OF && defined CONFIG_PM_GENERIC_DOMAINS
/*
 * Generic power domain handling code.
 *
 * Here we handle the power-domains properties of our "simple-framebuffer"
 * dt node. This is only necessary if there is more than one power-domain.
 * A single power-domains is handled automatically by the driver core. Multiple
 * power-domains have to be handled by drivers since the driver core can't know
 * the correct power sequencing. Power sequencing is not an issue for simpledrm
 * since the bootloader has put the power domains already in the correct state.
 * simpledrm has only to ensure they remain active for its lifetime.
 *
 * When the driver unloads, we detach from the power-domains.
 *
 * We only complain about errors here, no action is taken as the most likely
 * error can only happen due to a mismatch between the bootloader which set
 * up the "simple-framebuffer" dt node, and the PM domain providers in the
 * device tree. Chances are that there are no adverse effects, and if there are,
 * a clean teardown of the fb probe will not help us much either. So just
 * complain and carry on, and hope that the user actually gets a working fb at
 * the end of things.
 */
static void simpledrm_device_detach_genpd(void *res)
{
	int i;
	struct simpledrm_device *sdev = res;

	if (sdev->pwr_dom_count <= 1)
		return;

	for (i = sdev->pwr_dom_count - 1; i >= 0; i--) {
		if (sdev->pwr_dom_links[i])
			device_link_del(sdev->pwr_dom_links[i]);
		if (!IS_ERR_OR_NULL(sdev->pwr_dom_devs[i]))
			dev_pm_domain_detach(sdev->pwr_dom_devs[i], true);
	}
}

static int simpledrm_device_attach_genpd(struct simpledrm_device *sdev)
{
	struct device *dev = sdev->sysfb.dev.dev;
	int i;

	sdev->pwr_dom_count = of_count_phandle_with_args(dev->of_node, "power-domains",
							 "#power-domain-cells");
	/*
	 * Single power-domain devices are handled by driver core nothing to do
	 * here. The same for device nodes without "power-domains" property.
	 */
	if (sdev->pwr_dom_count <= 1)
		return 0;

	sdev->pwr_dom_devs = devm_kcalloc(dev, sdev->pwr_dom_count,
					  sizeof(*sdev->pwr_dom_devs),
					  GFP_KERNEL);
	if (!sdev->pwr_dom_devs)
		return -ENOMEM;

	sdev->pwr_dom_links = devm_kcalloc(dev, sdev->pwr_dom_count,
					   sizeof(*sdev->pwr_dom_links),
					   GFP_KERNEL);
	if (!sdev->pwr_dom_links)
		return -ENOMEM;

	for (i = 0; i < sdev->pwr_dom_count; i++) {
		sdev->pwr_dom_devs[i] = dev_pm_domain_attach_by_id(dev, i);
		if (IS_ERR(sdev->pwr_dom_devs[i])) {
			int ret = PTR_ERR(sdev->pwr_dom_devs[i]);

			if (ret == -EPROBE_DEFER) {
				simpledrm_device_detach_genpd(sdev);
				return ret;
			}
			drm_warn(&sdev->sysfb.dev,
				 "pm_domain_attach_by_id(%u) failed: %d\n", i, ret);
			continue;
		}

		sdev->pwr_dom_links[i] = device_link_add(dev,
							 sdev->pwr_dom_devs[i],
							 DL_FLAG_STATELESS |
							 DL_FLAG_PM_RUNTIME |
							 DL_FLAG_RPM_ACTIVE);
		if (!sdev->pwr_dom_links[i])
			drm_warn(&sdev->sysfb.dev, "failed to link power-domain %d\n", i);
	}

	return devm_add_action_or_reset(dev, simpledrm_device_detach_genpd, sdev);
}
#else
static int simpledrm_device_attach_genpd(struct simpledrm_device *sdev)
{
	return 0;
}
#endif

/*
 * Scan timing
 */

static unsigned int q25_line(struct simpledrm_device *sdev)
{
	return readl(sdev->rdma + RDMA_OUT_LINE_CNT) & 0x1fff;
}

static bool q25_active(struct simpledrm_device *sdev, unsigned int line)
{
	return line >= 1 && line < sdev->vact;
}

static ktime_t q25_predicted(struct simpledrm_device *sdev)
{
	unsigned long flags;
	ktime_t next;

	spin_lock_irqsave(&sdev->vbl_lock, flags);
	next = sdev->next_vbl;
	spin_unlock_irqrestore(&sdev->vbl_lock, flags);
	return next;
}

/* Start of the next front porch: exact from the counter, else the prediction. */
static ktime_t q25_next_vbl(struct simpledrm_device *sdev, ktime_t now, unsigned int *line)
{
	ktime_t next;

	*line = q25_line(sdev);
	if (q25_active(sdev, *line))
		return ktime_add_ns(now, (u64)(sdev->vact - *line) * sdev->line_ns);

	next = q25_predicted(sdev);
	while (ktime_compare(next, now) <= 0)
		next = ktime_add_ns(next, sdev->period_ns);
	while (ktime_compare(ktime_sub_ns(next, sdev->period_ns), now) > 0)
		next = ktime_sub_ns(next, sdev->period_ns);
	return next;
}

/* Start of the front porch the scan is in or last passed. */
static ktime_t q25_last_vbl(struct simpledrm_device *sdev, ktime_t now)
{
	unsigned int line;
	ktime_t next = q25_next_vbl(sdev, now, &line);

	return ktime_sub_ns(next, sdev->period_ns);
}

static void q25_signal(struct simpledrm_device *sdev, ktime_t vbl)
{
	unsigned long flags;

	spin_lock_irqsave(&sdev->vbl_lock, flags);
	sdev->vbl_ts = ktime_add_ns(vbl, sdev->blank_ns);
	sdev->next_vbl = ktime_add_ns(vbl, sdev->period_ns);
	spin_unlock_irqrestore(&sdev->vbl_lock, flags);

	drm_crtc_handle_vblank(&sdev->crtc);
}

static enum hrtimer_restart q25_vbl_timer_fn(struct hrtimer *t)
{
	struct simpledrm_device *sdev = container_of(t, struct simpledrm_device, vbl_timer);
	ktime_t now = ktime_get();
	unsigned int line;
	ktime_t vbl = q25_next_vbl(sdev, now, &line);

	if (!q25_active(sdev, line)) {
		/* Late into the blanking: this frame's porch has just passed. */
		vbl = q25_last_vbl(sdev, now);
		q25_signal(sdev, vbl);
	} else if (ktime_to_ns(ktime_sub(vbl, now)) <= 2 * sdev->lead_ns) {
		q25_signal(sdev, vbl);
	} else {
		/* Woke well before the porch (first lock, or a delayed timer): retarget. */
		vbl = ktime_sub_ns(vbl, sdev->period_ns);
	}

	hrtimer_set_expires(t, ktime_sub_ns(ktime_add_ns(vbl, sdev->period_ns), sdev->lead_ns));
	return HRTIMER_RESTART;
}

static irqreturn_t q25_dsi_irq(int irq, void *arg)
{
	struct simpledrm_device *sdev = arg;
	ktime_t now = ktime_get();
	unsigned int line;
	ktime_t vbl;

	if (!(readl(sdev->dsi + DSI_INTSTA) & DSI_FRAME_DONE))
		return IRQ_NONE;
	writel((u32)~DSI_FRAME_DONE, sdev->dsi + DSI_INTSTA);
	if (readl(sdev->dsi + DSI_INTSTA) & DSI_FRAME_DONE) {
		writel(readl(sdev->dsi + DSI_INTEN) & ~DSI_FRAME_DONE, sdev->dsi + DSI_INTEN);
		dev_err(sdev->sysfb.dev.dev, "FRAME_DONE does not clear; interrupt disabled\n");
		return IRQ_HANDLED;
	}

	/* The FRAME_DONE-to-porch phase is unmeasured; log it and stamp the last porch. */
	line = q25_line(sdev);
	vbl = q25_last_vbl(sdev, now);
	dev_dbg_ratelimited(sdev->sysfb.dev.dev, "FRAME_DONE at line %u\n", line);
	q25_signal(sdev, vbl);
	return IRQ_HANDLED;
}

/*
 * Tear-free blits: the scan reads rows top to bottom and the blit writes them
 * top to bottom faster than the scan, so a blit only tears when it starts with
 * the scan inside the damaged rows. One blit per refresh also throttles
 * userspace to the panel rate, since its event is sent right after the blit.
 */
static void q25_wait_for_scan(struct simpledrm_device *sdev, int y1, int y2)
{
	ktime_t now = ktime_get(), until = 0;
	unsigned int line;
	ktime_t next = q25_next_vbl(sdev, now, &line);

	if (ktime_after(sdev->last_blit, ktime_sub_ns(next, sdev->period_ns)))
		until = next;
	else if (q25_active(sdev, line) && line + Q25_FETCH_LINES >= y1 && line < y2)
		until = ktime_add_ns(now, (u64)(y2 - line) * sdev->line_ns);

	if (until) {
		s64 us = ktime_us_delta(until, now);

		if (us > 0)
			usleep_range(us, us + 50);
	}
}

static int q25_init_timing(struct simpledrm_device *sdev, unsigned int height,
			   struct drm_display_mode *mode)
{
	struct drm_device *dev = &sdev->sysfb.dev;
	unsigned int vsa, vbp, vfp, hsa, hbp, hfp, n = 0, prev, l;
	ktime_t first = 0, last = 0, deadline;
	struct device_node *np;
	struct resource res;

	np = of_find_compatible_node(NULL, NULL, "mediatek,mt6789-dsi");
	if (np && !of_address_to_resource(np, 0, &res)) {
		/* The panel-doze driver owns the region; map without requesting it. */
		sdev->dsi = devm_ioremap(dev->dev, res.start, resource_size(&res));
		sdev->dsi_irq = irq_of_parse_and_map(np, 0);
	}
	of_node_put(np);
	np = of_find_compatible_node(NULL, NULL, "mediatek,mt6789-disp-rdma");
	if (np && !of_address_to_resource(np, 0, &res))
		sdev->rdma = devm_ioremap(dev->dev, res.start, resource_size(&res));
	of_node_put(np);
	if (!sdev->dsi || !sdev->rdma)
		return -ENODEV;

	sdev->vact = readl(sdev->dsi + DSI_VACT_NL);
	if (!(readl(sdev->dsi + DSI_MODE_CTRL) & 3) || sdev->vact != height) {
		drm_err(dev, "DSI not scanning %u lines in video mode\n", height);
		return -ENODEV;
	}

	deadline = ktime_add_ms(ktime_get(), 50 * (Q25_PERIOD_FRAMES + 2));
	prev = q25_line(sdev);
	while (n <= Q25_PERIOD_FRAMES && ktime_before(ktime_get(), deadline)) {
		l = q25_line(sdev);
		if (l < prev) {
			last = ktime_get();
			if (!n++)
				first = last;
		}
		prev = l;
		usleep_range(10, 20);
	}
	if (n <= Q25_PERIOD_FRAMES)
		return -ETIMEDOUT;
	sdev->period_ns = ktime_to_ns(ktime_sub(last, first)) / Q25_PERIOD_FRAMES;
	if (sdev->period_ns < 8 * NSEC_PER_MSEC || sdev->period_ns > 34 * NSEC_PER_MSEC)
		return -ERANGE;

	vsa = readl(sdev->dsi + DSI_VSA_NL);
	vbp = readl(sdev->dsi + DSI_VBP_NL);
	vfp = readl(sdev->dsi + DSI_VFP_NL);
	/* RGB888 word counts back to pixels, as mtk_dsi_config_vdo_timing() writes them */
	hsa = (readl(sdev->dsi + DSI_HSA_WC) + 10) / 3;
	hbp = (readl(sdev->dsi + DSI_HBP_WC) + 10) / 3;
	hfp = (readl(sdev->dsi + DSI_HFP_WC) + 12) / 3;

	mode->hsync_start = mode->hdisplay + hfp;
	mode->hsync_end = mode->hsync_start + hsa;
	mode->htotal = mode->hsync_end + hbp;
	mode->vsync_start = mode->vdisplay + vfp;
	mode->vsync_end = mode->vsync_start + vsa;
	mode->vtotal = mode->vsync_end + vbp;
	mode->clock = DIV_ROUND_CLOSEST_ULL((u64)mode->htotal * mode->vtotal * NSEC_PER_MSEC,
					    sdev->period_ns);

	sdev->line_ns = div_u64(sdev->period_ns, mode->vtotal);
	sdev->lead_ns = Q25_LEAD_LINES * sdev->line_ns;
	sdev->blank_ns = (u64)(mode->vtotal - mode->vdisplay) * sdev->line_ns;
	spin_lock_init(&sdev->vbl_lock);
	hrtimer_setup(&sdev->vbl_timer, q25_vbl_timer_fn, CLOCK_MONOTONIC, HRTIMER_MODE_ABS_HARD);

	drm_info(dev, "scan period %llu ns (%u lines, %llu ns each), vblank from %s\n",
		 sdev->period_ns, mode->vtotal, sdev->line_ns,
		 use_irq ? "DSI FRAME_DONE" : "timer");

	if (!use_irq)
		return 0;
	if (sdev->dsi_irq <= 0)
		return -ENXIO;
	return devm_request_irq(dev->dev, sdev->dsi_irq, q25_dsi_irq, 0, "q25-vsyncdrm", sdev);
}

/*
 * Modesetting
 */

static const u64 simpledrm_primary_plane_format_modifiers[] = {
	DRM_SYSFB_PLANE_FORMAT_MODIFIERS,
};

static void simpledrm_primary_plane_helper_atomic_update(struct drm_plane *plane,
							 struct drm_atomic_state *state)
{
	struct simpledrm_device *sdev = to_simpledrm_device(plane->dev);
	struct drm_plane_state *old_state = drm_atomic_get_old_plane_state(state, plane);
	struct drm_plane_state *new_state = drm_atomic_get_new_plane_state(state, plane);
	struct drm_rect damage;

	if (drm_atomic_helper_damage_merged(old_state, new_state, &damage))
		q25_wait_for_scan(sdev, damage.y1, damage.y2);
	drm_sysfb_plane_helper_atomic_update(plane, state);
	sdev->last_blit = ktime_get();
}

static const struct drm_plane_helper_funcs simpledrm_primary_plane_helper_funcs = {
	.begin_fb_access = drm_sysfb_plane_helper_begin_fb_access,
	.end_fb_access = drm_gem_end_shadow_fb_access,
	.atomic_check = drm_sysfb_plane_helper_atomic_check,
	.atomic_update = simpledrm_primary_plane_helper_atomic_update,
	.atomic_disable = drm_sysfb_plane_helper_atomic_disable,
	.get_scanout_buffer = drm_sysfb_plane_helper_get_scanout_buffer,
};

static const struct drm_plane_funcs simpledrm_primary_plane_funcs = {
	DRM_SYSFB_PLANE_FUNCS,
	.destroy = drm_plane_cleanup,
};

/* The blit already landed in the scanout buffer, so the event goes out now. */
static void simpledrm_crtc_helper_atomic_flush(struct drm_crtc *crtc,
					       struct drm_atomic_state *state)
{
	struct drm_crtc_state *crtc_state = drm_atomic_get_new_crtc_state(state, crtc);
	struct drm_pending_vblank_event *event;

	spin_lock_irq(&crtc->dev->event_lock);
	event = crtc_state->event;
	crtc_state->event = NULL;
	if (event) {
		bool ref = !drm_crtc_vblank_get(crtc);

		drm_crtc_send_vblank_event(crtc, event);
		if (ref)
			drm_crtc_vblank_put(crtc);
	}
	spin_unlock_irq(&crtc->dev->event_lock);
}

static void simpledrm_crtc_helper_atomic_enable(struct drm_crtc *crtc,
						struct drm_atomic_state *state)
{
	struct simpledrm_device *sdev = to_simpledrm_device(crtc->dev);
	ktime_t now = ktime_get();
	unsigned int line = q25_line(sdev);
	/* Off the active area the phase is unknown; half a frame on lands inside it. */
	ktime_t next = ktime_add_ns(now, q25_active(sdev, line) ?
				    (u64)(sdev->vact - line) * sdev->line_ns : sdev->period_ns / 2);
	unsigned long flags;

	spin_lock_irqsave(&sdev->vbl_lock, flags);
	sdev->next_vbl = next;
	sdev->vbl_ts = ktime_add_ns(ktime_sub_ns(next, sdev->period_ns), sdev->blank_ns);
	spin_unlock_irqrestore(&sdev->vbl_lock, flags);

	drm_crtc_vblank_on(crtc);
	if (use_irq) {
		writel((u32)~DSI_FRAME_DONE, sdev->dsi + DSI_INTSTA);
		writel(readl(sdev->dsi + DSI_INTEN) | DSI_FRAME_DONE, sdev->dsi + DSI_INTEN);
	} else {
		hrtimer_start(&sdev->vbl_timer, ktime_sub_ns(next, sdev->lead_ns),
			      HRTIMER_MODE_ABS_HARD);
	}
}

static void simpledrm_crtc_helper_atomic_disable(struct drm_crtc *crtc,
						 struct drm_atomic_state *state)
{
	struct simpledrm_device *sdev = to_simpledrm_device(crtc->dev);

	if (use_irq)
		writel(readl(sdev->dsi + DSI_INTEN) & ~DSI_FRAME_DONE, sdev->dsi + DSI_INTEN);
	else
		hrtimer_cancel(&sdev->vbl_timer);
	drm_crtc_vblank_off(crtc);
}

static const struct drm_crtc_helper_funcs simpledrm_crtc_helper_funcs = {
	DRM_SYSFB_CRTC_HELPER_FUNCS,
	.atomic_flush = simpledrm_crtc_helper_atomic_flush,
	.atomic_enable = simpledrm_crtc_helper_atomic_enable,
	.atomic_disable = simpledrm_crtc_helper_atomic_disable,
};

/* Vblank runs whenever the CRTC is on; DRM drops it while nobody listens. */
static int simpledrm_crtc_enable_vblank(struct drm_crtc *crtc)
{
	return 0;
}

static void simpledrm_crtc_disable_vblank(struct drm_crtc *crtc)
{
}

static bool simpledrm_crtc_get_vblank_timestamp(struct drm_crtc *crtc, int *max_error,
						ktime_t *vblank_time, bool in_vblank_irq)
{
	struct simpledrm_device *sdev = to_simpledrm_device(crtc->dev);
	unsigned long flags;

	spin_lock_irqsave(&sdev->vbl_lock, flags);
	*vblank_time = sdev->vbl_ts;
	spin_unlock_irqrestore(&sdev->vbl_lock, flags);
	*max_error = sdev->line_ns;
	return true;
}

static const struct drm_crtc_funcs simpledrm_crtc_funcs = {
	DRM_SYSFB_CRTC_FUNCS,
	.destroy = drm_crtc_cleanup,
	.enable_vblank = simpledrm_crtc_enable_vblank,
	.disable_vblank = simpledrm_crtc_disable_vblank,
	.get_vblank_timestamp = simpledrm_crtc_get_vblank_timestamp,
};

static const struct drm_encoder_funcs simpledrm_encoder_funcs = {
	.destroy = drm_encoder_cleanup,
};

static const struct drm_connector_helper_funcs simpledrm_connector_helper_funcs = {
	DRM_SYSFB_CONNECTOR_HELPER_FUNCS,
};

static const struct drm_connector_funcs simpledrm_connector_funcs = {
	DRM_SYSFB_CONNECTOR_FUNCS,
	.destroy = drm_connector_cleanup,
};

static const struct drm_mode_config_funcs simpledrm_mode_config_funcs = {
	DRM_SYSFB_MODE_CONFIG_FUNCS,
};

/*
 * Init / Cleanup
 */

static struct simpledrm_device *simpledrm_device_create(struct drm_driver *drv,
							struct platform_device *pdev)
{
	const struct simplefb_platform_data *pd = dev_get_platdata(&pdev->dev);
	struct device_node *of_node = pdev->dev.of_node;
	struct simpledrm_device *sdev;
	struct drm_sysfb_device *sysfb;
	struct drm_device *dev;
	int width, height, stride;
	int width_mm = 0, height_mm = 0;
	struct device_node *panel_node;
	const struct drm_format_info *format;
	struct resource *res, *mem = NULL;
	struct drm_plane *primary_plane;
	struct drm_crtc *crtc;
	struct drm_encoder *encoder;
	struct drm_connector *connector;
	unsigned long max_width, max_height;
	size_t nformats;
	int ret;

	sdev = devm_drm_dev_alloc(&pdev->dev, drv, struct simpledrm_device, sysfb.dev);
	if (IS_ERR(sdev))
		return ERR_CAST(sdev);
	sysfb = &sdev->sysfb;
	dev = &sysfb->dev;
	platform_set_drvdata(pdev, sdev);

	/*
	 * Hardware settings
	 */

	ret = simpledrm_device_init_clocks(sdev);
	if (ret)
		return ERR_PTR(ret);
	ret = simpledrm_device_init_regulators(sdev);
	if (ret)
		return ERR_PTR(ret);
	ret = simpledrm_device_attach_genpd(sdev);
	if (ret)
		return ERR_PTR(ret);

	if (pd) {
		width = simplefb_get_width_pd(dev, pd);
		if (width < 0)
			return ERR_PTR(width);
		height = simplefb_get_height_pd(dev, pd);
		if (height < 0)
			return ERR_PTR(height);
		stride = simplefb_get_stride_pd(dev, pd);
		if (stride < 0)
			return ERR_PTR(stride);
		format = simplefb_get_format_pd(dev, pd);
		if (IS_ERR(format))
			return ERR_CAST(format);
	} else if (of_node) {
		width = simplefb_get_width_of(dev, of_node);
		if (width < 0)
			return ERR_PTR(width);
		height = simplefb_get_height_of(dev, of_node);
		if (height < 0)
			return ERR_PTR(height);
		stride = simplefb_get_stride_of(dev, of_node);
		if (stride < 0)
			return ERR_PTR(stride);
		format = simplefb_get_format_of(dev, of_node);
		if (IS_ERR(format))
			return ERR_CAST(format);
		mem = simplefb_get_memory_of(dev, of_node);
		if (IS_ERR(mem))
			return ERR_CAST(mem);
		panel_node = of_parse_phandle(of_node, "panel", 0);
		if (panel_node) {
			simplefb_read_u32_of(dev, panel_node, "width-mm", &width_mm);
			simplefb_read_u32_of(dev, panel_node, "height-mm", &height_mm);
			of_node_put(panel_node);
		}
	} else {
		drm_err(dev, "no simplefb configuration found\n");
		return ERR_PTR(-ENODEV);
	}
	if (!stride) {
		stride = drm_format_info_min_pitch(format, 0, width);
		if (drm_WARN_ON(dev, !stride))
			return ERR_PTR(-EINVAL);
	}

	sysfb->fb_mode = drm_sysfb_mode(width, height, width_mm, height_mm);
	ret = q25_init_timing(sdev, height, &sysfb->fb_mode);
	if (ret)
		return ERR_PTR(ret);
	sysfb->fb_format = format;
	sysfb->fb_pitch = stride;

	drm_dbg(dev, "display mode={" DRM_MODE_FMT "}\n", DRM_MODE_ARG(&sysfb->fb_mode));
	drm_dbg(dev, "framebuffer format=%p4cc, size=%dx%d, stride=%d byte\n",
		&format->format, width, height, stride);

	/*
	 * Memory management
	 */

	if (mem) {
		void *screen_base;

		ret = devm_aperture_acquire_for_platform_device(pdev, mem->start,
								resource_size(mem));
		if (ret) {
			drm_err(dev, "could not acquire memory range %pr: %d\n", mem, ret);
			return ERR_PTR(ret);
		}

		drm_dbg(dev, "using system memory framebuffer at %pr\n", mem);

		screen_base = devm_memremap(dev->dev, mem->start, resource_size(mem), MEMREMAP_WC);
		if (IS_ERR(screen_base))
			return screen_base;

		iosys_map_set_vaddr(&sysfb->fb_addr, screen_base);
	} else {
		void __iomem *screen_base;

		res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
		if (!res)
			return ERR_PTR(-EINVAL);

		ret = devm_aperture_acquire_for_platform_device(pdev, res->start,
								resource_size(res));
		if (ret) {
			drm_err(dev, "could not acquire memory range %pr: %d\n", res, ret);
			return ERR_PTR(ret);
		}

		drm_dbg(dev, "using I/O memory framebuffer at %pr\n", res);

		mem = devm_request_mem_region(&pdev->dev, res->start, resource_size(res),
					      drv->name);
		if (!mem) {
			/*
			 * We cannot make this fatal. Sometimes this comes from magic
			 * spaces our resource handlers simply don't know about. Use
			 * the I/O-memory resource as-is and try to map that instead.
			 */
			drm_warn(dev, "could not acquire memory region %pr\n", res);
			mem = res;
		}

		screen_base = devm_ioremap_wc(&pdev->dev, mem->start, resource_size(mem));
		if (!screen_base)
			return ERR_PTR(-ENOMEM);

		iosys_map_set_vaddr_iomem(&sysfb->fb_addr, screen_base);
	}

	/*
	 * Modesetting
	 */

	ret = drmm_mode_config_init(dev);
	if (ret)
		return ERR_PTR(ret);

	max_width = max_t(unsigned long, width, DRM_SHADOW_PLANE_MAX_WIDTH);
	max_height = max_t(unsigned long, height, DRM_SHADOW_PLANE_MAX_HEIGHT);

	dev->mode_config.min_width = width;
	dev->mode_config.max_width = max_width;
	dev->mode_config.min_height = height;
	dev->mode_config.max_height = max_height;
	dev->mode_config.preferred_depth = format->depth;
	dev->mode_config.funcs = &simpledrm_mode_config_funcs;

	/* Primary plane */

	nformats = drm_sysfb_build_fourcc_list(dev, &format->format, 1,
					       sdev->formats, ARRAY_SIZE(sdev->formats));

	primary_plane = &sdev->primary_plane;
	ret = drm_universal_plane_init(dev, primary_plane, 0, &simpledrm_primary_plane_funcs,
				       sdev->formats, nformats,
				       simpledrm_primary_plane_format_modifiers,
				       DRM_PLANE_TYPE_PRIMARY, NULL);
	if (ret)
		return ERR_PTR(ret);
	drm_plane_helper_add(primary_plane, &simpledrm_primary_plane_helper_funcs);
	drm_plane_enable_fb_damage_clips(primary_plane);

	/* CRTC */

	crtc = &sdev->crtc;
	ret = drm_crtc_init_with_planes(dev, crtc, primary_plane, NULL,
					&simpledrm_crtc_funcs, NULL);
	if (ret)
		return ERR_PTR(ret);
	drm_crtc_helper_add(crtc, &simpledrm_crtc_helper_funcs);

	/* Encoder */

	encoder = &sdev->encoder;
	ret = drm_encoder_init(dev, encoder, &simpledrm_encoder_funcs,
			       DRM_MODE_ENCODER_NONE, NULL);
	if (ret)
		return ERR_PTR(ret);
	encoder->possible_crtcs = drm_crtc_mask(crtc);

	/* Connector */

	connector = &sdev->connector;
	ret = drm_connector_init(dev, connector, &simpledrm_connector_funcs,
				 DRM_MODE_CONNECTOR_Unknown);
	if (ret)
		return ERR_PTR(ret);
	drm_connector_helper_add(connector, &simpledrm_connector_helper_funcs);
	drm_connector_set_panel_orientation_with_quirk(connector,
						       DRM_MODE_PANEL_ORIENTATION_UNKNOWN,
						       width, height);

	ret = drm_connector_attach_encoder(connector, encoder);
	if (ret)
		return ERR_PTR(ret);

	ret = drm_vblank_init(dev, 1);
	if (ret)
		return ERR_PTR(ret);

	drm_mode_config_reset(dev);

	return sdev;
}

/*
 * DRM driver
 */

DEFINE_DRM_GEM_FOPS(simpledrm_fops);

static struct drm_driver simpledrm_driver = {
	DRM_GEM_SHMEM_DRIVER_OPS,
	DRM_FBDEV_SHMEM_DRIVER_OPS,
	.name			= DRIVER_NAME,
	.desc			= DRIVER_DESC,
	.major			= DRIVER_MAJOR,
	.minor			= DRIVER_MINOR,
	.driver_features	= DRIVER_ATOMIC | DRIVER_GEM | DRIVER_MODESET,
	.fops			= &simpledrm_fops,
};

/*
 * Platform driver
 */

static int simpledrm_probe(struct platform_device *pdev)
{
	struct simpledrm_device *sdev;
	struct drm_sysfb_device *sysfb;
	struct drm_device *dev;
	int ret;

	sdev = simpledrm_device_create(&simpledrm_driver, pdev);
	if (IS_ERR(sdev))
		return PTR_ERR(sdev);
	sysfb = &sdev->sysfb;
	dev = &sysfb->dev;

	ret = drm_dev_register(dev, 0);
	if (ret)
		return ret;

	drm_client_setup(dev, sdev->sysfb.fb_format);

	return 0;
}

static void simpledrm_remove(struct platform_device *pdev)
{
	struct simpledrm_device *sdev = platform_get_drvdata(pdev);
	struct drm_device *dev = &sdev->sysfb.dev;

	drm_dev_unplug(dev);
	if (use_irq)
		writel(readl(sdev->dsi + DSI_INTEN) & ~DSI_FRAME_DONE, sdev->dsi + DSI_INTEN);
	hrtimer_cancel(&sdev->vbl_timer);
}

/* No match table: it binds only through driver_override, after simpledrm lets go. */
static struct platform_driver simpledrm_platform_driver = {
	.driver = {
		.name = "q25-vsyncdrm",
	},
	.probe = simpledrm_probe,
	.remove = simpledrm_remove,
};

module_platform_driver(simpledrm_platform_driver);

MODULE_DESCRIPTION(DRIVER_DESC);
MODULE_LICENSE("GPL v2");
