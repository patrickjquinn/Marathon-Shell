// SPDX-License-Identifier: GPL-2.0
/*
 * Zinwa Q25 (MT6789 AFE + MT6366 codec + OCA72390 speaker PA) machine driver.
 *
 * One playback FE (DL1) and one capture FE (UL1/VUL12) on the ADDA BE.
 * Routing follows the stock audio_device.xml: speaker = LOL -> PA,
 * earpiece = RCV, headphones = HPL/HPR, main mic AIN0, headset mic AIN1,
 * second mic AIN2. MTKAIF protocol 1 (no calibration), as mt8186-mt6366.
 */
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/pm_runtime.h>
#include <linux/regmap.h>
#include <sound/soc.h>

#include "../codecs/mt6358.h"
#include "../mediatek/common/mtk-afe-platform-driver.h"
#include "../mediatek/mt6789/mt6789-afe-common.h"
#include "../mediatek/mt6789/mt6789-afe-clk.h"
#include "../mediatek/mt6789/mt6789-afe-gpio.h"
#include "../mediatek/mt6789/mt6789-reg.h"

static bool use_amp = true;
module_param(use_amp, bool, 0444);
MODULE_PARM_DESC(use_amp, "bind the OCA72390 speaker PA as aux device (default on)");

static int mtkaif = 3;
module_param(mtkaif, int, 0444);
MODULE_PARM_DESC(mtkaif, "MTKAIF protocol: 1, 2, 3 = protocol 2 clk-p2 with phase calibration (default, verified)");

/* Port of the stock mt6789_mt6366_mtkaif_calibration(); logs per-phase results. */
static void q25_mtkaif_calibration(struct mtk_base_afe *afe,
				   struct snd_soc_component *codec)
{
	struct mt6789_afe_private *afe_priv = afe->platform_priv;
	int phase, counter, cycle_1, cycle_2, prev_1 = -1, prev_2 = -1;
	int done_1, done_2, need_0, need_1;
	unsigned int monitor = 0;
	bool ok = true;

	pm_runtime_get_sync(afe->dev);
	need_0 = mt6789_afe_gpio_is_prepared(MT6789_AFE_GPIO_DAT_MISO0_ON);
	need_1 = mt6789_afe_gpio_is_prepared(MT6789_AFE_GPIO_DAT_MISO1_ON);
	mt6789_afe_gpio_request(afe, true, MT6789_DAI_ADDA, 1);
	mt6789_afe_gpio_request(afe, true, MT6789_DAI_ADDA, 0);
	mt6358_mtkaif_calibration_enable(codec);

	regmap_update_bits(afe->regmap, AFE_AUD_PAD_TOP, 0xff, 0x38);
	regmap_update_bits(afe->regmap, AFE_AUD_PAD_TOP, 0xff, 0x39);
	regmap_update_bits(afe_priv->topckgen, CKSYS_AUD_TOP_CFG, 0xffff, 0x4);

	afe_priv->mtkaif_calibration_num_phase = 42;
	afe_priv->mtkaif_chosen_phase[0] = -1;
	afe_priv->mtkaif_chosen_phase[1] = -1;

	for (phase = 0; phase <= 42 && ok; phase++) {
		mt6358_set_mtkaif_calibration_phase(codec, phase, phase);
		regmap_update_bits(afe_priv->topckgen, CKSYS_AUD_TOP_CFG, 0x1, 0x1);
		done_1 = need_0 ? 0 : -1;
		done_2 = need_1 ? 0 : -1;
		cycle_1 = -1;
		cycle_2 = -1;
		counter = 0;
		while (done_1 == 0 || done_2 == 0) {
			regmap_read(afe_priv->topckgen, CKSYS_AUD_TOP_MON, &monitor);
			if (done_1 == 0)
				done_1 = (monitor >> 28) & 0x1;
			if (done_2 == 0)
				done_2 = (monitor >> 29) & 0x1;
			if (done_1 == 1)
				cycle_1 = monitor & 0xf;
			if (done_2 == 1)
				cycle_2 = (monitor >> 4) & 0xf;
			if (++counter > 10000) {
				dev_err(afe->dev, "mtkaif cal: phase %d never done, monitor %#x\n",
					phase, monitor);
				ok = false;
				break;
			}
		}
		dev_info(afe->dev, "mtkaif cal: phase %d cycle %d/%d monitor %#x\n",
			 phase, cycle_1, cycle_2, monitor);
		if (phase == 0) {
			prev_1 = cycle_1;
			prev_2 = cycle_2;
		}
		if (need_0 && cycle_1 != prev_1 && afe_priv->mtkaif_chosen_phase[0] < 0) {
			afe_priv->mtkaif_chosen_phase[0] = phase - 1;
			afe_priv->mtkaif_phase_cycle[0] = prev_1;
		}
		if (need_1 && cycle_2 != prev_2 && afe_priv->mtkaif_chosen_phase[1] < 0) {
			afe_priv->mtkaif_chosen_phase[1] = phase - 1;
			afe_priv->mtkaif_phase_cycle[1] = prev_2;
		}
		regmap_update_bits(afe_priv->topckgen, CKSYS_AUD_TOP_CFG, 0x1, 0x0);
	}

	mt6358_set_mtkaif_calibration_phase(codec,
		max(afe_priv->mtkaif_chosen_phase[0], 0),
		max(afe_priv->mtkaif_chosen_phase[1], 0));
	regmap_update_bits(afe->regmap, AFE_AUD_PAD_TOP, 0xff, 0x38);
	mt6358_mtkaif_calibration_disable(codec);
	mt6789_afe_gpio_request(afe, false, MT6789_DAI_ADDA, 1);
	mt6789_afe_gpio_request(afe, false, MT6789_DAI_ADDA, 0);
	if (!need_0)
		regmap_update_bits(afe->regmap, AFE_ADDA_MTKAIF_SYNCWORD_CFG,
				   RG_ADDA_MTKAIF_RX_SYNC_WORD1_DISABLE_MASK_SFT,
				   BIT(RG_ADDA_MTKAIF_RX_SYNC_WORD1_DISABLE_SFT));
	if (!need_1)
		regmap_update_bits(afe->regmap, AFE_ADDA_MTKAIF_SYNCWORD_CFG,
				   RG_ADDA_MTKAIF_RX_SYNC_WORD2_DISABLE_MASK_SFT,
				   BIT(RG_ADDA_MTKAIF_RX_SYNC_WORD2_DISABLE_SFT));
	pm_runtime_put(afe->dev);

	dev_info(afe->dev, "mtkaif cal: chosen phase %d/%d cycle %d/%d need %d/%d ok %d\n",
		 afe_priv->mtkaif_chosen_phase[0], afe_priv->mtkaif_chosen_phase[1],
		 afe_priv->mtkaif_phase_cycle[0], afe_priv->mtkaif_phase_cycle[1],
		 need_0, need_1, ok);
}

static int q25_adda_init(struct snd_soc_pcm_runtime *rtd)
{
	struct snd_soc_component *afe_c = snd_soc_rtdcom_lookup(rtd, AFE_PCM_NAME);
	struct snd_soc_component *codec = snd_soc_rtd_to_codec(rtd, 0)->component;
	struct mtk_base_afe *afe = snd_soc_component_get_drvdata(afe_c);
	struct mt6789_afe_private *afe_priv = afe->platform_priv;

	switch (mtkaif) {
	case 2:
		mt6358_set_mtkaif_protocol(codec, MT6358_MTKAIF_PROTOCOL_2);
		afe_priv->mtkaif_protocol = MTKAIF_PROTOCOL_2;
		break;
	case 3:
		mt6358_set_mtkaif_protocol(codec, MT6358_MTKAIF_PROTOCOL_2_CLK_P2);
		afe_priv->mtkaif_protocol = MTKAIF_PROTOCOL_2_CLK_P2;
		q25_mtkaif_calibration(afe, codec);
		break;
	default:
		mt6358_set_mtkaif_protocol(codec, MT6358_MTKAIF_PROTOCOL_1);
		afe_priv->mtkaif_protocol = MTKAIF_PROTOCOL_1;
		break;
	}
	dev_info(afe->dev, "q25: MTKAIF protocol param %d\n", mtkaif);

	return snd_soc_dapm_sync(snd_soc_card_to_dapm(rtd->card));
}

SND_SOC_DAILINK_DEFS(playback1,
	DAILINK_COMP_ARRAY(COMP_CPU("DL1")),
	DAILINK_COMP_ARRAY(COMP_DUMMY()),
	DAILINK_COMP_ARRAY(COMP_EMPTY()));
SND_SOC_DAILINK_DEFS(capture1,
	DAILINK_COMP_ARRAY(COMP_CPU("UL1")),
	DAILINK_COMP_ARRAY(COMP_DUMMY()),
	DAILINK_COMP_ARRAY(COMP_EMPTY()));
SND_SOC_DAILINK_DEFS(playback2,
	DAILINK_COMP_ARRAY(COMP_CPU("DL2")),
	DAILINK_COMP_ARRAY(COMP_DUMMY()),
	DAILINK_COMP_ARRAY(COMP_EMPTY()));
SND_SOC_DAILINK_DEFS(capture2,
	DAILINK_COMP_ARRAY(COMP_CPU("UL2")),
	DAILINK_COMP_ARRAY(COMP_DUMMY()),
	DAILINK_COMP_ARRAY(COMP_EMPTY()));
SND_SOC_DAILINK_DEFS(hostless_speech,
	DAILINK_COMP_ARRAY(COMP_CPU("Hostless Speech DAI")),
	DAILINK_COMP_ARRAY(COMP_DUMMY()),
	DAILINK_COMP_ARRAY(COMP_EMPTY()));
SND_SOC_DAILINK_DEFS(hostless_sph_echo_ref,
	DAILINK_COMP_ARRAY(COMP_CPU("Hostless_Sph_Echo_Ref_DAI")),
	DAILINK_COMP_ARRAY(COMP_DUMMY()),
	DAILINK_COMP_ARRAY(COMP_EMPTY()));
SND_SOC_DAILINK_DEFS(pcm2,
	DAILINK_COMP_ARRAY(COMP_CPU("PCM 2")),
	DAILINK_COMP_ARRAY(COMP_DUMMY()),
	DAILINK_COMP_ARRAY(COMP_EMPTY()));
SND_SOC_DAILINK_DEFS(adda,
	DAILINK_COMP_ARRAY(COMP_CPU("ADDA")),
	DAILINK_COMP_ARRAY(COMP_CODEC("mt6358-sound", "mt6358-snd-codec-aif1")),
	DAILINK_COMP_ARRAY(COMP_EMPTY()));

static struct snd_soc_dai_link q25_links[] = {
	{
		.name = "Playback_1",
		.stream_name = "Playback_1",
		.trigger = { SND_SOC_DPCM_TRIGGER_PRE, SND_SOC_DPCM_TRIGGER_PRE },
		.dynamic = 1,
		.playback_only = 1,
		SND_SOC_DAILINK_REG(playback1),
	},
	{
		.name = "Capture_1",
		.stream_name = "Capture_1",
		.trigger = { SND_SOC_DPCM_TRIGGER_PRE, SND_SOC_DPCM_TRIGGER_PRE },
		.dynamic = 1,
		.capture_only = 1,
		SND_SOC_DAILINK_REG(capture1),
	},
	{
		.name = "Primary Codec",
		.no_pcm = 1,
		.ignore_suspend = 1,
		.init = q25_adda_init,
		SND_SOC_DAILINK_REG(adda),
	},
	/* Voice-call plumbing (stock link names). pcm 3/4 = DL2/UL2 for PCM2 tests. */
	{
		.name = "Playback_2",
		.stream_name = "Playback_2",
		.trigger = { SND_SOC_DPCM_TRIGGER_PRE, SND_SOC_DPCM_TRIGGER_PRE },
		.dynamic = 1,
		.playback_only = 1,
		SND_SOC_DAILINK_REG(playback2),
	},
	{
		.name = "Capture_2",
		.stream_name = "Capture_2",
		.trigger = { SND_SOC_DPCM_TRIGGER_PRE, SND_SOC_DPCM_TRIGGER_PRE },
		.dynamic = 1,
		.capture_only = 1,
		SND_SOC_DAILINK_REG(capture2),
	},
	{
		.name = "Hostless_Speech",
		.stream_name = "Hostless_Speech",
		.trigger = { SND_SOC_DPCM_TRIGGER_PRE, SND_SOC_DPCM_TRIGGER_PRE },
		.dynamic = 1,
		.ignore_suspend = 1,
		SND_SOC_DAILINK_REG(hostless_speech),
	},
	{
		.name = "Hostless_Sph_Echo_Ref",
		.stream_name = "Hostless_Sph_Echo_Ref",
		.trigger = { SND_SOC_DPCM_TRIGGER_PRE, SND_SOC_DPCM_TRIGGER_PRE },
		.dynamic = 1,
		.ignore_suspend = 1,
		SND_SOC_DAILINK_REG(hostless_sph_echo_ref),
	},
	{
		.name = "PCM 2",
		.no_pcm = 1,
		.ignore_suspend = 1,
		SND_SOC_DAILINK_REG(pcm2),
	},
};

static const struct snd_soc_dapm_widget q25_widgets[] = {
	SND_SOC_DAPM_SPK("Speakers", NULL),
	SND_SOC_DAPM_SPK("Earpiece", NULL),
	SND_SOC_DAPM_HP("Headphones", NULL),
	SND_SOC_DAPM_MIC("Main Mic", NULL),
	SND_SOC_DAPM_MIC("Headset Mic", NULL),
	SND_SOC_DAPM_MIC("Second Mic", NULL),
};

static const struct snd_soc_dapm_route q25_routes[] = {
	{ "Earpiece", NULL, "Receiver" },
	{ "Headphones", NULL, "Headphone L" },
	{ "Headphones", NULL, "Headphone R" },
	{ "AIN0", NULL, "Main Mic" },
	{ "AIN1", NULL, "Headset Mic" },
	{ "AIN2", NULL, "Second Mic" },
};

static const struct snd_soc_dapm_route q25_amp_routes[] = {
	{ "Speaker IN", NULL, "LINEOUT L" },
	{ "Speakers", NULL, "Speaker OUT" },
};

static const struct snd_soc_dapm_route q25_noamp_routes[] = {
	{ "Speakers", NULL, "LINEOUT L" },
};

static const struct snd_kcontrol_new q25_controls[] = {
	SOC_DAPM_PIN_SWITCH("Speakers"),
	SOC_DAPM_PIN_SWITCH("Earpiece"),
	SOC_DAPM_PIN_SWITCH("Headphones"),
	SOC_DAPM_PIN_SWITCH("Main Mic"),
	SOC_DAPM_PIN_SWITCH("Headset Mic"),
	SOC_DAPM_PIN_SWITCH("Second Mic"),
};

static struct snd_soc_aux_dev q25_amp_aux;

static struct snd_soc_card q25_card = {
	.name = "q25-mt6366",
	.driver_name = "q25-mt6366",
	.owner = THIS_MODULE,
	.dai_link = q25_links,
	.num_links = ARRAY_SIZE(q25_links),
	.dapm_widgets = q25_widgets,
	.num_dapm_widgets = ARRAY_SIZE(q25_widgets),
	.dapm_routes = q25_routes,
	.num_dapm_routes = ARRAY_SIZE(q25_routes),
	.controls = q25_controls,
	.num_controls = ARRAY_SIZE(q25_controls),
};

static int q25_late_routes(struct snd_soc_card *card)
{
	struct snd_soc_dapm_context *dapm = snd_soc_card_to_dapm(card);

	if (card->num_aux_devs)
		return snd_soc_dapm_add_routes(dapm, q25_amp_routes,
					       ARRAY_SIZE(q25_amp_routes));
	return snd_soc_dapm_add_routes(dapm, q25_noamp_routes,
				       ARRAY_SIZE(q25_noamp_routes));
}

static int q25_card_probe(struct platform_device *pdev)
{
	struct snd_soc_card *card = &q25_card;
	struct device_node *platform, *amp;
	struct snd_soc_dai_link *link;
	int i, ret;

	platform = of_parse_phandle(pdev->dev.of_node, "mediatek,platform", 0);
	if (!platform)
		return dev_err_probe(&pdev->dev, -EINVAL, "no mediatek,platform\n");

	for_each_card_prelinks(card, i, link) {
		if (!link->platforms->name)
			link->platforms->of_node = platform;
	}

	amp = use_amp ? of_parse_phandle(pdev->dev.of_node, "mediatek,speaker-amp", 0) : NULL;
	if (amp) {
		q25_amp_aux.dlc.of_node = amp;
		card->aux_dev = &q25_amp_aux;
		card->num_aux_devs = 1;
	}
	card->late_probe = q25_late_routes;
	card->dev = &pdev->dev;
	of_property_read_string(pdev->dev.of_node, "model", &card->long_name);

	ret = devm_snd_soc_register_card(&pdev->dev, card);
	if (ret) {
		of_node_put(amp);
		of_node_put(platform);
		return dev_err_probe(&pdev->dev, ret, "register card\n");
	}
	return 0;
}

static const struct of_device_id q25_card_of_match[] = {
	{ .compatible = "zinwa,q25-mt6366-sound" },
	{ }
};
MODULE_DEVICE_TABLE(of, q25_card_of_match);

static struct platform_driver q25_card_driver = {
	.driver = {
		.name = "q25-mt6366-sound",
		.of_match_table = q25_card_of_match,
		.pm = &snd_soc_pm_ops,
	},
	.probe = q25_card_probe,
};
module_platform_driver(q25_card_driver);

MODULE_DESCRIPTION("Zinwa Q25 MT6789/MT6366 ASoC machine driver");
MODULE_LICENSE("GPL");
