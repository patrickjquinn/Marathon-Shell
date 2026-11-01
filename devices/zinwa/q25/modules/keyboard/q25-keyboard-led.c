// SPDX-License-Identifier: GPL-2.0-only
/* Manual sidecar to existing Q25 keyboard. No FIFO/CFG/GPIO/reset access. */
#include <linux/device.h>
#include <linux/i2c.h>
#include <linux/leds.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/slab.h>
#include "q25-bkl-protocol.h"

static bool enable_control;
module_param(enable_control, bool, 0644);
MODULE_PARM_DESC(enable_control, "Explicit opt-in to BKL05 control; N disables further writes");
static char *client_name;
module_param(client_name, charp, 0444);
MODULE_PARM_DESC(client_name, "Existing bound keyboard I2C client, verified6-001f onQ25");

struct q25_keyboard_led {
	struct i2c_client *client;
	struct led_classdev led;
	struct mutex lock;
	struct q25_bkl_io io;
	int last_error;
};
static struct q25_keyboard_led *sidecar;

static bool q25_client_ready(struct q25_keyboard_led *kbd)
{
	struct device *dev = &kbd->client->dev;

	return device_is_registered(dev) && dev->driver &&
		!strcmp(dev->driver->name, "q25_bbq_keys");
}

static int q25_read(void *ctx, unsigned int reg)
{
	return i2c_smbus_read_byte_data(ctx, reg);
}

static int q25_write(void *ctx, unsigned int command, unsigned int value)
{
	if (command != Q25_BKL_COMMAND || value > 255)
		return -EPERM;
	return i2c_smbus_write_byte_data(ctx, command, value);
}

static enum led_brightness q25_brightness_get(struct led_classdev *led)
{
	struct q25_keyboard_led *kbd = container_of(led, struct q25_keyboard_led, led);
	int ret;

	/* Preserve desired brightness while core temporarily writes0 for suspend. */
	if ((led->flags & LED_SUSPENDED) || !READ_ONCE(enable_control))
		return led->brightness;
	mutex_lock(&kbd->lock);
	ret = q25_client_ready(kbd) ? q25_bkl_get(&kbd->io) : -ENODEV;
	if (ret < 0)
		kbd->last_error = ret;
	mutex_unlock(&kbd->lock);
	return ret < 0 ? led->brightness : ret;
}

static int q25_brightness_set(struct led_classdev *led, enum led_brightness value)
{
	struct q25_keyboard_led *kbd = container_of(led, struct q25_keyboard_led, led);
	int ret;

	mutex_lock(&kbd->lock);
	if (!READ_ONCE(enable_control))
		ret = -EPERM;
	else if (!q25_client_ready(kbd))
		ret = -ENODEV;
	else
		ret = q25_bkl_set(&kbd->io, value);
	kbd->last_error = ret;
	mutex_unlock(&kbd->lock);
	if (ret)
		dev_err_ratelimited(&kbd->client->dev, "BKL05 write/readback failed:%d\n", ret);
	return ret;
}

static ssize_t last_error_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	struct led_classdev *led = dev_get_drvdata(dev);
	struct q25_keyboard_led *kbd = container_of(led, struct q25_keyboard_led, led);
	int ret;

	mutex_lock(&kbd->lock);
	ret = sysfs_emit(buf, "%d\n", kbd->last_error);
	mutex_unlock(&kbd->lock);
	return ret;
}
static DEVICE_ATTR_RO(last_error);
static struct attribute *q25_attrs[] = { &dev_attr_last_error.attr, NULL };
ATTRIBUTE_GROUPS(q25);

static int __init q25_led_init(void)
{
	struct i2c_client *client;
	struct device *dev;
	int level, ret;

	if (!enable_control || !client_name || !*client_name)
		return -EPERM;
	dev = bus_find_device_by_name(&i2c_bus_type, NULL, client_name);
	if (!dev)
		return -ENODEV;
	client = i2c_verify_client(dev);
	if (!client || client->addr != 0x1f || !dev->driver ||
	    strcmp(dev->driver->name, "q25_bbq_keys") ||
	    !client->adapter->dev.of_node ||
	    strcmp(kbasename(of_node_full_name(client->adapter->dev.of_node)), "i2c@1101a000")) {
		ret = -ENODEV;
		goto put;
	}
	if (!i2c_check_functionality(client->adapter, I2C_FUNC_SMBUS_BYTE_DATA)) {
		ret = -EOPNOTSUPP;
		goto put;
	}
	sidecar = kzalloc(sizeof(*sidecar), GFP_KERNEL);
	if (!sidecar) {
		ret = -ENOMEM;
		goto put;
	}
	sidecar->client = client;
	mutex_init(&sidecar->lock);
	sidecar->io = (struct q25_bkl_io) {
		.ctx = client, .read = q25_read, .write = q25_write,
	};
	/* Preserve firmware state: read05 only, never force a level on load. */
	level = q25_bkl_get(&sidecar->io);
	if (level < 0) {
		ret = level;
		goto free;
	}
	sidecar->led.name = "q25::kbd_backlight";
	sidecar->led.max_brightness = 255;
	sidecar->led.brightness = level;
	sidecar->led.brightness_get = q25_brightness_get;
	sidecar->led.brightness_set_blocking = q25_brightness_set;
	sidecar->led.groups = q25_groups;
	sidecar->led.flags = LED_REJECT_NAME_CONFLICT | LED_RETAIN_AT_SHUTDOWN |
		LED_CORE_SUSPENDRESUME;
	ret = led_classdev_register(&client->dev, &sidecar->led);
	if (ret)
		goto free;
	dev_info(dev, "native keyboard LED05 registered; initial%d; no probe writes\n", level);
	return 0;
free:
	kfree(sidecar);
put:
	put_device(dev);
	return ret;
}
module_init(q25_led_init);

static void __exit q25_led_exit(void)
{
	led_classdev_unregister(&sidecar->led);
	put_device(&sidecar->client->dev);
	kfree(sidecar);
}
module_exit(q25_led_exit);

/* No modalias autoload: parent explicitly opts in after protocol review. */
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Q25 independent LED05 control on existing native keyboard client");
MODULE_AUTHOR("Q25 native source review; protocol from wallComputer/MediaTek vendor source");
