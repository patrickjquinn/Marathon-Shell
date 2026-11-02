// SPDX-License-Identifier: GPL-2.0
/*
 * Zinwa Q25 (Xelex q20_v12) 720x720 DSI video-mode panel.
 *
 * Ported from the vendor MediaTek LCM driver
 * (drivers/gpu/drm/panel/panel-q20-hd720-lcm-dsi-vdo.c in the LineageOS
 * android_kernel_xelex_mt6789 tree) to a plain mainline drm_panel driver.
 *
 * The vendor driver's lcm_panel_init() DCS command table is entirely inside
 * #if 0 on the shipping q20_v12 board: the panel needs only the power/reset
 * sequence followed by the standard exit_sleep_mode + set_display_on. There
 * is therefore no vendor-specific init sequence to transcribe here.
 *
 * Copyright (c) 2019 MediaTek Inc. (original vendor driver)
 */

#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/module.h>
#include <linux/of.h>

#include <drm/drm_mipi_dsi.h>
#include <drm/drm_modes.h>
#include <drm/drm_panel.h>

#include <video/mipi_display.h>

struct q20_panel {
	struct drm_panel panel;
	struct mipi_dsi_device *dsi;
	struct gpio_desc *reset_gpio;
	struct gpio_desc *enable_gpio;	/* avdd / ocp2131 bias enable */
	bool prepared;
};

static inline struct q20_panel *to_q20_panel(struct drm_panel *panel)
{
	return container_of(panel, struct q20_panel, panel);
}

/*
 * Mode 0, 60 fps (the shipping firmware mode). Vendor header values:
 *   HSA 50, HBP 40, HFP 60; VSA 5, VBP 35, VFP 68; pixel timing pclk 43222 kHz.
 *
 * BUT: the vendor LCM runs the DSI HS link at an explicit PLL giving a
 * 652 Mbit/s-per-lane data rate (HW_MAP mode-0 pll pair). Mainline mtk_dsi
 * derives the link rate SOLELY from mode->clock:
 *   data_rate = mode->clock * bpp / lanes = 43222 * 24 / 2 = 518.7 Mbit/s
 * and ignores dsi->hs_rate. Feeding this panel a link ~26% below its rated
 * 652 Mbit/s leaves its TCON PLL unable to lock -> the frame rolls vertically.
 *
 * Since mode->clock is the only knob over the link rate, express the vendor
 * 652 Mbit/s through it and absorb the extra rate in the horizontal front
 * porch so the panel still sees 60 fps:
 *   clock 54334 kHz -> data_rate = 54334 * 24 / 2 = 652008 kbit/s ~= 652 Mbit/s
 *   HFP 284 -> htotal = 720 + 284 + 50 + 40 = 1094
 *   fps = 54334000 / (1094 * 828) = 59.98 Hz
 * vertical timing is unchanged (vtotal 828).
 */
static const struct drm_display_mode q20_mode = {
	.clock		= 54334,
	.hdisplay	= 720,
	.hsync_start	= 720 + 284,
	.hsync_end	= 720 + 284 + 50,
	.htotal		= 720 + 284 + 50 + 40,
	.vdisplay	= 720,
	.vsync_start	= 720 + 68,
	.vsync_end	= 720 + 68 + 5,
	.vtotal		= 720 + 68 + 5 + 35,
	.width_mm	= 62,
	.height_mm	= 62,
};

static int q20_panel_prepare(struct drm_panel *panel)
{
	struct q20_panel *ctx = to_q20_panel(panel);
	struct mipi_dsi_device *dsi = ctx->dsi;
	int ret;

	if (ctx->prepared)
		return 0;

	/* Power + reset sequence, mirroring the vendor lcm_prepare(). */
	gpiod_set_value(ctx->enable_gpio, 1);
	msleep(15);
	gpiod_set_value(ctx->reset_gpio, 1);
	msleep(1);
	gpiod_set_value(ctx->reset_gpio, 0);
	msleep(10);
	gpiod_set_value(ctx->reset_gpio, 1);
	msleep(120);

	/* No panel-specific DCS init: shipping q20_v12 uses power-on defaults. */

	ret = mipi_dsi_dcs_exit_sleep_mode(dsi);
	if (ret < 0) {
		dev_err(&dsi->dev, "failed to exit sleep mode: %d\n", ret);
		goto fail;
	}
	msleep(120);

	ret = mipi_dsi_dcs_set_display_on(dsi);
	if (ret < 0) {
		dev_err(&dsi->dev, "failed to set display on: %d\n", ret);
		goto fail;
	}
	usleep_range(10000, 20000);

	ctx->prepared = true;
	return 0;

fail:
	gpiod_set_value(ctx->reset_gpio, 0);
	gpiod_set_value(ctx->enable_gpio, 0);
	return ret;
}

static int q20_panel_unprepare(struct drm_panel *panel)
{
	struct q20_panel *ctx = to_q20_panel(panel);
	struct mipi_dsi_device *dsi = ctx->dsi;

	if (!ctx->prepared)
		return 0;

	mipi_dsi_dcs_set_display_off(dsi);
	usleep_range(10000, 20000);
	mipi_dsi_dcs_enter_sleep_mode(dsi);

	/*
	 * The q20_v12 board deliberately keeps the panel rails powered across
	 * unprepare (vendor: "Q20 V12 board not poweroff"), so we do NOT drop
	 * the reset / enable GPIOs here.
	 */
	ctx->prepared = false;
	return 0;
}

static int q20_panel_get_modes(struct drm_panel *panel,
			       struct drm_connector *connector)
{
	struct drm_display_mode *mode;

	mode = drm_mode_duplicate(connector->dev, &q20_mode);
	if (!mode)
		return -ENOMEM;

	drm_mode_set_name(mode);
	mode->type = DRM_MODE_TYPE_DRIVER | DRM_MODE_TYPE_PREFERRED;
	drm_mode_probed_add(connector, mode);

	connector->display_info.width_mm = q20_mode.width_mm;
	connector->display_info.height_mm = q20_mode.height_mm;

	return 1;
}

static const struct drm_panel_funcs q20_panel_funcs = {
	.prepare	= q20_panel_prepare,
	.unprepare	= q20_panel_unprepare,
	.get_modes	= q20_panel_get_modes,
};

static int q20_panel_probe(struct mipi_dsi_device *dsi)
{
	struct device *dev = &dsi->dev;
	struct q20_panel *ctx;
	int ret;

	ctx = devm_kzalloc(dev, sizeof(*ctx), GFP_KERNEL);
	if (!ctx)
		return -ENOMEM;

	ctx->dsi = dsi;
	mipi_dsi_set_drvdata(dsi, ctx);

	dsi->lanes = 2;
	dsi->format = MIPI_DSI_FMT_RGB888;
	dsi->mode_flags = MIPI_DSI_MODE_VIDEO |
			  MIPI_DSI_MODE_VIDEO_SYNC_PULSE |
			  MIPI_DSI_MODE_LPM |
			  MIPI_DSI_CLOCK_NON_CONTINUOUS;

	ctx->reset_gpio = devm_gpiod_get(dev, "reset", GPIOD_OUT_HIGH);
	if (IS_ERR(ctx->reset_gpio))
		return dev_err_probe(dev, PTR_ERR(ctx->reset_gpio),
				     "cannot get reset-gpios\n");

	ctx->enable_gpio = devm_gpiod_get(dev, "enable", GPIOD_OUT_HIGH);
	if (IS_ERR(ctx->enable_gpio))
		return dev_err_probe(dev, PTR_ERR(ctx->enable_gpio),
				     "cannot get enable-gpios\n");

	drm_panel_init(&ctx->panel, dev, &q20_panel_funcs,
		       DRM_MODE_CONNECTOR_DSI);

	ret = drm_panel_of_backlight(&ctx->panel);
	if (ret)
		return ret;

	drm_panel_add(&ctx->panel);

	ret = mipi_dsi_attach(dsi);
	if (ret < 0) {
		dev_err(dev, "failed to attach to DSI host: %d\n", ret);
		drm_panel_remove(&ctx->panel);
		return ret;
	}

	return 0;
}

static void q20_panel_remove(struct mipi_dsi_device *dsi)
{
	struct q20_panel *ctx = mipi_dsi_get_drvdata(dsi);

	mipi_dsi_detach(dsi);
	drm_panel_remove(&ctx->panel);
}

static const struct of_device_id q20_panel_of_match[] = {
	{ .compatible = "zinwa,q20-hd720" },
	{ }
};
MODULE_DEVICE_TABLE(of, q20_panel_of_match);

static struct mipi_dsi_driver q20_panel_driver = {
	.probe = q20_panel_probe,
	.remove = q20_panel_remove,
	.driver = {
		.name = "panel-zinwa-q20-hd720",
		.of_match_table = q20_panel_of_match,
	},
};
module_mipi_dsi_driver(q20_panel_driver);

MODULE_DESCRIPTION("Zinwa Q25 q20_v12 720x720 DSI panel driver");
MODULE_LICENSE("GPL v2");
