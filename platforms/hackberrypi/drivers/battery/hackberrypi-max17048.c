/*
        Copyright (C) CNflysky. All rights reserved.
        Fuel Gauge driver for MAX17048 chip found on HackberryPi CM5.
*/

#include <linux/module.h>
#include <linux/power_supply.h>
#include <linux/of.h>
#include <linux/i2c.h>
#include <linux/regmap.h>
#include <linux/property.h>

#define MAX17048_VCELL_REG 0x02
#define MAX17048_SOC_REG 0x04
#define MAX17048_CRATE_REG 0x16

static const struct regmap_config max17048_regmap_cfg = {
	.reg_bits = 8,
	.val_bits = 16,
	.max_register = 0xFF,
	.disable_locking = false,
	.cache_type = REGCACHE_NONE,
};

struct max17048 {
	struct i2c_client *client;
	struct regmap *regmap;
	struct power_supply *battery;
	uint32_t battery_capacity; // mAh
};

static uint32_t max17048_get_vcell(struct max17048 *battery)
{
	uint32_t vcell = 0;
	regmap_read(battery->regmap, MAX17048_VCELL_REG, &vcell);
	return (vcell * 625 / 8);
}

static uint32_t max17048_get_soc(struct max17048 *battery)
{
	uint32_t soc = 0;
	regmap_read(battery->regmap, MAX17048_SOC_REG, &soc);
	return (soc / 256);
}

static int max17048_get_property(struct power_supply *psy,
				 enum power_supply_property psp,
				 union power_supply_propval *val)
{
	struct max17048 *battery = power_supply_get_drvdata(psy);
	switch (psp) {
	case POWER_SUPPLY_PROP_VOLTAGE_NOW:
		val->intval = max17048_get_vcell(battery);
		break;
	case POWER_SUPPLY_PROP_CAPACITY:
		val->intval = max17048_get_soc(battery);
		break;
	case POWER_SUPPLY_PROP_CHARGE_NOW:
		val->intval = max17048_get_soc(battery) *
			      battery->battery_capacity * 10; // uAh
		break;
	case POWER_SUPPLY_PROP_CHARGE_FULL:
		val->intval = battery->battery_capacity * 1000;
		break;
	default:
		return -EINVAL;
	}
	return 0;
}

static enum power_supply_property max17048_battery_props[] = {
	POWER_SUPPLY_PROP_VOLTAGE_NOW, POWER_SUPPLY_PROP_CAPACITY,
	POWER_SUPPLY_PROP_CHARGE_FULL, POWER_SUPPLY_PROP_CHARGE_NOW,
};

static const struct power_supply_desc max17048_battery_desc = {
	.name = "battery",
	.type = POWER_SUPPLY_TYPE_BATTERY,
	.get_property = max17048_get_property,
	.properties = max17048_battery_props,
	.num_properties = ARRAY_SIZE(max17048_battery_props),
};

static int max17048_probe(struct i2c_client *client)
{
	struct device *dev = &client->dev;
	struct max17048 *max17048_desc;
	struct power_supply_config psycfg = {};
	int ret;

	if (!i2c_check_functionality(client->adapter, I2C_FUNC_SMBUS_BYTE))
		return -EIO;

	max17048_desc = devm_kzalloc(dev, sizeof(struct max17048), GFP_KERNEL);
	if (!max17048_desc)
		return -ENOMEM;

	max17048_desc->client = client;
	max17048_desc->regmap =
		devm_regmap_init_i2c(client, &max17048_regmap_cfg);

	ret = device_property_read_u32(dev, "battery-capacity",
				       &max17048_desc->battery_capacity);
	if (ret) {
		dev_warn(dev, "battery-capacity not configured, default 5000");
		max17048_desc->battery_capacity = 5000;
	}

	if (IS_ERR(max17048_desc->regmap))
		return PTR_ERR(max17048_desc->regmap);

	psycfg.drv_data = max17048_desc;

	max17048_desc->battery = devm_power_supply_register(
		dev, &max17048_battery_desc, &psycfg);
	if (IS_ERR(max17048_desc->battery)) {
		dev_err(&client->dev,
			"Failed to register power supply device\n");
		return PTR_ERR(max17048_desc->battery);
	}

	return 0;
}

static struct of_device_id max17048_of_ids[] = {
	{ .compatible = "hackberrypi,max17048-battery" },
	{}
};

MODULE_DEVICE_TABLE(of, max17048_of_ids);

static struct i2c_device_id max17048_i2c_ids[] = { };

static struct i2c_driver max17048_driver = {
	.driver = { .name = "max17048", .of_match_table = max17048_of_ids },
	.probe = max17048_probe,
	.id_table = max17048_i2c_ids
};

module_i2c_driver(max17048_driver);

MODULE_DESCRIPTION("MAX17048 fuel gauge driver for HackBerryPi CM5");
MODULE_AUTHOR("CNflysky <cnflysky@qq.com>");
MODULE_LICENSE("GPL");
