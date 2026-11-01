// SPDX-License-Identifier: GPL-2.0
/*
 * The MT6358/MT6366 report the AUD and MISC top interrupt groups at bits 7
 * and 8; mainline uses 6 and 7. Give the irq chip a corrected group table.
 * No exit: the chip keeps the pointer.
 */
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_platform.h>
#include <linux/platform_device.h>
#include <linux/string.h>
#include <linux/mfd/mt6358/core.h>
#include <linux/mfd/mt6358/registers.h>
#include <linux/mfd/mt6397/core.h>

#define Q25_AUD_TOP_BIT		7
#define Q25_MISC_TOP_BIT	8

static struct irq_top_t q25_ints[8];

static int __init q25_irqfix_init(void)
{
	struct device_node *np = of_find_compatible_node(NULL, NULL, "mediatek,mt6358");
	struct platform_device *pdev = np ? of_find_device_by_node(np) : NULL;
	struct mt6397_chip *chip = pdev ? platform_get_drvdata(pdev) : NULL;
	struct pmic_irq_data *irqd;
	int i, ret = -ENODEV;

	of_node_put(np);
	if (!chip || (chip->chip_id != MT6358_CHIP_ID && chip->chip_id != MT6366_CHIP_ID))
		goto out;
	irqd = chip->irq_data;
	if (!irqd || irqd->num_top != ARRAY_SIZE(q25_ints))
		goto out;

	memcpy(q25_ints, irqd->pmic_ints, sizeof(q25_ints));
	for (i = 0; i < ARRAY_SIZE(q25_ints); i++) {
		if (q25_ints[i].sta_reg == MT6358_AUD_TOP_INT_STATUS0)
			q25_ints[i].top_offset = Q25_AUD_TOP_BIT;
		else if (q25_ints[i].sta_reg == MT6358_MISC_TOP_INT_STATUS0)
			q25_ints[i].top_offset = Q25_MISC_TOP_BIT;
	}
	ret = 0;
	if (!memcmp(q25_ints, irqd->pmic_ints, sizeof(q25_ints))) {
		pr_info("q25-irqfix: PMIC top bits already correct\n");
		goto out;
	}
	WRITE_ONCE(irqd->pmic_ints, q25_ints);
	pr_info("q25-irqfix: PMIC 0x%x AUD/MISC top bits set to %d/%d\n",
		chip->chip_id, Q25_AUD_TOP_BIT, Q25_MISC_TOP_BIT);
out:
	if (pdev)
		put_device(&pdev->dev);
	return ret;
}
module_init(q25_irqfix_init);

MODULE_DESCRIPTION("Zinwa Q25: MT6358/MT6366 PMIC AUD/MISC interrupt group bits");
MODULE_LICENSE("GPL");
