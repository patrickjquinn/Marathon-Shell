#include <linux/module.h>
#include <linux/export-internal.h>
#include <linux/compiler.h>

MODULE_INFO(name, KBUILD_MODNAME);

__visible struct module __this_module
__section(".gnu.linkonce.this_module") = {
	.name = KBUILD_MODNAME,
	.init = init_module,
#ifdef CONFIG_MODULE_UNLOAD
	.exit = cleanup_module,
#endif
	.arch = MODULE_ARCH_INIT,
};



static const struct modversion_info ____versions[]
__used __section("__versions") = {
	{ 0x4e8e25be, "i2c_register_driver" },
	{ 0x36a78de3, "devm_kmalloc" },
	{ 0x929c4eb7, "__devm_regmap_init_i2c" },
	{ 0x72109e18, "device_property_read_u32_array" },
	{ 0x85dc3ccb, "devm_power_supply_register" },
	{ 0xf0fdf6cb, "__stack_chk_fail" },
	{ 0x3ed097c3, "_dev_err" },
	{ 0x40dd8548, "_dev_warn" },
	{ 0x2cfa9196, "i2c_del_driver" },
	{ 0x639e2de9, "power_supply_get_drvdata" },
	{ 0x9ba6295b, "regmap_read" },
	{ 0x474e54d2, "module_layout" },
};

MODULE_INFO(depends, "regmap-i2c");

MODULE_ALIAS("of:N*T*Chackberrypi,max17048-battery");
MODULE_ALIAS("of:N*T*Chackberrypi,max17048-batteryC*");

MODULE_INFO(srcversion, "9E9F0F51E6A2A09B665601D");
