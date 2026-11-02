// SPDX-License-Identifier: GPL-2.0-only
/*
 * Orient-Chip OCA72390 class-K speaker amplifier (Zinwa Q25, i2c3 @0x58).
 *
 * Register-compatible with the Awinic AW87390 (ID 0x76); the OCA part reports
 * 0x11, which the stock driver files under the same "76" register map. The stock vendor
 * driver (snd-soc-oca72xxx) only writes the register lists from
 * /vendor/firmware/ocs72xxx_cf.bin; the two lists used by the stock machine
 * driver ("Music" on, "Off" on shutdown) are embedded here verbatim, so no
 * firmware file is needed.
 */
#include <linux/delay.h>
#include <linux/i2c.h>
#include <linux/module.h>
#include <linux/regmap.h>
#include <sound/soc.h>

#define OCA_ID_REG		0x00
#define OCA_SYSCTRL_REG		0x01
#define OCA_PAG_REG		0x05
#define OCA_ID			0x11
#define AW87390_ID		0x76
#define OCA_MAX_REG		0x78

static const struct reg_sequence oca_music[] = {
	{ 0x01, 0x0d }, { 0x02, 0x1c }, { 0x03, 0x08 }, { 0x04, 0x09 },
	{ 0x05, 0x0e }, { 0x06, 0x08 }, { 0x07, 0x56 }, { 0x08, 0x87 },
	{ 0x09, 0x12 }, { 0x0a, 0xca }, { 0x0b, 0x26 },
};

static const struct reg_sequence oca_off[] = {
	{ 0x01, 0x0c }, { 0x02, 0x0c }, { 0x03, 0x0a }, { 0x04, 0x09 },
	{ 0x05, 0x0a }, { 0x06, 0x09 }, { 0x07, 0x4e }, { 0x08, 0x04 },
	{ 0x09, 0x12 }, { 0x0a, 0x4a }, { 0x0b, 0x26 },
};

struct oca72390 {
	struct regmap *regmap;
	unsigned int pag;	/* 0 = keep the stock Music value */
};

static void oca_dump(struct device *dev, struct regmap *map, const char *when)
{
	unsigned int v[12];
	int i;

	for (i = 0; i < ARRAY_SIZE(v); i++)
		if (regmap_read(map, i, &v[i]))
			v[i] = 0xff;
	dev_info(dev, "%s: regs 00-0b = %*ph\n", when, (int)ARRAY_SIZE(v),
		 (u8[]){ v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7],
			 v[8], v[9], v[10], v[11] });
}

static int oca_pa_event(struct snd_soc_dapm_widget *w,
			struct snd_kcontrol *kcontrol, int event)
{
	struct snd_soc_component *c = snd_soc_dapm_to_component(w->dapm);
	struct oca72390 *oca = snd_soc_component_get_drvdata(c);
	int ret = 0;

	switch (event) {
	case SND_SOC_DAPM_POST_PMU:
		ret = regmap_multi_reg_write(oca->regmap, oca_music,
					     ARRAY_SIZE(oca_music));
		if (!ret && oca->pag)
			ret = regmap_write(oca->regmap, OCA_PAG_REG, oca->pag);
		oca_dump(c->dev, oca->regmap, "on");
		break;
	case SND_SOC_DAPM_PRE_PMD:
		ret = regmap_multi_reg_write(oca->regmap, oca_off,
					     ARRAY_SIZE(oca_off));
		break;
	}
	if (ret)
		dev_err(c->dev, "PA event %d failed: %d\n", event, ret);
	return ret;
}

static int oca_pag_get(struct snd_kcontrol *kc, struct snd_ctl_elem_value *uc)
{
	struct snd_soc_component *c = snd_kcontrol_chip(kc);
	struct oca72390 *oca = snd_soc_component_get_drvdata(c);

	uc->value.integer.value[0] = oca->pag;
	return 0;
}

static int oca_pag_put(struct snd_kcontrol *kc, struct snd_ctl_elem_value *uc)
{
	struct snd_soc_component *c = snd_kcontrol_chip(kc);
	struct oca72390 *oca = snd_soc_component_get_drvdata(c);
	unsigned int v = uc->value.integer.value[0];

	if (v > 0x0e)
		return -EINVAL;
	if (v == oca->pag)
		return 0;
	oca->pag = v;
	return 1;
}

/* PAG 1..14 overrides the stock Music gain (0x0e) at next power-up; 0 = stock */
static const struct snd_kcontrol_new oca_controls[] = {
	SOC_SINGLE_EXT("PA Gain Override", SND_SOC_NOPM, 0, 0x0e, 0,
		       oca_pag_get, oca_pag_put),
};

static const struct snd_soc_dapm_widget oca_widgets[] = {
	SND_SOC_DAPM_INPUT("IN"),
	SND_SOC_DAPM_OUT_DRV_E("PA", SND_SOC_NOPM, 0, 0, NULL, 0, oca_pa_event,
			       SND_SOC_DAPM_POST_PMU | SND_SOC_DAPM_PRE_PMD),
	SND_SOC_DAPM_OUTPUT("OUT"),
};

static const struct snd_soc_dapm_route oca_routes[] = {
	{ "PA", NULL, "IN" },
	{ "OUT", NULL, "PA" },
};

static const struct snd_soc_component_driver oca_component = {
	.controls = oca_controls,
	.num_controls = ARRAY_SIZE(oca_controls),
	.dapm_widgets = oca_widgets,
	.num_dapm_widgets = ARRAY_SIZE(oca_widgets),
	.dapm_routes = oca_routes,
	.num_dapm_routes = ARRAY_SIZE(oca_routes),
};

static const struct regmap_config oca_regmap = {
	.reg_bits = 8,
	.val_bits = 8,
	.max_register = OCA_MAX_REG,
	.cache_type = REGCACHE_NONE,
};

static int oca_probe(struct i2c_client *client)
{
	struct device *dev = &client->dev;
	struct oca72390 *oca;
	unsigned int id;
	int ret;

	oca = devm_kzalloc(dev, sizeof(*oca), GFP_KERNEL);
	if (!oca)
		return -ENOMEM;

	oca->regmap = devm_regmap_init_i2c(client, &oca_regmap);
	if (IS_ERR(oca->regmap))
		return PTR_ERR(oca->regmap);

	ret = regmap_read(oca->regmap, OCA_ID_REG, &id);
	if (ret)
		return dev_err_probe(dev, ret, "no answer at 0x%02x\n", client->addr);
	if (id != OCA_ID && id != AW87390_ID)
		return dev_err_probe(dev, -ENODEV, "unexpected ID 0x%02x\n", id);

	/* probe is read-only: the chip is not reset or reprogrammed here */
	oca_dump(dev, oca->regmap, "probe");
	i2c_set_clientdata(client, oca);

	return devm_snd_soc_register_component(dev, &oca_component, NULL, 0);
}

static void oca_shutdown(struct i2c_client *client)
{
	struct oca72390 *oca = i2c_get_clientdata(client);

	if (oca)
		regmap_multi_reg_write(oca->regmap, oca_off, ARRAY_SIZE(oca_off));
}

static const struct of_device_id oca_of_match[] = {
	{ .compatible = "ocs,oca72390" },
	{ }
};
MODULE_DEVICE_TABLE(of, oca_of_match);

static struct i2c_driver oca_driver = {
	.driver = {
		.name = "q25-oca72390",
		.of_match_table = oca_of_match,
	},
	.probe = oca_probe,
	.shutdown = oca_shutdown,
};
module_i2c_driver(oca_driver);

MODULE_DESCRIPTION("OCA72390 speaker amplifier for Zinwa Q25");
MODULE_LICENSE("GPL");
