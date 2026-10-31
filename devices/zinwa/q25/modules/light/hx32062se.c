// SPDX-License-Identifier: GPL-2.0
/*
 * TYHX HX32062SE ambient light and proximity sensor (polled).
 *
 * No datasheet is public. The register usage comes from the MediaTek SCP
 * sensor-hub firmware on the Zinwa Q25; see HANDOFF.md for what is decoded
 * versus assumed.
 */

#include <linux/bits.h>
#include <linux/delay.h>
#include <linux/i2c.h>
#include <linux/iio/iio.h>
#include <linux/module.h>
#include <linux/mod_devicetable.h>
#include <linux/mutex.h>
#include <linux/property.h>
#include <linux/regmap.h>
#include <linux/time.h>
#include <linux/unaligned.h>

#define HX_REG_ID		0x00
#define HX_ID_REV_1S2_MC	0x37
#define HX_REG_RESTART		0x1a
#define HX_RESTART_BIT		BIT(2)
#define HX_REG_PS_START		0x70
#define HX_PS_START		0x02
#define HX_PS_START_DELAY_US	(250 * USEC_PER_MSEC)
#define HX_REG_ALS_DATA		0x01	/* 9 bytes: als1[3] ch2[3] - ch3[2] */
#define HX_REG_CTRL		0x4c
#define HX_CTRL_ALS_EN		GENMASK(2, 0)
#define HX_CTRL_PS_EN		BIT(3)
#define HX_REG_PS_THR_HI	0x60	/* 16-bit LE */
#define HX_REG_PS_THR_LO	0x62	/* 16-bit LE */
#define HX_REG_PS_DATA		0x69	/* 16-bit LE */
#define HX_REG_LATCH		0x83
#define HX_LATCH_HOLD		BIT(1)

#define HX_DEFAULT_NEAR		3800	/* stock ps_threshold_high */
#define HX_DEFAULT_FAR		3300	/* stock ps_threshold_low */

/* Stock SCP firmware probe table, written in this order. */
static const u8 hx32062se_init[][2] = {
	{ 0x64, 0x00 }, { 0x65, 0x00 }, { 0x66, 0x00 }, { 0x72, 0xff },
	{ 0x53, 0xf4 }, { 0x52, 0x52 }, { 0x55, 0xc5 }, { 0x50, 0x74 },
	{ 0x5c, 0x21 }, { 0xe0, 0x00 }, { 0xe1, 0xd7 }, { 0xe2, 0xc8 },
	{ 0xe3, 0xf8 }, { 0xe4, 0x80 }, { 0xe7, 0x00 }, { 0xe9, 0x3f },
	{ 0xea, 0x57 }, { 0xeb, 0x04 }, { 0xec, 0x2c }, { 0xed, 0x01 },
	{ 0xef, 0x9f }, { 0xf0, 0x0f }, { 0x5a, 0x00 }, { 0x5b, 0x01 },
	{ 0x20, 0x30 }, { 0x21, 0x10 }, { 0x30, 0x30 }, { 0x31, 0x10 },
	{ 0x54, 0x22 }, { 0x1d, 0x10 }, { 0x80, 0x12 }, { 0x83, 0x00 },
	{ 0x1f, 0x80 }, { 0x19, 0x00 }, { 0x1d, 0xd0 }, { 0x1e, 0xc0 },
	{ 0x1c, 0x00 }, { 0x1b, 0x00 }, { 0x8a, 0xd0 }, { 0x8b, 0x00 },
	{ 0x8c, 0xd0 }, { 0x8d, 0x00 }, { 0x2a, 0x01 }, { 0x2b, 0xfc },
	{ 0x2c, 0x01 }, { 0x3a, 0x00 }, { 0x3b, 0x00 }, { 0x3c, 0x00 },
	{ 0x3d, 0x00 }, { 0x4d, 0x00 }, { 0x4e, 0x00 }, { 0x4f, 0x00 },
	{ 0x29, 0x06 }, { 0x39, 0x06 }, { 0x4a, 0x06 }, { 0x46, 0x00 },
	{ 0x47, 0x00 }, { 0x48, 0x18 }, { 0x67, 0x18 }, { 0x14, 0x02 },
	{ 0x77, 0x20 }, { 0x58, 0x80 }, { 0x6e, 0x0f }, { 0x70, 0x00 },
	/* After the table, before selecting the gain. */
	{ 0x45, 0x10 }, { 0x1d, 0x10 },
	/* Stock gain index 1 (the probe default): 0x29/0x39/0x4a, 0x8a/0x8c, 0xe7, 0xef. */
	{ 0x29, 0x06 }, { 0x39, 0x06 }, { 0x4a, 0x06 },
	{ 0x8a, 0xd0 }, { 0x8c, 0xd0 }, { 0xe7, 0x00 }, { 0xef, 0xbf },
};

static unsigned int lux_scale_micro = 1000;
module_param(lux_scale_micro, uint, 0644);
MODULE_PARM_DESC(lux_scale_micro, "lux per ALS count in millionths; rough, ~270k counts indoors");

struct hx32062se {
	struct regmap *regmap;
	struct mutex lock;	/* serialises latch + burst read */
	u32 near_level;
};

static int hx32062se_read_latched(struct hx32062se *hx, unsigned int reg,
				  u8 *buf, size_t len)
{
	int ret, ret2;

	guard(mutex)(&hx->lock);

	ret = regmap_set_bits(hx->regmap, HX_REG_LATCH, HX_LATCH_HOLD);
	if (ret)
		return ret;
	ret = regmap_bulk_read(hx->regmap, reg, buf, len);
	ret2 = regmap_clear_bits(hx->regmap, HX_REG_LATCH, HX_LATCH_HOLD);
	return ret ?: ret2;
}

static int hx32062se_read_raw(struct iio_dev *indio_dev,
			      const struct iio_chan_spec *chan,
			      int *val, int *val2, long mask)
{
	struct hx32062se *hx = iio_priv(indio_dev);
	u8 buf[9];
	int ret;

	switch (mask) {
	case IIO_CHAN_INFO_RAW:
		if (chan->type == IIO_LIGHT) {
			ret = hx32062se_read_latched(hx, HX_REG_ALS_DATA, buf, 9);
			if (ret)
				return ret;
			*val = get_unaligned_le24(buf);
		} else {
			ret = hx32062se_read_latched(hx, HX_REG_PS_DATA, buf, 2);
			if (ret)
				return ret;
			*val = get_unaligned_le16(buf);
		}
		return IIO_VAL_INT;
	case IIO_CHAN_INFO_SCALE:
		*val = lux_scale_micro / 1000000;
		*val2 = lux_scale_micro % 1000000;
		return IIO_VAL_INT_PLUS_MICRO;
	default:
		return -EINVAL;
	}
}

static ssize_t hx32062se_read_near_level(struct iio_dev *indio_dev,
					 uintptr_t priv,
					 const struct iio_chan_spec *chan,
					 char *buf)
{
	struct hx32062se *hx = iio_priv(indio_dev);

	return sysfs_emit(buf, "%u\n", hx->near_level);
}

static const struct iio_chan_spec_ext_info hx32062se_ps_ext_info[] = {
	{
		.name = "nearlevel",
		.shared = IIO_SEPARATE,
		.read = hx32062se_read_near_level,
	},
	{ }
};

static const struct iio_chan_spec hx32062se_channels[] = {
	{
		.type = IIO_LIGHT,
		.info_mask_separate = BIT(IIO_CHAN_INFO_RAW) |
				      BIT(IIO_CHAN_INFO_SCALE),
	},
	{
		.type = IIO_PROXIMITY,
		.info_mask_separate = BIT(IIO_CHAN_INFO_RAW),
		.ext_info = hx32062se_ps_ext_info,
	},
};

static const struct iio_info hx32062se_info = {
	.read_raw = hx32062se_read_raw,
};

/*
 * 0x90-0x97 hold the efuse calibration the chip loads itself; 0x9a controls
 * that load. Never written: v5 proved they are shadow registers, but there is
 * no datasheet saying what else 0x9a can do.
 */
static bool hx32062se_writeable(struct device *dev, unsigned int reg)
{
	return reg != HX_REG_ID && (reg < 0x90 || reg > 0x9a);
}

/*
 * Stock probe, calibrated part (0x97 != 0, 0x97 bit 6 clear): PS digital gain
 * = 0x92[7:6] + 5, written to 0x67 with bit 4 set. Otherwise keep the init
 * table's 0x67 = 0x18.
 */
static int hx32062se_ps_gain(struct hx32062se *hx, struct device *dev)
{
	unsigned int e92, e97;
	int ret;

	ret = regmap_read(hx->regmap, 0x92, &e92);
	if (ret)
		return ret;
	ret = regmap_read(hx->regmap, 0x97, &e97);
	if (ret)
		return ret;
	dev_info(dev, "efuse 0x92=%02x 0x97=%02x\n", e92, e97);
	if (!e97 || (e97 & BIT(6)))
		return 0;
	return regmap_write(hx->regmap, 0x67, 0x10 | ((e92 >> 6) + 5));
}

static const struct regmap_config hx32062se_regmap_config = {
	.reg_bits = 8,
	.val_bits = 8,
	.max_register = 0xff,
	.writeable_reg = hx32062se_writeable,
	.cache_type = REGCACHE_NONE,
};

static int hx32062se_write_le16(struct hx32062se *hx, unsigned int reg, u16 val)
{
	int ret;

	ret = regmap_write(hx->regmap, reg, val & 0xff);
	if (ret)
		return ret;
	return regmap_write(hx->regmap, reg + 1, val >> 8);
}

static int hx32062se_restart(struct hx32062se *hx)
{
	int ret;

	ret = regmap_clear_bits(hx->regmap, HX_REG_RESTART, HX_RESTART_BIT);
	if (ret)
		return ret;
	return regmap_set_bits(hx->regmap, HX_REG_RESTART, HX_RESTART_BIT);
}

static int hx32062se_set_enable(struct hx32062se *hx, bool on)
{
	int ret;

	ret = regmap_update_bits(hx->regmap, HX_REG_CTRL,
				 HX_CTRL_ALS_EN | HX_CTRL_PS_EN,
				 on ? HX_CTRL_ALS_EN | HX_CTRL_PS_EN : 0);
	if (ret || !on)
		return ret;

	/* The stock ALS enable restarts the engine by pulsing 0x1a bit 2. */
	ret = hx32062se_restart(hx);
	if (ret)
		return ret;

	/*
	 * The stock PS poll writes 0x70 = 0x02 and restarts on its fifth
	 * 50 ms frame; 0x69 reads zero until then.
	 */
	fsleep(HX_PS_START_DELAY_US);
	ret = regmap_write(hx->regmap, HX_REG_PS_START, HX_PS_START);
	if (ret)
		return ret;
	return hx32062se_restart(hx);
}

static void hx32062se_disable(void *data)
{
	hx32062se_set_enable(data, false);
}

static int hx32062se_probe(struct i2c_client *client)
{
	struct device *dev = &client->dev;
	struct iio_dev *indio_dev;
	struct hx32062se *hx;
	unsigned int id, ctrl, i;
	int ret;

	indio_dev = devm_iio_device_alloc(dev, sizeof(*hx));
	if (!indio_dev)
		return -ENOMEM;
	hx = iio_priv(indio_dev);
	mutex_init(&hx->lock);
	i2c_set_clientdata(client, indio_dev);

	hx->regmap = devm_regmap_init_i2c(client, &hx32062se_regmap_config);
	if (IS_ERR(hx->regmap))
		return PTR_ERR(hx->regmap);

	ret = regmap_read(hx->regmap, HX_REG_ID, &id);
	if (ret)
		return dev_err_probe(dev, ret, "no response at 0x%02x\n", client->addr);
	ret = regmap_read(hx->regmap, HX_REG_CTRL, &ctrl);
	if (ret)
		return ret;
	dev_info(dev, "id 0x%02x, ctrl 0x%02x\n", id, ctrl);
	if (id != HX_ID_REV_1S2_MC)
		dev_warn(dev, "unknown revision 0x%02x, init table is for 0x%02x\n",
			 id, HX_ID_REV_1S2_MC);

	for (i = 0; i < ARRAY_SIZE(hx32062se_init); i++) {
		ret = regmap_write(hx->regmap, hx32062se_init[i][0],
				   hx32062se_init[i][1]);
		if (ret)
			return ret;
	}
	ret = hx32062se_restart(hx);
	if (ret)
		return ret;
	ret = hx32062se_ps_gain(hx, dev);
	if (ret)
		return ret;

	hx->near_level = HX_DEFAULT_NEAR;
	device_property_read_u32(dev, "proximity-near-level", &hx->near_level);

	/* The stock firmware writes these one byte at a time. */
	ret = hx32062se_write_le16(hx, HX_REG_PS_THR_HI, hx->near_level);
	if (ret)
		return ret;
	ret = hx32062se_write_le16(hx, HX_REG_PS_THR_LO, HX_DEFAULT_FAR);
	if (ret)
		return ret;

	ret = hx32062se_set_enable(hx, true);
	if (ret)
		return ret;
	ret = devm_add_action_or_reset(dev, hx32062se_disable, hx);
	if (ret)
		return ret;

	indio_dev->name = "hx32062se";
	indio_dev->info = &hx32062se_info;
	indio_dev->channels = hx32062se_channels;
	indio_dev->num_channels = ARRAY_SIZE(hx32062se_channels);
	indio_dev->modes = INDIO_DIRECT_MODE;

	return devm_iio_device_register(dev, indio_dev);
}

static int hx32062se_suspend(struct device *dev)
{
	struct hx32062se *hx = iio_priv(dev_get_drvdata(dev));

	return hx32062se_set_enable(hx, false);
}

static int hx32062se_resume(struct device *dev)
{
	struct hx32062se *hx = iio_priv(dev_get_drvdata(dev));

	return hx32062se_set_enable(hx, true);
}

/* Its supply survives a reboot, so stop sampling before one. */
static void hx32062se_shutdown(struct i2c_client *client)
{
	hx32062se_set_enable(iio_priv(i2c_get_clientdata(client)), false);
}

static DEFINE_SIMPLE_DEV_PM_OPS(hx32062se_pm_ops, hx32062se_suspend,
				hx32062se_resume);

static const struct of_device_id hx32062se_of_match[] = {
	{ .compatible = "tyhx,hx32062se" },
	{ }
};
MODULE_DEVICE_TABLE(of, hx32062se_of_match);

static const struct i2c_device_id hx32062se_id[] = {
	{ "hx32062se" },
	{ }
};
MODULE_DEVICE_TABLE(i2c, hx32062se_id);

static struct i2c_driver hx32062se_driver = {
	.driver = {
		.name = "hx32062se",
		.of_match_table = hx32062se_of_match,
		.pm = pm_sleep_ptr(&hx32062se_pm_ops),
	},
	.probe = hx32062se_probe,
	.shutdown = hx32062se_shutdown,
	.id_table = hx32062se_id,
};
module_i2c_driver(hx32062se_driver);

MODULE_DESCRIPTION("TYHX HX32062SE ambient light and proximity sensor");
MODULE_LICENSE("GPL");
