// SPDX-License-Identifier: GPL-2.0
/*
 * Q25 vibration motor: mainline regulator-haptic on the MT6366 vibr LDO,
 * as stock's regulator-vibrator drives it. The board DT has no haptic node,
 * so this makes the device and points its "haptic" supply at the rail.
 */
#include <linux/module.h>
#include <linux/platform_data/regulator-haptic.h>
#include <linux/platform_device.h>
#include <linux/regulator/consumer.h>

static const struct regulator_haptic_data q25_haptic_data = {
	.max_volt = 2800000,
	.min_volt = 2800000,
};

static struct platform_device *q25_haptic;

static int __init q25_haptic_init(void)
{
	struct platform_device *pdev;
	int ret;

	pdev = platform_device_alloc("regulator-haptic", PLATFORM_DEVID_NONE);
	if (!pdev)
		return -ENOMEM;
	ret = platform_device_add_data(pdev, &q25_haptic_data, sizeof(q25_haptic_data));
	if (ret)
		goto put;
	ret = regulator_register_supply_alias(&pdev->dev, "haptic", &pdev->dev, "vibr");
	if (ret)
		goto put;
	ret = platform_device_add(pdev);
	if (ret)
		goto alias;
	q25_haptic = pdev;
	return 0;
alias:
	regulator_unregister_supply_alias(&pdev->dev, "haptic");
put:
	platform_device_put(pdev);
	return ret;
}
module_init(q25_haptic_init);

static void __exit q25_haptic_exit(void)
{
	regulator_unregister_supply_alias(&q25_haptic->dev, "haptic");
	platform_device_unregister(q25_haptic);
}
module_exit(q25_haptic_exit);

MODULE_DESCRIPTION("Zinwa Q25 vibration motor");
MODULE_LICENSE("GPL");
MODULE_SOFTDEP("post: regulator-haptic");
