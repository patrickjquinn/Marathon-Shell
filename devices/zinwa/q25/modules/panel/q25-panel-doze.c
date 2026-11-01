// SPDX-License-Identifier: GPL-2.0-only
/*
 * Zinwa Q25 panel sleep for Doze, through the DSI host the bootloader left
 * running in video mode (no DSI/DRM driver owns it).
 *
 * bl_power off: DCS 0x28, 0x10, check 0x0A, then drop GPIO84 (OCP2131 bias,
 * which also darkens the screen). bl_power on: GPIO84, 0x11, 0x29, check 0x0A;
 * on a bad check, the stock reset + sleep-out + display-on.
 * Writes go as video-mode commands (VM_CMD, stock mtk_dsi_host_send_vm_cmd);
 * reads stop video for one transfer and restart it (mainline mtk_dsi_host_transfer).
 *
 * Brightness, once root writes an I2C bus number to ocp_attach and the OCP2131
 * answers there: its AVDD/AVEE code (4.0 V + n * 100 mV, datasheet max 0x14), as
 * stock _gate_ic_backlight_set. Nothing I2C happens at probe.
 */
#include <linux/backlight.h>
#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/i2c.h>
#include <linux/io.h>
#include <linux/iopoll.h>
#include <linux/mod_devicetable.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/platform_device.h>

#define DSI_START		0x00
#define VM_CMD_START		BIT(16)
#define DSI_INTSTA		0x0c
#define LPRX_RD_RDY		BIT(0)
#define CMD_DONE		BIT(1)
#define VM_DONE			BIT(3)
#define VM_CMD_DONE		BIT(5)
#define DSI_BUSY		BIT(31)
#define DSI_MODE_CTRL		0x14
#define DSI_CMDQ_SIZE		0x60
#define DSI_RX_DATA0		0x74
#define DSI_RACK		0x84
#define DSI_VM_CMD_CON		0x200	/* MT6789: platform/mtk_drm_6789.c */
#define VM_CMD_EN		BIT(0)
#define TS_VFP_EN		BIT(5)
#define DSI_CMDQ0		0xd00

#define DCS_SHORT_WRITE		0x05
#define DCS_SHORT_WRITE_PARAM	0x15
#define DCS_READ		0x06
#define SET_MAX_RETURN		0x37
#define RX_ACK_ERR		0x02
#define RX_DCS_1BYTE		0x21
#define CFG_BTA			BIT(2)

#define PM_AWAKE		0x9c	/* booster, sleep out, normal, display on (stock) */
#define PM_SLEEP_OUT		BIT(4)
#define PM_DISPLAY_ON		BIT(2)

#define OCP_ADDR		0x3e
#define OCP_AVDD		0x00
#define OCP_AVEE		0x01
#define OCP_ID			0x04
#define OCP_ID_VALUE		0x0d	/* datasheet */
#define OCP_ID_VALUE_Q25	0x02	/* this unit's part */
#define OCP_MAX			0x14

struct q25_panel {
	struct device *dev;
	void __iomem *dsi;
	struct gpio_desc *bias;
	struct gpio_desc *reset;
	struct mutex lock;	/* serialises DSI and OCP2131 access */
	struct backlight_device *bd;
	struct i2c_client *ocp;
	bool on;
	int code;
	int last_pm;
};

static int q25_ocp_set(struct q25_panel *p, int code)
{
	int ret;

	ret = i2c_smbus_write_byte_data(p->ocp, OCP_AVDD, code);
	if (!ret)
		ret = i2c_smbus_write_byte_data(p->ocp, OCP_AVEE, code);
	if (ret) {
		dev_err(p->dev, "OCP2131 code %#x: %d\n", code, ret);
		return ret;
	}
	p->code = code;
	return 0;
}

static void q25_clear(struct q25_panel *p, u32 bits)
{
	writel(readl(p->dsi + DSI_INTSTA) & ~bits, p->dsi + DSI_INTSTA);
}

static int q25_dcs_write(struct q25_panel *p, u8 cmd, int param)
{
	u32 val, start;

	if (param < 0)
		val = (u32)cmd << 16 | DCS_SHORT_WRITE << 8;
	else
		val = (u32)param << 24 | (u32)cmd << 16 | DCS_SHORT_WRITE_PARAM << 8;
	writel(val | VM_CMD_EN | TS_VFP_EN, p->dsi + DSI_VM_CMD_CON);
	q25_clear(p, VM_CMD_DONE);
	start = readl(p->dsi + DSI_START);
	writel(start & ~VM_CMD_START, p->dsi + DSI_START);
	writel(start | VM_CMD_START, p->dsi + DSI_START);
	if (readl_poll_timeout(p->dsi + DSI_INTSTA, val, val & VM_CMD_DONE, 100, 50000)) {
		dev_err(p->dev, "DCS %#x: no VM_CMD_DONE\n", cmd);
		return -ETIMEDOUT;
	}
	q25_clear(p, VM_CMD_DONE);
	return 0;
}

/* One DCS short read; returns the byte or a negative error. */
static int q25_dcs_read(struct q25_panel *p, u8 cmd)
{
	u32 mode = readl(p->dsi + DSI_MODE_CTRL);
	u32 val, rx;
	int ret, i;

	if (mode & 3) {
		writel(0, p->dsi + DSI_START);
		q25_clear(p, VM_DONE);
		writel(0, p->dsi + DSI_MODE_CTRL);
		ret = readl_poll_timeout(p->dsi + DSI_INTSTA, val, val & VM_DONE, 100, 500000);
		if (ret)
			goto restore;
	}
	ret = readl_poll_timeout(p->dsi + DSI_INTSTA, val, !(val & DSI_BUSY), 10, 100000);
	if (ret)
		goto restore;

	q25_clear(p, LPRX_RD_RDY | CMD_DONE);
	writel(0x01 << 16 | SET_MAX_RETURN << 8, p->dsi + DSI_CMDQ0);
	writel((u32)cmd << 16 | DCS_READ << 8 | CFG_BTA, p->dsi + DSI_CMDQ0 + 4);
	writel((readl(p->dsi + DSI_CMDQ_SIZE) & ~0x3f) | 2, p->dsi + DSI_CMDQ_SIZE);
	writel(0, p->dsi + DSI_START);
	writel(1, p->dsi + DSI_START);
	ret = readl_poll_timeout(p->dsi + DSI_INTSTA, val, val & LPRX_RD_RDY, 100, 50000);
	if (ret)
		goto restore;

	rx = readl(p->dsi + DSI_RX_DATA0);
	for (i = 0; i < 1000 && (readl(p->dsi + DSI_INTSTA) & DSI_BUSY); i++)
		writel(readl(p->dsi + DSI_RACK) | 1, p->dsi + DSI_RACK);
	q25_clear(p, LPRX_RD_RDY | CMD_DONE);

	if ((rx & 0xff) == RX_DCS_1BYTE)
		ret = (rx >> 8) & 0xff;
	else
		ret = -EIO;
	if (ret < 0)
		dev_warn(p->dev, "DCS read %#x: response %#010x\n", cmd, rx);

restore:
	if (mode & 3) {
		writel(mode, p->dsi + DSI_MODE_CTRL);
		writel(0, p->dsi + DSI_START);
		writel(1, p->dsi + DSI_START);
	}
	return ret;
}

static int q25_sleep(struct q25_panel *p)
{
	int pm, ret;

	ret = q25_dcs_write(p, 0x28, -1);
	msleep(20);
	if (!ret)
		ret = q25_dcs_write(p, 0x10, -1);
	msleep(120);
	pm = ret ? ret : q25_dcs_read(p, 0x0a);
	p->last_pm = pm;
	if (pm < 0 || (pm & (PM_SLEEP_OUT | PM_DISPLAY_ON))) {
		/* Never drop the bias under an awake panel: light it again. */
		dev_err(p->dev, "sleep-in not confirmed (%d); bias kept on\n", pm);
		q25_dcs_write(p, 0x11, -1);
		msleep(120);
		q25_dcs_write(p, 0x29, -1);
		return -EIO;
	}
	gpiod_set_value_cansleep(p->bias, 0);
	dev_info(p->dev, "asleep, power mode %#04x, bias off\n", pm);
	return 0;
}

static int q25_wake_once(struct q25_panel *p)
{
	q25_dcs_write(p, 0x11, -1);
	msleep(120);
	q25_dcs_write(p, 0x29, -1);
	msleep(20);
	return q25_dcs_read(p, 0x0a);
}

static int q25_wake(struct q25_panel *p)
{
	int pm;

	gpiod_set_value_cansleep(p->bias, 1);
	if (p->ocp)
		q25_ocp_set(p, p->code);
	msleep(20);
	pm = q25_wake_once(p);
	if (pm != PM_AWAKE && p->reset) {
		dev_warn(p->dev, "power mode %d after wake; resetting panel\n", pm);
		gpiod_direction_output(p->reset, 0);
		usleep_range(10000, 11000);
		gpiod_set_value_cansleep(p->reset, 1);
		msleep(120);
		pm = q25_wake_once(p);
	}
	p->last_pm = pm;
	if (pm != PM_AWAKE) {
		dev_err(p->dev, "panel not awake after wake (%d)\n", pm);
		return -EIO;
	}
	dev_info(p->dev, "awake, power mode %#04x\n", pm);
	return 0;
}

static int q25_update_status(struct backlight_device *bd)
{
	struct q25_panel *p = bl_get_data(bd);
	int level = backlight_get_brightness(bd);
	bool on = level > 0;
	int ret = 0;

	mutex_lock(&p->lock);
	if (on && p->ocp && level != p->code)
		p->code = level;
	if (on != p->on) {
		ret = on ? q25_wake(p) : q25_sleep(p);
		if (!ret || on)
			p->on = on;
	} else if (on && p->ocp) {
		ret = q25_ocp_set(p, p->code);
	}
	mutex_unlock(&p->lock);
	return ret;
}

static const struct backlight_ops q25_ops = {
	.update_status = q25_update_status,
};

static ssize_t q25_read_attr(struct device *dev, char *buf, u8 cmd)
{
	struct q25_panel *p = dev_get_drvdata(dev);
	int val;

	mutex_lock(&p->lock);
	val = p->on ? q25_dcs_read(p, cmd) : -EAGAIN;
	mutex_unlock(&p->lock);
	return val < 0 ? val : sysfs_emit(buf, "0x%02x\n", val);
}

#define Q25_READ_ATTR(_name, _cmd)						\
static ssize_t _name##_show(struct device *dev, struct device_attribute *a,	\
			    char *buf)						\
{										\
	return q25_read_attr(dev, buf, _cmd);					\
}										\
static DEVICE_ATTR_ADMIN_RO(_name)

Q25_READ_ATTR(power_mode, 0x0a);
Q25_READ_ATTR(signal_mode, 0x0e);
Q25_READ_ATTR(dsi_errors, 0x05);
Q25_READ_ATTR(dcs_brightness, 0x52);
Q25_READ_ATTR(ctrl_display, 0x54);

static ssize_t last_power_mode_show(struct device *dev, struct device_attribute *a, char *buf)
{
	struct q25_panel *p = dev_get_drvdata(dev);

	return sysfs_emit(buf, "%d\n", p->last_pm);
}
static DEVICE_ATTR_RO(last_power_mode);

/* Test hook for the brightness plan: "51 40", "53 2c", "55 00" only. */
static ssize_t dcs_store(struct device *dev, struct device_attribute *a,
			 const char *buf, size_t len)
{
	struct q25_panel *p = dev_get_drvdata(dev);
	unsigned int cmd, param;
	int ret;

	if (sscanf(buf, "%x %x", &cmd, &param) != 2 || param > 0xff ||
	    (cmd != 0x51 && cmd != 0x53 && cmd != 0x55))
		return -EINVAL;
	mutex_lock(&p->lock);
	ret = p->on ? q25_dcs_write(p, cmd, param) : -EAGAIN;
	mutex_unlock(&p->lock);
	return ret ? ret : len;
}
static DEVICE_ATTR_WO(dcs);

static void q25_ocp_release(void *ocp)
{
	i2c_unregister_device(ocp);
}

static int q25_ocp_attach(struct q25_panel *p, unsigned int bus)
{
	struct i2c_adapter *adap;
	struct i2c_client *ocp;
	int id, avdd, avee;

	adap = i2c_get_adapter(bus);
	if (!adap)
		return -ENODEV;
	ocp = i2c_new_dummy_device(adap, OCP_ADDR);
	i2c_put_adapter(adap);
	if (IS_ERR(ocp))
		return PTR_ERR(ocp);
	/* The first transfer after the bus re-probes can NAK. */
	id = i2c_smbus_read_byte_data(ocp, OCP_ID);
	if (id < 0)
		id = i2c_smbus_read_byte_data(ocp, OCP_ID);
	avdd = i2c_smbus_read_byte_data(ocp, OCP_AVDD);
	avee = i2c_smbus_read_byte_data(ocp, OCP_AVEE);
	if ((id != OCP_ID_VALUE && id != OCP_ID_VALUE_Q25) || avdd < 0 || avdd != avee ||
	    avdd > OCP_MAX) {
		dev_warn(p->dev, "OCP2131 not usable (id %d, outputs %d/%d)\n", id, avdd, avee);
		i2c_unregister_device(ocp);
		return id < 0 ? id : -ENODEV;
	}
	if (devm_add_action_or_reset(p->dev, q25_ocp_release, ocp))
		return -ENOMEM;
	p->ocp = ocp;
	p->code = avdd ? avdd : 1;
	/* Readers re-read max_brightness; Marathon picks it up on its next start. */
	WRITE_ONCE(p->bd->props.brightness, p->code);
	WRITE_ONCE(p->bd->props.max_brightness, OCP_MAX);
	dev_info(p->dev, "OCP2131 brightness on i2c-%u, code %#x\n", bus, avdd);
	return 0;
}

static ssize_t ocp_attach_store(struct device *dev, struct device_attribute *a,
				const char *buf, size_t len)
{
	struct q25_panel *p = dev_get_drvdata(dev);
	unsigned int bus;
	int ret;

	if (kstrtouint(buf, 0, &bus))
		return -EINVAL;
	mutex_lock(&p->lock);
	ret = p->ocp ? -EBUSY : q25_ocp_attach(p, bus);
	mutex_unlock(&p->lock);
	return ret ? ret : len;
}
static DEVICE_ATTR_WO(ocp_attach);

static struct attribute *q25_attrs[] = {
	&dev_attr_power_mode.attr,
	&dev_attr_signal_mode.attr,
	&dev_attr_dsi_errors.attr,
	&dev_attr_dcs_brightness.attr,
	&dev_attr_ctrl_display.attr,
	&dev_attr_last_power_mode.attr,
	&dev_attr_dcs.attr,
	&dev_attr_ocp_attach.attr,
	NULL
};
ATTRIBUTE_GROUPS(q25);

static int q25_probe(struct platform_device *pdev)
{
	struct backlight_properties props = {
		.type = BACKLIGHT_RAW,
		.max_brightness = 1,
		.brightness = 1,
		.power = BACKLIGHT_POWER_ON,
	};
	struct device *dev = &pdev->dev;
	struct backlight_device *bd;
	struct q25_panel *p;
	int ret;

	p = devm_kzalloc(dev, sizeof(*p), GFP_KERNEL);
	if (!p)
		return -ENOMEM;
	p->dev = dev;
	p->on = true;
	p->last_pm = -ENODATA;
	mutex_init(&p->lock);

	p->dsi = devm_platform_ioremap_resource(pdev, 0);
	if (IS_ERR(p->dsi))
		return PTR_ERR(p->dsi);
	if (!(readl(p->dsi + DSI_MODE_CTRL) & 3))
		return dev_err_probe(dev, -ENODEV, "DSI is not in video mode\n");

	p->bias = devm_gpiod_get(dev, "bias", GPIOD_ASIS);
	if (IS_ERR(p->bias))
		return dev_err_probe(dev, PTR_ERR(p->bias), "bias gpio\n");
	ret = gpiod_get_value_cansleep(p->bias);
	if (ret != 1)
		return dev_err_probe(dev, -ENODEV, "bias is not on (%d)\n", ret);
	ret = gpiod_direction_output(p->bias, 1);
	if (ret)
		return ret;

	p->reset = devm_gpiod_get_optional(dev, "reset", GPIOD_ASIS);
	if (IS_ERR(p->reset))
		return dev_err_probe(dev, PTR_ERR(p->reset), "reset gpio\n");

	platform_set_drvdata(pdev, p);
	bd = devm_backlight_device_register(dev, "q25-panel", dev, p, &q25_ops, &props);
	if (IS_ERR(bd))
		return dev_err_probe(dev, PTR_ERR(bd), "register\n");
	p->bd = bd;
	dev_info(dev, "panel on, DSI mode %#x\n", readl(p->dsi + DSI_MODE_CTRL));
	return 0;
}

static const struct of_device_id q25_of_match[] = {
	{ .compatible = "zinwa,q25-panel-doze" },
	{ }
};
MODULE_DEVICE_TABLE(of, q25_of_match);

static struct platform_driver q25_driver = {
	.driver = {
		.name = "q25-panel-doze",
		.of_match_table = q25_of_match,
		.dev_groups = q25_groups,
	},
	.probe = q25_probe,
};
module_platform_driver(q25_driver);

MODULE_DESCRIPTION("Zinwa Q25 panel sleep through the firmware DSI host");
MODULE_LICENSE("GPL");
