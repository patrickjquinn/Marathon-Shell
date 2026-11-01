// SPDX-License-Identifier: GPL-2.0-only
/*
 * Zinwa Q25: the MT6789 imp_iic_wrap gates name their parent "top_i2c"
 * (clk-mt6789-imp_iic_wrap.c), a clock this topckgen never registers, so every
 * I2C "main" clock is an orphan at 0 Hz. Register "top_i2c" as a critical 1:1
 * alias of i2c_pseudo_ck, the stock parent (vendor clk-mt6789-i2c.c): the
 * orphans adopt it and report 124.8 MHz, and i2c_sel can never be gated by an
 * I2C clock disable. A controller re-probed afterwards computes real timing.
 */
#include <linux/clk-provider.h>
#include <linux/module.h>

static int __init q25_i2c_clk_init(void)
{
	struct clk_hw *hw;
	unsigned long rate;

	hw = clk_hw_register_fixed_factor(NULL, "top_i2c", "i2c_pseudo_ck",
					  CLK_IS_CRITICAL, 1, 1);
	if (IS_ERR(hw))
		return PTR_ERR(hw);
	rate = clk_hw_get_rate(hw);
	if (!rate)
		pr_err("q25-i2c-clk: top_i2c has no rate (i2c_pseudo_ck missing?)\n");
	else
		pr_info("q25-i2c-clk: top_i2c -> i2c_pseudo_ck, %lu Hz\n", rate);
	return 0;
}
module_init(q25_i2c_clk_init);

MODULE_DESCRIPTION("Zinwa Q25 top_i2c clock alias");
MODULE_LICENSE("GPL");
