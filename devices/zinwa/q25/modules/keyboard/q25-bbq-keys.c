// SPDX-License-Identifier: GPL-2.0-only
/*
 * Q25 native keyboard power/configuration candidate. FIFO format and keymap derived
 * from wallComputer's GPL BBQX0 driver and the pinned Q25 vendor source.
 * New lifecycle/polling glue is AI-authored; see PROVENANCE.json.
 */
#include <linux/bitops.h>
#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/i2c.h>
#include <linux/input.h>
#include <linux/interrupt.h>
#include <linux/irq.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/mutex.h>
#include <linux/slab.h>
#include <linux/workqueue.h>

#define BBQ20KBD_TRACKPAD_AS_MOUSE 0
#define BBQ20KBD_TRACKPAD_AS_KEYS 1
#define BBQ20KBD_TRACKPAD_USE BBQ20KBD_TRACKPAD_AS_KEYS
#include "bbq20kbd_pmod_codes.h"

#define BBQ_VERSION 0x01
#define BBQ_CONFIG 0x02
#define BBQ_WRITE BIT(7)
#define BBQ_INTERRUPT 0x03
#define BBQ_COUNT 0x04
#define BBQ_FIFO 0x09
#define BBQ_RAW_MODIFIERS BIT(6)
#define BBQ_TRANSLATE_MODIFIERS BIT(7)
#define BBQ_STOCK_CONFIG 0x53
#define BBQ_PRESSED 1
#define BBQ_RELEASED 3
#define BBQ_POLL_MS 40

static bool use_irq = true;
module_param(use_irq, bool, 0444);
MODULE_PARM_DESC(use_irq, "Optional preconfigured IRQ; polling always remains active");

static bool configure_raw = true;
module_param(configure_raw, bool, 0444);
MODULE_PARM_DESC(configure_raw, "Set stock CFG bits0/1/4/6, clear bit7, preserve bits2/3/5");

static bool ack_irq = true;
module_param(ack_irq, bool, 0444);
MODULE_PARM_DESC(ack_irq, "Vendor INT acknowledgment (83 00) after successful poll/IRQ drain");

struct bbq_handoff {
	struct i2c_client *client;
	struct input_dev *input;
	struct delayed_work poll;
	struct mutex lock; /* Serializes FIFO consumption, activation and close. */
	unsigned short codes[NUM_KEYCODES];
	bool active;
	struct gpio_desc *vdd, *v1v8, *v2v8;
};

/* Caller holds lock: IRQ and poll must never concurrently consume FIFO. */
static void bbq_drain(struct bbq_handoff *kbd)
{
	int status, raw_count, count, pair, i, ret;
	unsigned int state, scan, code;
	bool reported = false, complete = true;

	status = i2c_smbus_read_byte_data(kbd->client, BBQ_INTERRUPT);
	if (status < 0)
		goto read_error;
	raw_count = i2c_smbus_read_byte_data(kbd->client, BBQ_COUNT);
	if (raw_count < 0)
		goto read_error;
	count = raw_count & 0x1f;
	/* Stock FIFO capacity31; upper count-register bits are lock flags. */
	for (i = 0; i < count; i++) {
		pair = i2c_smbus_read_word_data(kbd->client, BBQ_FIFO);
		if (pair < 0) {
			complete = false;
			break;
		}
		if (!pair)
			break;
		state = pair & 0xff;
		scan = (pair >> 8) & 0xff;
		if (state != BBQ_PRESSED && state != BBQ_RELEASED)
			continue;
		input_event(kbd->input, EV_MSC, MSC_SCAN, scan);
		reported = true;
		code = kbd->codes[scan];
		if (code != KEY_RESERVED && code != KEY_UNKNOWN)
			input_report_key(kbd->input, code, state == BBQ_PRESSED);
	}
	if (reported)
		input_sync(kbd->input);
	/* INT is ordinary R/W, not read-to-clear. Stock clears it with83,00.
	 * Do this in the shared poll/IRQ path, never after a failed FIFO read.
	 * New arrivals racing this acknowledgment remain visible to next poll.
	 */
	if (complete && status && ack_irq) {
		ret = i2c_smbus_write_byte_data(kbd->client,
					      BBQ_INTERRUPT | BBQ_WRITE, 0);
		if (ret < 0)
			dev_err_ratelimited(&kbd->client->dev, "INT acknowledgment failed\n");
	}
	return;

read_error:
	dev_err_ratelimited(&kbd->client->dev, "INT/count read failed\n");
}

static void bbq_poll(struct work_struct *work)
{
	struct bbq_handoff *kbd = container_of(to_delayed_work(work),
					     struct bbq_handoff, poll);

	mutex_lock(&kbd->lock);
	if (kbd->active) {
		bbq_drain(kbd);
		schedule_delayed_work(&kbd->poll, msecs_to_jiffies(BBQ_POLL_MS));
	}
	mutex_unlock(&kbd->lock);
}

static irqreturn_t bbq_irq(int irq, void *data)
{
	struct bbq_handoff *kbd = data;

	mutex_lock(&kbd->lock);
	if (kbd->active)
		bbq_drain(kbd);
	mutex_unlock(&kbd->lock);
	return IRQ_HANDLED;
}

static int bbq_open(struct input_dev *input)
{
	struct bbq_handoff *kbd = input_get_drvdata(input);

	mutex_lock(&kbd->lock);
	kbd->active = true;
	schedule_delayed_work(&kbd->poll, 0);
	mutex_unlock(&kbd->lock);
	return 0;
}

static void bbq_close(struct input_dev *input)
{
	struct bbq_handoff *kbd = input_get_drvdata(input);

	mutex_lock(&kbd->lock);
	kbd->active = false;
	mutex_unlock(&kbd->lock);
	cancel_delayed_work_sync(&kbd->poll);
}

/* Request every descriptor without changing levels before enabling any rail.
 * No disable action: removal/error must not deliberately pulse these lines low.
 * GPIO47 (firmware download), reset and backlight are never requested here.
 */
static int bbq_power_enable(struct bbq_handoff *kbd)
{
	struct device *dev = &kbd->client->dev;
	int ret;

	kbd->vdd = devm_gpiod_get_optional(dev, "power-vdd", GPIOD_ASIS);
	if (IS_ERR(kbd->vdd))
		return dev_err_probe(dev, PTR_ERR(kbd->vdd), "Get VDD enable\n");
	kbd->v1v8 = devm_gpiod_get_optional(dev, "power-1v8", GPIOD_ASIS);
	if (IS_ERR(kbd->v1v8))
		return dev_err_probe(dev, PTR_ERR(kbd->v1v8), "Get 1V8 enable\n");
	kbd->v2v8 = devm_gpiod_get_optional(dev, "power-2v8", GPIOD_ASIS);
	if (IS_ERR(kbd->v2v8))
		return dev_err_probe(dev, PTR_ERR(kbd->v2v8), "Get 2V8 enable\n");
	if (!kbd->vdd && !kbd->v1v8 && !kbd->v2v8)
		return 0; /* Already powered handoff; no inferred GPIO numbers. */
	if (!kbd->vdd || !kbd->v1v8 || !kbd->v2v8)
		return dev_err_probe(dev, -EINVAL, "Require all three power enables\n");
	if (gpiod_is_active_low(kbd->vdd) || gpiod_is_active_low(kbd->v1v8) ||
	    gpiod_is_active_low(kbd->v2v8))
		return dev_err_probe(dev, -EINVAL, "Stock Q25 enables must be active high\n");
	ret = gpiod_direction_output(kbd->vdd, 1);
	if (ret)
		return ret;
	usleep_range(10000, 11000);
	ret = gpiod_direction_output(kbd->v1v8, 1);
	if (ret)
		return ret;
	ret = gpiod_direction_output(kbd->v2v8, 1);
	if (ret)
		return ret;
	/* Stock power settle (10ms) followed by probe startup (400ms). */
	msleep(410);
	return 0;
}

static int bbq_probe(struct i2c_client *client)
{
	struct bbq_handoff *kbd;
	struct input_dev *input;
	int version, config, desired, ret, i;

	if (client->addr != 0x1f)
		return -ENODEV;
	if (!i2c_check_functionality(client->adapter,
				     I2C_FUNC_SMBUS_BYTE_DATA | I2C_FUNC_SMBUS_WORD_DATA))
		return -EOPNOTSUPP;
	kbd = devm_kzalloc(&client->dev, sizeof(*kbd), GFP_KERNEL);
	if (!kbd)
		return -ENOMEM;
	kbd->client = client;
	ret = bbq_power_enable(kbd);
	if (ret)
		return ret;
	version = i2c_smbus_read_byte_data(client, BBQ_VERSION);
	if (version < 0)
		return version;
	config = i2c_smbus_read_byte_data(client, BBQ_CONFIG);
	if (config < 0)
		return config;
	desired = (config | BBQ_STOCK_CONFIG) & ~BBQ_TRANSLATE_MODIFIERS;
	if (config != desired && configure_raw) {
		/* Vendor protocol uses register | 0x80 for writes: CFG wire82. */
		ret = i2c_smbus_write_byte_data(client, BBQ_CONFIG | BBQ_WRITE, desired);
		if (ret < 0)
			return dev_err_probe(&client->dev, ret, "Configure raw key reporting\n");
		config = i2c_smbus_read_byte_data(client, BBQ_CONFIG);
		if (config < 0)
			return config;
		if (config != desired)
			return dev_err_probe(&client->dev, -EIO, "CFG readback mismatch\n");
	}
	if (!(config & BBQ_RAW_MODIFIERS) || (config & BBQ_TRANSLATE_MODIFIERS))
		return dev_err_probe(&client->dev, -EOPNOTSUPP,
			"Firmware cfg=%02x not raw/modifier-reporting\n", config);
	input = devm_input_allocate_device(&client->dev);
	if (!input)
		return -ENOMEM;
	kbd->client = client;
	kbd->input = input;
	mutex_init(&kbd->lock);
	INIT_DELAYED_WORK(&kbd->poll, bbq_poll);
	memcpy(kbd->codes, keycodes, sizeof(kbd->codes));
	/* Vendor lowercase g/h are dummy capability slots, not raw key events.
	 * Do not advertise mouse buttons on the keyboard input device.
	 * A future real trackpad transport requires its own input device.
	 */
	kbd->codes['g'] = KEY_RESERVED;
	kbd->codes['h'] = KEY_RESERVED;
	input->name = "Q25 native BBQ keyboard";
	input->id.bustype = BUS_I2C;
	input->id.version = version;
	input->open = bbq_open;
	input->close = bbq_close;
	input->keycode = kbd->codes;
	input->keycodesize = sizeof(kbd->codes[0]);
	input->keycodemax = ARRAY_SIZE(kbd->codes);
	input_set_drvdata(input, kbd);
	input_set_capability(input, EV_MSC, MSC_SCAN);
	__set_bit(EV_REP, input->evbit);
	for (i = 0; i < ARRAY_SIZE(kbd->codes); i++)
		if (kbd->codes[i] != KEY_RESERVED && kbd->codes[i] != KEY_UNKNOWN)
			input_set_capability(input, EV_KEY, kbd->codes[i]);
	i2c_set_clientdata(client, kbd);
	if (use_irq && client->irq > 0) {
		if (irq_get_trigger_type(client->irq) != IRQ_TYPE_EDGE_FALLING)
			return dev_err_probe(&client->dev, -EINVAL,
					     "Require preconfigured falling-edge IRQ\n");
		ret = devm_request_threaded_irq(&client->dev, client->irq, NULL,
						bbq_irq, IRQF_ONESHOT,
						dev_name(&client->dev), kbd);
		if (ret)
			return ret;
	}
	ret = input_register_device(input);
	if (ret)
		return ret;
	dev_info(&client->dev, "fw=%02x cfg=%02x; stock CFG/INT ack; no reset/backlight writes\n",
		 version, config);
	return 0;
}

static void bbq_remove(struct i2c_client *client)
{
	struct bbq_handoff *kbd = i2c_get_clientdata(client);

	bbq_close(kbd->input);
}

static const struct i2c_device_id bbq_ids[] = {
	{ "q25_bbq_keys" },
	{ }
};
MODULE_DEVICE_TABLE(i2c, bbq_ids);

static const struct of_device_id bbq_of_match[] = {
	{ .compatible = "zinwa,q25-bbq-keys" },
	{ }
};
MODULE_DEVICE_TABLE(of, bbq_of_match);

static struct i2c_driver bbq_driver = {
	.driver = {
		.name = "q25_bbq_keys",
		.of_match_table = bbq_of_match,
	},
	.probe = bbq_probe,
	.remove = bbq_remove,
	.shutdown = bbq_remove,
	.id_table = bbq_ids,
};
module_i2c_driver(bbq_driver);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("wallComputer (protocol/keymap); Codex (experimental handoff adaptation)");
MODULE_DESCRIPTION("Q25 keyboard stock power/config/INT ack with polling fallback");
