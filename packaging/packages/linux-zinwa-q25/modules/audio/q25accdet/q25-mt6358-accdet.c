// SPDX-License-Identifier: GPL-2.0
/*
 * Copyright (C) 2022 MediaTek Inc.
 * Author: Kevin Huang <shang-ming.huang@mediatek.com>
 */

#include <linux/of_gpio.h>
#include <linux/of.h>
#include <linux/of_irq.h>
#include <linux/of_device.h>
#include <linux/of_platform.h>
#include <linux/iio/driver.h>
#include <linux/iio/iio.h>
#include <linux/iio/machine.h>
#include <linux/of_address.h>
#include <linux/input.h>
#include <linux/kthread.h>
#include <linux/io.h>
#include <linux/sched/clock.h>
#include <linux/workqueue.h>
#include <linux/timer.h>
#include <linux/delay.h>
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/iio/consumer.h>
#include <linux/nvmem-consumer.h>
#include <linux/init.h>
#include <linux/irqdomain.h>
#include <linux/irq.h>
#include <linux/regmap.h>
#include <sound/soc.h>
#include <sound/jack.h>
#include <linux/mfd/mt6397/core.h>
#include <linux/mfd/mt6358/core.h>
#include "mt6358-accdet.h"
#include "q25-accdet.h"
#include "stock-mt6358.h"

/* grobal variable definitions */
#define REGISTER_VAL(x)	(x - 1)
#define HAS_CAP(_c, _x)	(((_c) & (_x)) == (_x))
#define ACCDET_PMIC_EINT_IRQ		BIT(0)
#define ACCDET_AP_GPIO_EINT		BIT(1)

#define ACCDET_PMIC_EINT0		BIT(2)
#define ACCDET_PMIC_EINT1		BIT(3)
#define ACCDET_PMIC_BI_EINT		BIT(4)

#define ACCDET_PMIC_GPIO_TRIG_EINT	BIT(5)
#define ACCDET_PMIC_INVERTER_TRIG_EINT	BIT(6)
#define ACCDET_PMIC_RSV_EINT		BIT(7)

#define ACCDET_THREE_KEY		BIT(8)
#define ACCDET_FOUR_KEY			BIT(9)
#define ACCDET_TRI_KEY_CDD		BIT(10)
#define ACCDET_RSV_KEY			BIT(11)

#define ACCDET_ANALOG_FASTDISCHARGE	BIT(12)
#define ACCDET_DIGITAL_FASTDISCHARGE	BIT(13)
#define ACCDET_AD_FASTDISCHRAGE		BIT(14)

#define ACCDET_MOISTURE_DETECTED	BIT(15)

#define RET_LT_5K			(-1)
#define RET_GT_5K			(0)

/* Used to let accdet know if the pin has been fully plugged-in */
#define EINT_PLUG_OUT			(0)
#define EINT_PLUG_IN			(1)
#define EINT_MOISTURE_DETECTED	(2)

struct mt63xx_accdet_data {
	u32 base;
	struct snd_soc_card card;
	struct snd_soc_jack jack;
	bool jack_ready;
	struct platform_device *pdev;
	struct device *dev;
	struct accdet_priv *data;
	atomic_t init_once;
	struct regmap *regmap;
	struct iio_channel *accdet_auxadc;
	struct nvmem_device *accdet_efuse;
	int accdet_irq;
	int accdet_eint0;
	int accdet_eint1;
	struct wakeup_source *wake_lock;
	struct wakeup_source *timer_lock;
	struct mutex res_lock;
	dev_t accdet_devno;
	struct class *accdet_class;
	int button_status;
	bool eint_sync_flag;
	/* accdet FSM State & lock*/
	u32 cur_eint_state;
	u32 eint0_state;
	u32 eint1_state;
	u32 accdet_status;
	u32 cable_type;
	u32 cur_key;
	u32 cali_voltage;
	int auxadc_offset;
	u32 eint_id;
	bool thing_in_flag;
	/* when caps include ACCDET_AP_GPIO_EINT */
	struct pinctrl *pinctrl;
	struct pinctrl_state *pins_eint;
	u32 gpiopin;
	u32 gpio_hp_deb;
	u32 gpioirq;
	u32 accdet_eint_type;
	/* when MICBIAS_DISABLE_TIMER timeout, queue work: dis_micbias_work */
	struct work_struct delay_init_work;
	struct workqueue_struct *delay_init_workqueue;
	struct work_struct dis_micbias_work;
	struct workqueue_struct *dis_micbias_workqueue;
	struct work_struct accdet_work;
	struct workqueue_struct *accdet_workqueue;
	/* when eint issued, queue work: eint_work */
	struct work_struct eint_work;
	struct workqueue_struct *eint_workqueue;
	u32 water_r;
	u32 moisture_ext_r;
	u32 moisture_int_r;
	u32 moisture_vm;
	u32 moisture_vdd_offset;
	u32 moisture_offset;
	u32 moisture_eint_offset;
};
static struct mt63xx_accdet_data *accdet;

static struct head_dts_data accdet_dts;
struct pwm_deb_settings *cust_pwm_deb;

struct accdet_priv {
	u32 caps;
	struct snd_card *snd_card;
};

static struct accdet_priv mt6357_accdet[] = {
	{
		.caps = 0,
	},
};

const struct of_device_id accdet_of_match[] = {
	{
		.compatible = "mediatek,mt6357-accdet",
		.data = &mt6357_accdet,
	}, {
		.compatible = "mediatek,mt6358-accdet",
		.data = &mt6357_accdet,
	}, {
		.compatible = "mediatek,mt8163-accdet",
	}, {
		.compatible = "mediatek,mt8173-accdet",
	}, {
		/* sentinel */
	},
};
static struct platform_driver accdet_driver;
static int accdet_pmic;

static bool standalone;
module_param(standalone, bool, 0444);
MODULE_PARM_DESC(standalone, "no DT node needed: built-in Q25 resources (PMIC IRQ 133/134, AUXADC acc_det, stock q20_v12 parameters)");
static int q25_cable;
module_param_named(cable, q25_cable, int, 0444);
MODULE_PARM_DESC(cable, "last reported state: 0 none, 1 headset (4-pole), 2 headphone (3-pole), 4 line-out");
static int q25_keys;
module_param_named(key_presses, q25_keys, int, 0444);
MODULE_PARM_DESC(key_presses, "headset button presses seen");
static atomic_t accdet_first;
#define ACCDET_INIT_WAIT_TIMER (10 * HZ)
static struct timer_list accdet_init_timer;
static void delay_init_timerhandler(struct timer_list *t);
/* micbias_timer: disable micbias if no accdet irq after eint,
 * timeout: 6 seconds
 * timerHandler: dis_micbias_timerhandler()
 */
#define MICBIAS_DISABLE_TIMER (6 * HZ)
static struct timer_list micbias_timer;
static void dis_micbias_timerhandler(struct timer_list *t);
static bool dis_micbias_done;

static u32 button_press_debounce = 0x400;

/* local function declaration */
static void accdet_init_once(void);
static inline void accdet_init(void);
static void accdet_init_debounce(void);
static void config_eint_init_by_mode(void);
static u32 get_triggered_eint(void);
static void send_status_event(u32 cable_type, u32 status);
static inline void accdet_eint_high_level_support(void);
/* global function declaration */
inline u32 accdet_read(u32 addr)
{
	u32 val = 0;

	regmap_read(accdet->regmap, addr, &val);
	return val;
}

inline u32 accdet_read_bits(u32 addr, u32 shift, u32 mask)
{
	u32 val = 0;

	val = accdet_read(addr);
	return ((val>>shift) & mask);
}

inline void accdet_write(u32 addr, u32 wdata)
{
	regmap_write(accdet->regmap, addr, wdata);
}

inline void accdet_update_bits(u32 addr, u32 shift, u32 mask, u32 data)
{
	regmap_update_bits(accdet->regmap, addr, mask << shift,
		data << shift);
}

inline void accdet_update_bit(u32 addr, u32 shift)
{
	unsigned int mask = shift;

	regmap_update_bits(accdet->regmap, addr, BIT(mask),
		BIT(shift));
}

inline void accdet_clear_bits(u32 addr, unsigned int shift,
			unsigned int mask, unsigned int data)
{
	regmap_update_bits(accdet->regmap, addr, mask << shift, 0);
}

inline void accdet_clear_bit(u32 addr, u32 shift)
{
	unsigned int mask = shift;

	regmap_update_bits(accdet->regmap, addr, BIT(mask), 0);
}

static u64 accdet_get_current_time(void)
{
	return sched_clock();
}

static bool accdet_timeout_ns(u64 start_time_ns, u64 timeout_time_ns)
{
	u64 cur_time = 0;
	u64 elapse_time = 0;

	/* get current tick, ns */
	cur_time = accdet_get_current_time();
	if (cur_time < start_time_ns) {
		start_time_ns = cur_time;
		/* 400us */
		timeout_time_ns = 400 * 1000;
	}
	elapse_time = cur_time - start_time_ns;

	/* check if timeout */
	if (timeout_time_ns <= elapse_time)
		return false;

	return true;
}

static u32 accdet_get_auxadc(void)
{
	int vol = 0, ret = 0;

	if (!IS_ERR(accdet->accdet_auxadc)) {
		ret = iio_read_channel_processed(accdet->accdet_auxadc, &vol);
		if (ret < 0) {
			pr_notice("Error: %s read fail (%d)\n", __func__, ret);
			return ret;
		}
	}

	pr_info("%s() vol_val:%d offset:%d real vol:%d mv!\n", __func__, vol,
		accdet->auxadc_offset,
		(vol < accdet->auxadc_offset) ? 0 : (vol-accdet->auxadc_offset));

	if (vol < accdet->auxadc_offset)
		vol = 0;
	else
		vol -= accdet->auxadc_offset;

	return vol;
}

static void accdet_get_efuse(void)
{
	unsigned short efuseval = 0;
	int ret = 0;
	int tmp_div;
	int efuse_idx = 0;
	unsigned int moisture_eint0;
	unsigned int moisture_eint1;
	int efuse[2][5] = {{110, 113, 114, 112, 113},
			   {115, 118, 119, 117, 118} };

	if (accdet_pmic == 0x0)
		efuse_idx = 0;
	else if (accdet_pmic == 0x66)
		efuse_idx = 1;
	/* accdet offset efuse:
	 * this efuse must divided by 2
	 */
	ret = nvmem_device_read(accdet->accdet_efuse, efuse[efuse_idx][0]*2, 2, &efuseval);
	accdet->auxadc_offset = efuseval & 0xFF;
	if (accdet->auxadc_offset > 128)
		accdet->auxadc_offset -= 256;
	accdet->auxadc_offset = (accdet->auxadc_offset >> 1);
/* all of moisture_vdd/moisture_offset0/eint is  2'complement,
 * we need to transfer it
 */
	/* moisture vdd efuse offset */
	ret = nvmem_device_read(accdet->accdet_efuse, efuse[efuse_idx][1]*2, 2, &efuseval);
	accdet->moisture_vdd_offset =
		(int)((efuseval >> 8) & ACCDET_CALI_MASK0);
	if (accdet->moisture_vdd_offset > 128)
		accdet->moisture_vdd_offset -= 256;
	pr_info("%s moisture_vdd efuse=0x%x, moisture_vdd_offset=%d mv\n",
		__func__, efuseval, accdet->moisture_vdd_offset);

	/* moisture offset */
	ret = nvmem_device_read(accdet->accdet_efuse, efuse[efuse_idx][2]*2, 2, &efuseval);
	accdet->moisture_offset = (int)(efuseval & ACCDET_CALI_MASK0);
	if (accdet->moisture_offset > 128)
		accdet->moisture_offset -= 256;
	pr_info("%s moisture_efuse efuse=0x%x,moisture_offset=%d mv\n",
		__func__, efuseval, accdet->moisture_offset);

	if (accdet_dts.moisture_use_ext_res == 0x0) {
		/* moisture eint efuse offset */
		ret = nvmem_device_read(accdet->accdet_efuse,
				efuse[efuse_idx][3]*2, 2, &efuseval);
		moisture_eint0 =
			(int)((efuseval >> 8) & ACCDET_CALI_MASK0);
		ret = nvmem_device_read(accdet->accdet_efuse,
				efuse[efuse_idx][4]*2, 2, &efuseval);
		moisture_eint1 = (int)(efuseval & ACCDET_CALI_MASK0);

		accdet->moisture_eint_offset =
			(moisture_eint1 << 8) | moisture_eint0;
		if (accdet->moisture_eint_offset > 32768)
			accdet->moisture_eint_offset -= 65536;
		pr_info("%s moisture_eint_offset=%d ohm\n", __func__,
			accdet->moisture_eint_offset);

		accdet->moisture_vm = (2800 + accdet->moisture_vdd_offset);
		accdet->moisture_vm *=
			(accdet->water_r + accdet->moisture_int_r);
		tmp_div = accdet->water_r + accdet->moisture_int_r +
			8 * accdet->moisture_eint_offset + 450000;
		accdet->moisture_vm = accdet->moisture_vm / tmp_div;
		accdet->moisture_vm =
			accdet->moisture_vm + accdet->moisture_offset / 2;
		pr_info("%s internal moisture_vm=%d mv\n", __func__,
			accdet->moisture_vm);
	} else if (accdet_dts.moisture_use_ext_res == 0x1) {
		accdet->moisture_vm = (2800 + accdet->moisture_vdd_offset);
		accdet->moisture_vm = accdet->moisture_vm * accdet->water_r;
		accdet->moisture_vm /=
			(accdet->water_r + accdet->moisture_ext_r);
		accdet->moisture_vm +=
			(accdet->moisture_offset >> 1);
		pr_info("%s external moisture_vm=%d mv\n", __func__,
			accdet->moisture_vm);
	}
	pr_info("%s efuse=0x%x,auxadc_val=%dmv\n", __func__, efuseval,
		accdet->auxadc_offset);
}

static void accdet_get_efuse_4key(void)
{
	unsigned short tmp_val = 0;
	unsigned short tmp_8bit = 0;
	int ret = 0;
	int efuse_idx = 0;
	int efuse[2][2] = {{111, 112},
			   {116, 117} };

	if (accdet_pmic == 0x0)
		efuse_idx = 0;
	else if (accdet_pmic == 0x66)
		efuse_idx = 1;

	/* 4-key efuse:
	 * bit[9:2] efuse value is loaded, so every read out value need to be
	 * left shift 2 bit,and then compare with voltage get from AUXADC.
	 * AD efuse: key-A Voltage:0--AD;
	 * DB efuse: key-D Voltage: AD--DB;
	 * BC efuse: key-B Voltage:DB--BC;
	 * key-C Voltage: BC--600;
	 */
	ret = nvmem_device_read(accdet->accdet_efuse, efuse[efuse_idx][0]*2, 2, &tmp_val);
	tmp_8bit = tmp_val & ACCDET_CALI_MASK0;
	accdet_dts.four_key.mid = tmp_8bit << 2;

	tmp_8bit = (tmp_val >> 8) & ACCDET_CALI_MASK0;
	accdet_dts.four_key.voice = tmp_8bit << 2;

	ret = nvmem_device_read(accdet->accdet_efuse, efuse[efuse_idx][1]*2, 2, &tmp_val);
	tmp_8bit = tmp_val & ACCDET_CALI_MASK0;
	accdet_dts.four_key.up = tmp_8bit << 2;

	accdet_dts.four_key.down = 600;
	pr_info("accdet key thresh: mid=%dmv,voice=%dmv,up=%dmv,down=%dmv\n",
		accdet_dts.four_key.mid, accdet_dts.four_key.voice,
		accdet_dts.four_key.up, accdet_dts.four_key.down);
}

static u32 key_check(u32 v)
{
	if (HAS_CAP(accdet->data->caps, ACCDET_FOUR_KEY)) {
		if ((v < accdet_dts.four_key.down) &&
			(v >= accdet_dts.four_key.up))
			return DW_KEY;
		if ((v < accdet_dts.four_key.up) &&
			(v >= accdet_dts.four_key.voice))
			return UP_KEY;
		if ((v < accdet_dts.four_key.voice) &&
			(v >= accdet_dts.four_key.mid))
			return AS_KEY;
		if (v < accdet_dts.four_key.mid)
			return MD_KEY;
	} else {
		if ((v < accdet_dts.three_key.down) &&
			(v >= accdet_dts.three_key.up))
			return DW_KEY;
		if ((v < accdet_dts.three_key.up) &&
			(v >= accdet_dts.three_key.mid))
			return UP_KEY;
		if (v < accdet_dts.three_key.mid)
			return MD_KEY;
	}
	return NO_KEY;
}

static void send_key_event(u32 keycode, u32 flag)
{
	int report = 0;

	if (flag)
		q25_keys++;

	switch (keycode) {
	case DW_KEY:
		if (flag != 0)
			report = SND_JACK_BTN_1;
		snd_soc_jack_report(&accdet->jack, report,
				SND_JACK_BTN_1);
		break;
	case UP_KEY:
		if (flag != 0)
			report = SND_JACK_BTN_2;
		snd_soc_jack_report(&accdet->jack, report,
				SND_JACK_BTN_2);
		break;
	case MD_KEY:
		if (flag != 0)
			report = SND_JACK_BTN_0;
		snd_soc_jack_report(&accdet->jack, report,
				SND_JACK_BTN_0);
		break;
	case AS_KEY:
		if (flag != 0)
			report = SND_JACK_BTN_3;
		snd_soc_jack_report(&accdet->jack, report,
				SND_JACK_BTN_3);
		break;
	}
}

static void send_status_event(u32 cable_type, u32 status)
{
	int report = 0;

	q25_cable = status ? cable_type : 0;

	switch (cable_type) {
	case HEADSET_NO_MIC:
		if (status)
			report = SND_JACK_HEADPHONE;
		else
			report = 0;
		snd_soc_jack_report(&accdet->jack, report,
				SND_JACK_HEADPHONE);
		/* when plug 4-pole out, if both AB=3 AB=0 happen,3-pole plug
		 * in will be incorrectly reported, then 3-pole plug-out is
		 * reported,if no mantory 4-pole plug-out, icon would be
		 * visible.
		 */
		if (status == 0) {
			report = 0;
			snd_soc_jack_report(&accdet->jack, report,
					SND_JACK_MICROPHONE);
		}
		pr_info("accdet HEADPHONE(3-pole) %s\n",
			status ? "PlugIn" : "PlugOut");
		break;
	case HEADSET_MIC:
		/* when plug 4-pole out, 3-pole plug out should also be
		 * reported for slow plug-in case
		 */
		if (status == 0) {
			report = 0;
			snd_soc_jack_report(&accdet->jack, report,
					SND_JACK_HEADPHONE);
		}
		if (status)
			report = SND_JACK_HEADSET;
		else
			report = 0;

		snd_soc_jack_report(&accdet->jack, report,
				SND_JACK_HEADSET);
		pr_info("accdet MICROPHONE(4-pole) %s\n",
			status ? "PlugIn" : "PlugOut");
		/* when press key for a long time then plug in
		 * even recoginized as 4-pole
		 * disable micbias timer still timeout after 6s
		 * it check AB=00(because keep to press key) then disable
		 * micbias, it will cause key no response
		 */
		timer_delete_sync(&micbias_timer);
		break;
	case LINE_OUT_DEVICE:
		if (status)
			report = SND_JACK_LINEOUT;
		else
			report = 0;

		snd_soc_jack_report(&accdet->jack, report,
				SND_JACK_LINEOUT);
		pr_info("accdet LineOut %s\n",
			status ? "PlugIn" : "PlugOut");
		break;
	default:
		pr_info("%s Invalid cableType\n", __func__);
	}
}

static void multi_key_detection(u32 cur_AB)
{
	if (cur_AB == ACCDET_STATE_AB_00)
		accdet->cur_key = key_check(accdet->cali_voltage);

	/* delay to fix side effect key when plug-out, when plug-out,seldom
	 * issued AB=0 and Eint, delay to wait eint been flaged in register.
	 * or eint handler issued. accdet->cur_eint_state == PLUG_OUT
	 */
	usleep_range(10000, 12000);

	if (HAS_CAP(accdet->data->caps, ACCDET_AP_GPIO_EINT)) {
		if (accdet->cur_eint_state == EINT_PLUG_IN)
			send_key_event(accdet->cur_key, !cur_AB);
		else
			accdet->cur_key = NO_KEY;
	} else {
		bool irq_bit = false;

		irq_bit = !(accdet_read(ACCDET_IRQ_ADDR) &
					ACCDET_EINT_IRQ_B2_B3);
		/* send key when:
		 * no eint is flaged in reg, and now eint PLUG_IN
		 */
		if (irq_bit && (accdet->cur_eint_state == EINT_PLUG_IN))
			send_key_event(accdet->cur_key, !cur_AB);
		else
			accdet->cur_key = NO_KEY;
	}

	if (cur_AB)
		accdet->cur_key = NO_KEY;
}

static inline void clear_accdet_int(void)
{
	/* it is safe by using polling to adjust when to clear IRQ_CLR_BIT */
	accdet_update_bit(ACCDET_IRQ_ADDR, ACCDET_IRQ_CLR_SFT);
}

static inline void clear_accdet_int_check(void)
{
	u64 cur_time = accdet_get_current_time();

	while ((accdet_read(ACCDET_IRQ_ADDR) & ACCDET_IRQ_MASK_SFT) &&
		(accdet_timeout_ns(cur_time, ACCDET_TIME_OUT)))
		;
	/* clear accdet int, modify  for fix interrupt trigger twice error */
	accdet_clear_bit(ACCDET_IRQ_ADDR, ACCDET_IRQ_CLR_SFT);
	accdet_update_bit(RG_INT_STATUS_ACCDET_ADDR,
		RG_INT_STATUS_ACCDET_SFT);
}

static inline void clear_accdet_eint(u32 eintid)
{
	if ((eintid & PMIC_EINT0) == PMIC_EINT0) {
		accdet_update_bit(ACCDET_IRQ_ADDR,
			ACCDET_EINT0_IRQ_CLR_SFT);
	}
	if ((eintid & PMIC_EINT1) == PMIC_EINT1) {
		accdet_update_bit(ACCDET_IRQ_ADDR,
			ACCDET_EINT1_IRQ_CLR_SFT);
	}

}

static inline void clear_accdet_eint_check(u32 eintid)
{
	u64 cur_time = accdet_get_current_time();

	if ((eintid & PMIC_EINT0) == PMIC_EINT0) {
		while ((accdet_read(ACCDET_IRQ_ADDR) & ACCDET_EINT0_IRQ_MASK_SFT)
			&& (accdet_timeout_ns(cur_time, ACCDET_TIME_OUT)))
			;
		accdet_clear_bit(ACCDET_IRQ_ADDR,
				ACCDET_EINT0_IRQ_CLR_SFT);
		accdet_update_bit(RG_INT_STATUS_ACCDET_ADDR,
				RG_INT_STATUS_ACCDET_EINT0_SFT);
	}
	if ((eintid & PMIC_EINT1) == PMIC_EINT1) {
		while ((accdet_read(ACCDET_IRQ_ADDR) & ACCDET_EINT1_IRQ_MASK_SFT)
			&& (accdet_timeout_ns(cur_time, ACCDET_TIME_OUT)))
			;
		accdet_clear_bit(ACCDET_IRQ_ADDR,
				ACCDET_EINT1_IRQ_CLR_SFT);
		accdet_update_bit(RG_INT_STATUS_ACCDET_ADDR,
				RG_INT_STATUS_ACCDET_EINT1_SFT);
	}
}

static u32 get_triggered_eint(void)
{
	u32 eint_ID = NO_PMIC_EINT;
	u32 irq_status = accdet_read(ACCDET_IRQ_ADDR);

	if (HAS_CAP(accdet->data->caps,
			ACCDET_PMIC_EINT0)) {
		if ((irq_status & ACCDET_EINT0_IRQ_MASK_SFT) ==
				ACCDET_EINT0_IRQ_MASK_SFT)
			eint_ID = PMIC_EINT0;
	} else if (HAS_CAP(accdet->data->caps,
			ACCDET_PMIC_EINT1)) {
		if ((irq_status & ACCDET_EINT1_IRQ_MASK_SFT) ==
				ACCDET_EINT1_IRQ_MASK_SFT)
			eint_ID = PMIC_EINT1;
	} else if (HAS_CAP(accdet->data->caps,
			ACCDET_PMIC_BI_EINT)) {
		if ((irq_status & ACCDET_EINT0_IRQ_MASK_SFT) ==
				ACCDET_EINT0_IRQ_MASK_SFT)
			eint_ID |= PMIC_EINT0;
		if ((irq_status & ACCDET_EINT1_IRQ_MASK_SFT) ==
				ACCDET_EINT1_IRQ_MASK_SFT)
			eint_ID |= PMIC_EINT1;
	}
	return eint_ID;
}

static void eint_polarity_reverse(u32 eint_id)
{
	if (eint_id == PMIC_EINT0) {
		if (accdet->cur_eint_state == EINT_PLUG_OUT) {
			if (accdet->accdet_eint_type == IRQ_TYPE_LEVEL_HIGH)
				accdet_clear_bit(ACCDET_EINT0_IRQ_POLARITY_ADDR,
					ACCDET_EINT0_IRQ_POLARITY_SFT);
			else
				accdet_update_bit(
					ACCDET_EINT0_IRQ_POLARITY_ADDR,
					ACCDET_EINT0_IRQ_POLARITY_SFT);
		} else {
			if (accdet->accdet_eint_type == IRQ_TYPE_LEVEL_HIGH)
				accdet_update_bit(
					ACCDET_EINT0_IRQ_POLARITY_ADDR,
					ACCDET_EINT0_IRQ_POLARITY_SFT);
			else
				accdet_clear_bit(ACCDET_EINT0_IRQ_POLARITY_ADDR,
					ACCDET_EINT0_IRQ_POLARITY_SFT);
		}
	} else if (eint_id == PMIC_EINT1) {

		if (accdet->cur_eint_state == EINT_PLUG_OUT) {
			if (accdet->accdet_eint_type == IRQ_TYPE_LEVEL_HIGH)
				accdet_clear_bit(ACCDET_EINT1_IRQ_POLARITY_ADDR,
					ACCDET_EINT1_IRQ_POLARITY_SFT);
			else
				accdet_update_bit(
					ACCDET_EINT1_IRQ_POLARITY_ADDR,
					ACCDET_EINT1_IRQ_POLARITY_SFT);
		} else {
			if (accdet->accdet_eint_type == IRQ_TYPE_LEVEL_HIGH)
				accdet_update_bit(
					ACCDET_EINT1_IRQ_POLARITY_ADDR,
					ACCDET_EINT1_IRQ_POLARITY_SFT);
			else
				accdet_clear_bit(ACCDET_EINT1_IRQ_POLARITY_ADDR,
					ACCDET_EINT1_IRQ_POLARITY_SFT);
		}
	}
}
static inline void enable_accdet(u32 state_swctrl)
{
	/* enable ACCDET unit */
	accdet_update_bit(ACCDET_EN_ADDR, ACCDET_EN_SFT);
}

static inline void disable_accdet(void)
{
	/* sync with accdet_irq_handler set clear accdet irq bit to avoid to
	 * set clear accdet irq bit after disable accdet disable accdet irq
	 */
	clear_accdet_int();
	udelay(200);
	mutex_lock(&accdet->res_lock);
	clear_accdet_int_check();
	mutex_unlock(&accdet->res_lock);

	/* recover accdet debounce0,3 */
	accdet_set_debounce(accdet_state000, cust_pwm_deb->debounce0);
	accdet_set_debounce(accdet_state011, cust_pwm_deb->debounce3);

	accdet_clear_bit(ACCDET_EN_ADDR, ACCDET_EN_SFT);
	/* clc ACCDET PWM enable to avoid power leakage */
	accdet_clear_bits(ACCDET_CMP_PWM_EN_ADDR,
				ACCDET_CMP_PWM_EN_SFT, 0x7, 0x7);
}

static inline void headset_plug_out(void)
{
	send_status_event(accdet->cable_type, 0);
	accdet->accdet_status = PLUG_OUT;
	accdet->cable_type = NO_DEVICE;

	if (accdet->cur_key != 0) {
		send_key_event(accdet->cur_key, 0);
		accdet->cur_key = 0;
	}
	dis_micbias_done = false;
	pr_info("accdet %s, set cable_type = NO_DEVICE %d\n", __func__,
		dis_micbias_done);
}
static void dis_micbias_timerhandler(struct timer_list *t)
{
	int ret = 0;

	ret = queue_work(accdet->dis_micbias_workqueue,
			&accdet->dis_micbias_work);
	if (!ret)
		pr_notice("Error: %s (%d)\n", __func__, ret);
}

static void dis_micbias_work_callback(struct work_struct *work)
{
	u32 cur_AB = 0, eintID = 0;

	/* check EINT0 status, if plug out,
	 * not need to disable accdet here
	 */
	eintID = accdet_read_bits(ACCDET_EINT0_MEM_IN_ADDR,
		ACCDET_EINT0_MEM_IN_SFT,
		ACCDET_EINT0_MEM_IN_MASK);
	if (eintID == M_PLUG_OUT) {
		pr_notice("%s Plug-out, no dis micbias\n", __func__);
		return;
	}
	/* if modify_vref_volt called, not need to dis micbias again */
	if (dis_micbias_done == true) {
		pr_notice("%s modify_vref_volt called\n", __func__);
		return;
	}

	cur_AB = accdet_read(ACCDET_MEM_IN_ADDR) >> ACCDET_STATE_MEM_IN_OFFSET;
		cur_AB = cur_AB & ACCDET_STATE_AB_MASK;

	/* if 3pole disable accdet
	 * if <20k + 4pole, disable accdet will disable accdet
	 * plug out interrupt. The behavior will same as 3pole
	 */
	if ((accdet->cable_type == HEADSET_NO_MIC) ||
		(cur_AB == ACCDET_STATE_AB_00) ||
		(cur_AB == ACCDET_STATE_AB_11)) {
		/* disable accdet_sw_en=0
		 * disable accdet_hwmode_en=0
		 */
		accdet_clear_bits(ACCDET_CMP_PWM_IDLE_ADDR,
				ACCDET_CMP_PWM_IDLE_SFT, 0x7, 0x7);
		disable_accdet();
	}
}

static void eint_work_callback(struct work_struct *work)
{
	if (accdet->cur_eint_state == EINT_PLUG_IN) {
		mutex_lock(&accdet->res_lock);
		accdet->eint_sync_flag = true;
		mutex_unlock(&accdet->res_lock);
		__pm_wakeup_event(accdet->timer_lock,
			jiffies_to_msecs(7 * HZ));

		accdet_init();

		/* set PWM IDLE  on */
		accdet_update_bits(ACCDET_CMP_PWM_IDLE_ADDR,
				ACCDET_CMP_PWM_IDLE_SFT, 0x7, 0x7);

		if (HAS_CAP(accdet->data->caps, ACCDET_PMIC_EINT_IRQ)) {
			if (HAS_CAP(accdet->data->caps, ACCDET_PMIC_EINT0)) {
				accdet_update_bit(ACCDET_EINT0_PWM_IDLE_ADDR,
					ACCDET_EINT0_PWM_IDLE_SFT);
			} else if (HAS_CAP(accdet->data->caps,
					ACCDET_PMIC_EINT1)) {
				accdet_update_bit(ACCDET_EINT1_PWM_IDLE_ADDR,
					ACCDET_EINT1_PWM_IDLE_SFT);
			} else if (HAS_CAP(accdet->data->caps,
					ACCDET_PMIC_BI_EINT)) {
				accdet_update_bit(ACCDET_EINT0_PWM_IDLE_ADDR,
					ACCDET_EINT0_PWM_IDLE_SFT);
				accdet_update_bit(ACCDET_EINT1_PWM_IDLE_ADDR,
					ACCDET_EINT1_PWM_IDLE_SFT);
			}
		}
		accdet_update_bits(ACCDET_CMP_PWM_EN_ADDR,
				ACCDET_CMP_PWM_EN_SFT, 0x7, 0x7);

		enable_accdet(0);
	} else {
		mutex_lock(&accdet->res_lock);
		accdet->eint_sync_flag = false;
		accdet->thing_in_flag = false;
		mutex_unlock(&accdet->res_lock);
		timer_delete_sync(&micbias_timer);

		/* disable accdet_sw_en=0
		 */
		accdet_clear_bits(ACCDET_CMP_PWM_IDLE_ADDR,
			ACCDET_CMP_PWM_IDLE_SFT, 0x7, 0x7);
		disable_accdet();
		headset_plug_out();
	}

	if (HAS_CAP(accdet->data->caps, ACCDET_AP_GPIO_EINT))
		enable_irq(accdet->gpioirq);

}

void accdet_set_debounce(int state, unsigned int debounce)
{
	switch (state) {
	case accdet_state000:
		/* set ACCDET debounce value = debounce/32 ms */
		accdet_write(ACCDET_DEBOUNCE0_ADDR, debounce);
		break;
	case accdet_state001:
		accdet_write(ACCDET_DEBOUNCE1_ADDR, debounce);
		break;
	case accdet_state010:
		accdet_write(ACCDET_DEBOUNCE2_ADDR, debounce);
		break;
	case accdet_state011:
		accdet_write(ACCDET_DEBOUNCE3_ADDR, debounce);
		break;
	case accdet_auxadc:
		/* set auxadc debounce:0x42(2ms) */
		accdet_write(ACCDET_DEBOUNCE4_ADDR, debounce);
		break;
	case eint_state000:
		accdet_update_bits(ACCDET_EINT0_DEBOUNCE_ADDR,
				ACCDET_EINT0_DEBOUNCE_SFT,
				ACCDET_EINT0_DEBOUNCE_MASK,
				debounce);
		break;
	case eint_state001:
		accdet_update_bits(ACCDET_EINT1_DEBOUNCE_ADDR,
				ACCDET_EINT1_DEBOUNCE_SFT,
				ACCDET_EINT1_DEBOUNCE_MASK,
				debounce);
		break;
	default:
		pr_notice("Error: %s error state (%d)\n", __func__, state);
		break;
	}
}

static inline void check_cable_type(void)
{
	u32 cur_AB = 0;

	cur_AB = accdet_read(ACCDET_MEM_IN_ADDR) >> ACCDET_STATE_MEM_IN_OFFSET;
		cur_AB = cur_AB & ACCDET_STATE_AB_MASK;

	accdet->button_status = 0;

	switch (accdet->accdet_status) {
	case PLUG_OUT:
		if (cur_AB == ACCDET_STATE_AB_00) {
			mutex_lock(&accdet->res_lock);
			if (accdet->eint_sync_flag) {
				accdet->cable_type = HEADSET_NO_MIC;
				accdet->accdet_status = HOOK_SWITCH;
			} else
				pr_notice("accdet hp has been plug-out\n");
			mutex_unlock(&accdet->res_lock);
		} else if (cur_AB == ACCDET_STATE_AB_01) {
			mutex_lock(&accdet->res_lock);
			if (accdet->eint_sync_flag) {
				accdet->accdet_status = MIC_BIAS;
				accdet->cable_type = HEADSET_MIC;
				accdet_set_debounce(accdet_state011,
						cust_pwm_deb->debounce3 * 30);
			} else
				pr_notice("accdet hp has been plug-out\n");
			mutex_unlock(&accdet->res_lock);
			/* solution: adjust hook switch debounce time
			 * for fast key press condition, avoid to miss key
			 */
			accdet_set_debounce(accdet_state000,
				button_press_debounce);
		} else if (cur_AB == ACCDET_STATE_AB_11) {
			/* accdet PLUG_OUT state not change */
			if (HAS_CAP(accdet->data->caps,
					ACCDET_PMIC_EINT_IRQ)) {
				mutex_lock(&accdet->res_lock);
				if (accdet->eint_sync_flag) {
					accdet->accdet_status = PLUG_OUT;
					accdet->cable_type = NO_DEVICE;
				} else
					pr_notice("accdet hp been plug-out\n");
				mutex_unlock(&accdet->res_lock);
			}
		} else {
			pr_notice("accdet %s Invalid AB.Do nothing\n",
					__func__);
		}
		break;
	case MIC_BIAS:
		if (cur_AB == ACCDET_STATE_AB_00) {
			mutex_lock(&accdet->res_lock);
			if (accdet->eint_sync_flag) {
				accdet->button_status = 1;
				accdet->accdet_status = HOOK_SWITCH;
				multi_key_detection(cur_AB);
			} else
				pr_notice("accdet hp has been plug-out\n");
			mutex_unlock(&accdet->res_lock);
		} else if (cur_AB == ACCDET_STATE_AB_01) {
			mutex_lock(&accdet->res_lock);
			if (accdet->eint_sync_flag) {
				accdet->accdet_status = MIC_BIAS;
				accdet->cable_type = HEADSET_MIC;
				/* accdet MIC_BIAS state not change */
			} else
				pr_notice("accdet hp has been plug-out\n");
			mutex_unlock(&accdet->res_lock);
		} else if (cur_AB == ACCDET_STATE_AB_11) {
			/* accdet Don't send plug out in MIC_BIAS */
			mutex_lock(&accdet->res_lock);
			if (accdet->eint_sync_flag)
				accdet->accdet_status = PLUG_OUT;
			else
				pr_notice("accdet hp has been plug-out\n");
			mutex_unlock(&accdet->res_lock);
		} else {
			pr_notice("accdet %s Invalid AB.Do nothing\n",
					__func__);
		}
		break;
	case HOOK_SWITCH:
		if (cur_AB == ACCDET_STATE_AB_00) {
		} else if (cur_AB == ACCDET_STATE_AB_01) {
			mutex_lock(&accdet->res_lock);
			if (accdet->eint_sync_flag) {
				multi_key_detection(cur_AB);
				accdet->accdet_status = MIC_BIAS;
				accdet->cable_type = HEADSET_MIC;
			} else
				pr_notice("accdet hp has been plug-out\n");
			mutex_unlock(&accdet->res_lock);
		} else if (cur_AB == ACCDET_STATE_AB_11) {
			/* accdet Don't send plugout in HOOK_SWITCH */
			mutex_lock(&accdet->res_lock);
			if (accdet->eint_sync_flag)
				accdet->accdet_status = PLUG_OUT;
			else
				pr_notice("accdet hp has been plug-out\n");
			mutex_unlock(&accdet->res_lock);
		} else {
			pr_notice("accdet %s Invalid AB.Do nothing\n",
					__func__);
		}
		break;
	case STAND_BY:
		/* accdet %s STANDBY state.Err!Do nothing */
		break;
	default:
		/* accdet %s Error state.Do nothing */
		break;
	}
}

static void accdet_work_callback(struct work_struct *work)
{
	u32 pre_cable_type = accdet->cable_type;

	__pm_stay_awake(accdet->wake_lock);
	check_cable_type();

	mutex_lock(&accdet->res_lock);
	if (accdet->eint_sync_flag) {
		if (pre_cable_type != accdet->cable_type)
			send_status_event(accdet->cable_type, 1);
	}
	mutex_unlock(&accdet->res_lock);

	__pm_relax(accdet->wake_lock);
}

static void accdet_queue_work(void)
{
	int ret;

	if (accdet->accdet_status == MIC_BIAS)
		accdet->cali_voltage = accdet_get_auxadc();
	ret = queue_work(accdet->accdet_workqueue, &accdet->accdet_work);
	if (!ret)
		pr_notice("Error: %s (%d)\n", __func__, ret);
}

static int pmic_eint_queue_work(int eintID)
{
	int ret = 0;

	if (HAS_CAP(accdet->data->caps, ACCDET_PMIC_EINT0)) {
		if (eintID == PMIC_EINT0) {
			if (accdet->cur_eint_state == EINT_PLUG_IN) {
				accdet_set_debounce(eint_state000,
						ACCDET_EINT0_DEB_IN_256);
				accdet_set_debounce(accdet_state011,
					cust_pwm_deb->debounce3);
				accdet->cur_eint_state = EINT_PLUG_OUT;
			} else {
				accdet_set_debounce(eint_state000,
						ACCDET_EINT0_DEB_OUT_012);
				if (accdet->eint_id != M_PLUG_OUT) {
					accdet->cur_eint_state = EINT_PLUG_IN;

					mod_timer(&micbias_timer,
					jiffies + MICBIAS_DISABLE_TIMER);
				}
			}
			ret = queue_work(accdet->eint_workqueue,
					&accdet->eint_work);
		} else
			pr_notice("%s invalid EINT ID!\n", __func__);
	} else if (HAS_CAP(accdet->data->caps, ACCDET_PMIC_EINT1)) {
		if (eintID == PMIC_EINT1) {
			if (accdet->cur_eint_state == EINT_PLUG_IN) {
				accdet_set_debounce(eint_state001,
						ACCDET_EINT0_DEB_IN_256);
				accdet_set_debounce(accdet_state011,
					cust_pwm_deb->debounce3);
				accdet->cur_eint_state = EINT_PLUG_OUT;
			} else {
				accdet_set_debounce(eint_state001,
						ACCDET_EINT0_DEB_OUT_012);
				if (accdet->eint_id != M_PLUG_OUT) {
					accdet->cur_eint_state = EINT_PLUG_IN;

					mod_timer(&micbias_timer,
					jiffies + MICBIAS_DISABLE_TIMER);
				}
			}
			ret = queue_work(accdet->eint_workqueue,
					&accdet->eint_work);
		} else
			pr_notice("%s invalid EINT ID!\n", __func__);
	} else if (HAS_CAP(accdet->data->caps, ACCDET_PMIC_BI_EINT)) {
		if ((eintID & PMIC_EINT0) == PMIC_EINT0) {
			if (accdet->eint0_state == EINT_PLUG_IN) {
				accdet_set_debounce(accdet_state011,
					cust_pwm_deb->debounce3);
				accdet->eint0_state = EINT_PLUG_OUT;
			} else {
				if (accdet->eint_id != M_PLUG_OUT)
					accdet->eint0_state = EINT_PLUG_IN;
			}
		}
		if ((eintID & PMIC_EINT1) == PMIC_EINT1) {
			if (accdet->eint1_state == EINT_PLUG_IN) {
				accdet_set_debounce(accdet_state011,
					cust_pwm_deb->debounce3);
				accdet->eint1_state = EINT_PLUG_OUT;
			} else {
				if (accdet->eint_id != M_PLUG_OUT)
					accdet->eint1_state = EINT_PLUG_IN;
			}
		}

		/* bi_eint trigger issued current state, may */
		if (accdet->cur_eint_state == EINT_PLUG_OUT) {
			accdet->cur_eint_state =
				accdet->eint0_state & accdet->eint1_state;
			if (accdet->cur_eint_state == EINT_PLUG_IN) {
				mod_timer(&micbias_timer,
					jiffies + MICBIAS_DISABLE_TIMER);
				ret = queue_work(accdet->eint_workqueue,
						&accdet->eint_work);
			}
		} else if (accdet->cur_eint_state == EINT_PLUG_IN) {
			if ((accdet->eint0_state|accdet->eint1_state)
					== EINT_PLUG_OUT) {
				clear_accdet_eint_check(PMIC_EINT0);
				clear_accdet_eint_check(PMIC_EINT1);
			} else if ((accdet->eint0_state & accdet->eint1_state)
					== EINT_PLUG_OUT) {
				accdet->cur_eint_state = EINT_PLUG_OUT;
				ret = queue_work(accdet->eint_workqueue,
						&accdet->eint_work);
			}
		}
	}
	return ret;
}

static u32 moisture_detect(void)
{
	u32 moisture_vol = 0;
	u32 tmp_1 = 0, tmp_2 = 0, tmp_3 = 0;

	tmp_1 = accdet_read(RG_AUDACCDETRSV_ADDR);
	tmp_2 = accdet_read(RG_AUDPWDBMICBIAS1_ADDR);
	tmp_3 = accdet_read(RG_AUDACCDETMICBIAS0PULLLOW_ADDR);

	/* Disable ACCDET to AUXADC */
	accdet_write(RG_AUDACCDETMICBIAS0PULLLOW_ADDR,
			accdet_read(RG_AUDACCDETMICBIAS0PULLLOW_ADDR) & 0x1FFF);
	accdet_write(RG_AUDACCDETRSV_ADDR,
		accdet_read(RG_AUDACCDETRSV_ADDR) & 0xFBFF);
	accdet_write(RG_AUDACCDETRSV_ADDR,
		accdet_read(RG_AUDACCDETRSV_ADDR) | 0x800);

	/* Enable moisture detection, set 219A bit[13] = 1*/
	accdet_write(RG_AUDPWDBMICBIAS1_ADDR,
		accdet_read(RG_AUDPWDBMICBIAS1_ADDR) | 0x2000);

	/* select PAD_HP_EINT for moisture detection, set 219A bit[14] = 0*/
	accdet_write(RG_AUDPWDBMICBIAS1_ADDR,
		accdet_read(RG_AUDPWDBMICBIAS1_ADDR) & 0xBFFF);

	if (accdet_dts.moisture_use_ext_res == 0x0) {
		/* select VTH to 2v and 500k, use internal resitance,
		 * 219C bit[10][11][12] = 1
		 */
		accdet_write(RG_AUDACCDETMICBIAS0PULLLOW_ADDR,
			accdet_read(RG_AUDACCDETMICBIAS0PULLLOW_ADDR) | 0x1C00);

	} else if (accdet_dts.moisture_use_ext_res == 0x1) {
		/* select VTH to 2v and 500k, use external resitance
		 * set 219C bit[10] = 1, bit[11] [12]= 0
		 */
		accdet_write(RG_AUDACCDETMICBIAS0PULLLOW_ADDR,
			accdet_read(RG_AUDACCDETMICBIAS0PULLLOW_ADDR) & 0xE7FF);
		accdet_write(RG_AUDACCDETMICBIAS0PULLLOW_ADDR,
			accdet_read(RG_AUDACCDETMICBIAS0PULLLOW_ADDR) | 0x0400);
	}
	moisture_vol = accdet_get_auxadc();
	pr_info("%s accdet Moisture Read Auxadc=%d\n", __func__, moisture_vol);

	/* reverse register setting after reading moisture voltage */
	accdet_write(RG_AUDACCDETRSV_ADDR, tmp_1);
	accdet_write(RG_AUDPWDBMICBIAS1_ADDR, tmp_2);
	accdet_write(RG_AUDACCDETMICBIAS0PULLLOW_ADDR, tmp_3);

	return moisture_vol;
}

static void accdet_irq_handle(void)
{

	u32 eintID = 0;
	u32 irq_status = 0, acc_sts = 0, eint_sts = 0;
	int moisture_vol = 0;

	eintID = get_triggered_eint();
	irq_status = accdet_read(ACCDET_IRQ_ADDR);
	acc_sts = accdet_read(ACCDET_MEM_IN_ADDR);
	eint_sts = accdet_read(ACCDET_EINT0_MEM_IN_ADDR);

	if ((irq_status & ACCDET_IRQ_MASK_SFT) && (eintID == 0)) {
		clear_accdet_int();
		accdet_queue_work();
		clear_accdet_int_check();
	} else if (eintID != NO_PMIC_EINT) {
		pr_info("%s() IRQ:0x%x, eint-%s trig. cur_eint_state:%d\n",
		__func__, irq_status,
		(eintID == PMIC_EINT0)?"0":((eintID == PMIC_EINT1)?"1":"BI"),
		accdet->cur_eint_state);
		/* check EINT0 status */
		accdet->eint_id = accdet_read_bits(
			ACCDET_EINT0_MEM_IN_ADDR,
			ACCDET_EINT0_MEM_IN_SFT,
			ACCDET_EINT0_MEM_IN_MASK);
		/* adjust eint digital/analog setting */
		if (accdet->water_r != 0) {
			if (accdet->cur_eint_state ==
				EINT_MOISTURE_DETECTED) {
				pr_info("%s Moisture plug out detectecd\n",
					__func__);
				eint_polarity_reverse(eintID);
				accdet->cur_eint_state = EINT_PLUG_OUT;
				clear_accdet_eint(eintID);
				clear_accdet_eint_check(eintID);
				return;
			}

			if (accdet->cur_eint_state == EINT_PLUG_OUT) {
				pr_info("%s now check moisture\n", __func__);
				moisture_vol = moisture_detect();
			if (moisture_vol > accdet->moisture_vm) {
				eint_polarity_reverse(eintID);
				accdet->cur_eint_state =
					EINT_MOISTURE_DETECTED;
				clear_accdet_eint(eintID);
				clear_accdet_eint_check(eintID);
				pr_info("%s Moisture plug in detectecd!\n",
					__func__);
				return;
			}
			pr_info("%s check moisture done,not water.\n",
					__func__);
			}
		}
		eint_polarity_reverse(eintID);
		clear_accdet_eint(eintID);
		clear_accdet_eint_check(eintID);
		pmic_eint_queue_work(eintID);
	} else {
		pr_notice("%s no interrupt detected!\n", __func__);
	}
}

static irqreturn_t mtk_accdet_irq_handler_thread(int irq, void *data)
{
	accdet_irq_handle();

	return IRQ_HANDLED;
}

static int accdet_get_dts_data(void)
{
	int ret = 0;
	struct device_node *node = NULL;
	int pwm_deb[15] = {0};
	int three_key[4] = {0};
	u32 tmp = 0;

	node = of_find_matching_node(node, accdet_of_match);
	if (!node && standalone) {
		/* stock q20_v12 dtbo accdet node */
		static const int stock_pwm_deb[15] = {
			0x500, 0x500, 1, 0x1f0, 0x800, 0x800, 0x20, 0x44,
			0, 0, 0xe, 0, 0, 0, 0 };

		accdet_pmic = 0x66;
		accdet_dts.mic_vol = 6;
		accdet_dts.plugout_deb = 1;
		accdet_dts.mic_mode = HEADSET_MODE_1;
		accdet_dts.eint_pol = IRQ_TYPE_LEVEL_HIGH;
		memcpy(&accdet_dts.pwm_deb, stock_pwm_deb, sizeof(stock_pwm_deb));
		cust_pwm_deb = &accdet_dts.pwm_deb;
		accdet->data->caps |= ACCDET_PMIC_EINT_IRQ | ACCDET_PMIC_EINT0 |
				      ACCDET_PMIC_GPIO_TRIG_EINT | ACCDET_THREE_KEY;
		accdet_dts.three_key.mid = 80;
		accdet_dts.three_key.up = 220;
		accdet_dts.three_key.down = 400;
		dis_micbias_done = false;
		accdet->water_r = 0;
		accdet_dts.moisture_use_ext_res = -1;
		accdet_dts.eint_use_ext_res = 0;
		pr_info("accdet: standalone, stock parameters, caps=%x\n",
			accdet->data->caps);
		return 0;
	}
	if (!node) {
		pr_notice("Error: %s can't find compatible dts node\n",
			__func__);
		return -1;
	}

	ret = of_property_read_u32(node, "mediatek,accdet-pmic", &accdet_pmic);
	if (ret)
		accdet_pmic = 0x0;

	ret = of_property_read_u32(node,
			"accdet-mic-vol", &accdet_dts.mic_vol);
	if (ret)
		accdet_dts.mic_vol = 6;

	ret = of_property_read_u32(node, "accdet-plugout-debounce",
			&accdet_dts.plugout_deb);
	if (ret)
		accdet_dts.plugout_deb = 1;

	ret = of_property_read_u32(node,
			"accdet-mic-mode", &accdet_dts.mic_mode);
	if (ret)
		accdet_dts.mic_mode = 2;

	ret = of_property_read_u32_array(node, "headset-mode-setting", pwm_deb,
			ARRAY_SIZE(pwm_deb));
	/* debounce8(auxadc debounce) is default, needn't get from dts */
	if (!ret)
		memcpy(&accdet_dts.pwm_deb, pwm_deb, sizeof(pwm_deb));

	cust_pwm_deb = &accdet_dts.pwm_deb;

	ret = of_property_read_u32(node, "headset-eint-level-pol",
			&accdet_dts.eint_pol);
	if (ret)
		accdet_dts.eint_pol = 8;

	pr_info("accdet mic_vol=%d, plugout_deb=%d mic_mode=%d eint_pol=%d\n",
	     accdet_dts.mic_vol, accdet_dts.plugout_deb,
	     accdet_dts.mic_mode, accdet_dts.eint_pol);

	ret = of_property_read_u32(node,
			"headset-use-ap-eint", &tmp);
	if (ret)
		tmp = 0;
	if (tmp != 0)
		pr_notice("accdet: AP GPIO EINT unsupported, using PMIC EINT\n");
	accdet->data->caps |= ACCDET_PMIC_EINT_IRQ;

	ret = of_property_read_u32(node,
			"headset-eint-num", &tmp);
	if (ret)
		tmp = 0;
	if (tmp == 0)
		accdet->data->caps |= ACCDET_PMIC_EINT0;
	else if (tmp == 1)
		accdet->data->caps |= ACCDET_PMIC_EINT1;
	else if (tmp == 2)
		accdet->data->caps |= ACCDET_PMIC_BI_EINT;

	ret = of_property_read_u32(node,
			"headset-eint-trig-mode", &tmp);
	if (ret)
		tmp = 0;
	if (tmp == 0)
		accdet->data->caps |= ACCDET_PMIC_GPIO_TRIG_EINT;
	else if (tmp == 1)
		accdet->data->caps |= ACCDET_PMIC_INVERTER_TRIG_EINT;

	ret = of_property_read_u32(node,
			"headset-key-mode", &tmp);
	if (ret)
		tmp = 0;
	if (tmp == 0)
		accdet->data->caps |= ACCDET_THREE_KEY;
	else if (tmp == 1)
		accdet->data->caps |= ACCDET_FOUR_KEY;
	else if (tmp == 2)
		accdet->data->caps |= ACCDET_TRI_KEY_CDD;

	pr_info("accdet caps=%x\n", accdet->data->caps);
	if (HAS_CAP(accdet->data->caps, ACCDET_FOUR_KEY)) {
		int four_key[5];

		ret = of_property_read_u32_array(node,
				"headset-four-key-threshold",
			four_key, ARRAY_SIZE(four_key));
		if (!ret)
			memcpy(&accdet_dts.four_key, four_key+1,
					sizeof(struct four_key_threshold));
		else {
			pr_notice("accdet no 4-key-thrsh dts, use efuse\n");
			accdet_get_efuse_4key();
		}
	} else {
		if (HAS_CAP(accdet->data->caps, ACCDET_THREE_KEY)) {
			ret = of_property_read_u32_array(node,
					"headset-three-key-threshold",
					three_key, ARRAY_SIZE(three_key));
		} else {
			ret = of_property_read_u32_array(node,
				"headset-three-key-threshold-CDD", three_key,
				ARRAY_SIZE(three_key));
		}
		if (!ret)
			memcpy(&accdet_dts.three_key, three_key+1,
					sizeof(struct three_key_threshold));
	}
	dis_micbias_done = false;

	ret = of_property_read_u32(node, "moisture-water-r", &accdet->water_r);
	if (ret) {
		/* no moisture detection */
		accdet->water_r = 0x0;
	}
	ret = of_property_read_u32(node, "moisture_use_ext_res",
		&accdet_dts.moisture_use_ext_res);
	if (ret) {
		/* no moisture detection */
		accdet_dts.moisture_use_ext_res = -1;
	}
	if (accdet_dts.moisture_use_ext_res == 0x1) {
		of_property_read_u32(node, "moisture-external-r",
			&accdet->moisture_ext_r);
		pr_info("Moisture_EXT support water_r=%d, ext_r=%d\n",
		     accdet->water_r, accdet->moisture_ext_r);
	} else if (accdet_dts.moisture_use_ext_res == 0x0) {
		of_property_read_u32(node, "moisture-internal-r",
			&accdet->moisture_int_r);
		pr_info("Moisture_INT support water_r=%d, int_r=%d\n",
		     accdet->water_r, accdet->moisture_int_r);
	}
	ret = of_property_read_u32(node, "eint_use_ext_res",
		&accdet_dts.eint_use_ext_res);
	if (ret) {
		/* eint use internal resister */
		accdet_dts.eint_use_ext_res = 0x0;
	}
	return 0;
}

static inline void accdet_eint_high_level_support(void)
{
	unsigned int reg_val = 0;

	reg_val = 0;
	pr_debug("[accdet]eint_high_level_support enter--->\n");

	/* set high level trigger */
	if (HAS_CAP(accdet->data->caps, ACCDET_PMIC_EINT_IRQ)) {
		if (HAS_CAP(accdet->data->caps, ACCDET_PMIC_EINT0)) {
			if ((accdet->cur_eint_state == EINT_PLUG_OUT) &&
				(accdet_dts.eint_pol == IRQ_TYPE_LEVEL_HIGH)) {
				reg_val = accdet_read(ACCDET_IRQ_ADDR);
				pr_info("[accdet]pol = %d\n",
					accdet_dts.eint_pol);
				accdet->accdet_eint_type = IRQ_TYPE_LEVEL_HIGH;
				accdet_write(ACCDET_IRQ_ADDR, reg_val |
					ACCDET_EINT0_IRQ_POLARITY_MASK_SFT);

				reg_val =
					accdet_read(ACCDET_EINT0_SEQ_INIT_ADDR);
				/* set bit3 to en default EINT init status */
				accdet_write(ACCDET_EINT0_SEQ_INIT_ADDR,
					reg_val |
					ACCDET_EINT0_SEQ_INIT_MASK_SFT);
				usleep_range(2000, 3000);
				reg_val =
					accdet_read(ACCDET_EINT0_SEQ_INIT_ADDR);
				reg_val =
					accdet_read(ACCDET_EINT0_IVAL_SEL_ADDR);
				/* set default EINT init status */
				accdet_write(ACCDET_EINT0_IVAL_SEL_ADDR,
					(reg_val |
					 ACCDET_EINT0_IVAL_SEL_MASK_SFT) &
					(~ACCDET_EINT0_IVAL_B2_6_10));
				usleep_range(2000, 3000);
				reg_val =
					accdet_read(ACCDET_EINT0_IVAL_SEL_ADDR);
				/* clear bit3 to dis default EINT init status */
				reg_val =
					accdet_read(ACCDET_EINT0_SEQ_INIT_ADDR);
				accdet_write(ACCDET_EINT0_SEQ_INIT_ADDR,
					reg_val &
					(~ACCDET_EINT0_SEQ_INIT_MASK_SFT));
				reg_val = accdet_read(ACCDET_EINT0_DEBOUNCE_ADDR) &
					(~(0x0F<<3));
				accdet_write(ACCDET_EINT0_DEBOUNCE_ADDR, reg_val);
				accdet_write(ACCDET_EINT0_DEBOUNCE_ADDR, reg_val |
					ACCDET_EINT0_DEB_IN_256);
			}
		}
	}
}

static void config_digital_init_by_mode(void)
{
	unsigned int reg = 0;

	/* sw mode, */
	reg = accdet_read(ACCDET_HWEN_SEL_ADDR);
	accdet_write(ACCDET_HWEN_SEL_ADDR,
		(reg & (~ACCDET_HWMODE_SEL_BIT)) | ACCDET_FAST_DISCAHRGE);
}

static void config_eint_init_by_mode(void)
{
	if (HAS_CAP(accdet->data->caps, ACCDET_PMIC_EINT0)) {
		accdet_update_bits(ACCDET_EINT0_PWM_THRESH_ADDR, 0x8, 0x6, 0x6);
		accdet_update_bits(ACCDET_EINT0_PWM_WIDTH_ADDR, 0xc, 0x2, 0x2);

		accdet_update_bit(ACCDET_EINT0_PWM_EN_ADDR,
				ACCDET_EINT0_PWM_EN_SFT);
		accdet_update_bit(ACCDET_EINT0_PWM_IDLE_ADDR,
				ACCDET_EINT0_PWM_IDLE_SFT);
	} else if (HAS_CAP(accdet->data->caps, ACCDET_PMIC_EINT1)) {
		accdet_update_bits(ACCDET_EINT0_PWM_THRESH_ADDR, 0x8, 0x6, 0x6);
		accdet_update_bits(ACCDET_EINT0_PWM_WIDTH_ADDR, 0xc, 0x2, 0x2);

		accdet_update_bit(ACCDET_EINT1_PWM_EN_ADDR,
				ACCDET_EINT1_PWM_EN_SFT);
		accdet_update_bit(ACCDET_EINT1_PWM_IDLE_ADDR,
				ACCDET_EINT1_PWM_IDLE_SFT);
	} else if (HAS_CAP(accdet->data->caps, ACCDET_PMIC_BI_EINT)) {
		accdet_update_bits(ACCDET_EINT0_PWM_THRESH_ADDR, 0x8, 0x6, 0x6);
		accdet_update_bits(ACCDET_EINT0_PWM_WIDTH_ADDR, 0xc, 0x2, 0x2);

		accdet_update_bit(ACCDET_EINT0_PWM_EN_ADDR,
				ACCDET_EINT0_PWM_EN_SFT);
		accdet_update_bit(ACCDET_EINT0_PWM_IDLE_ADDR,
				ACCDET_EINT0_PWM_IDLE_SFT);
		accdet_update_bits(ACCDET_EINT0_PWM_THRESH_ADDR, 0x8, 0x6, 0x6);
		accdet_update_bits(ACCDET_EINT0_PWM_WIDTH_ADDR, 0xc, 0x2, 0x2);

		accdet_update_bit(ACCDET_EINT1_PWM_EN_ADDR,
				ACCDET_EINT1_PWM_EN_SFT);
		accdet_update_bit(ACCDET_EINT1_PWM_IDLE_ADDR,
				ACCDET_EINT1_PWM_IDLE_SFT);

	}
}

static void accdet_init_once(void)
{
	unsigned int reg = 0;

	/* HP_EINT trigger level 2.0 V: stock codec init does this, mainline mt6358 does not */
	accdet_update_bits(MT6358_AUDENC_ANA_CON11, RG_EINTCOMPVTH_SFT, 0x1, 0x1);

	/* reset the accdet unit */
	accdet_update_bit(RG_ACCDET_RST_ADDR,
			RG_ACCDET_RST_SFT);
	accdet_clear_bit(RG_ACCDET_RST_ADDR,
			RG_ACCDET_RST_SFT);

	/* init pwm frequency, duty & rise/falling delay */
	accdet_write(ACCDET_PWM_WIDTH_ADDR,
		REGISTER_VAL(cust_pwm_deb->pwm_width));
	accdet_write(ACCDET_PWM_THRESH_ADDR,
		REGISTER_VAL(cust_pwm_deb->pwm_thresh));
	accdet_write(ACCDET_RISE_DELAY_ADDR,
		  (cust_pwm_deb->fall_delay << 15 | cust_pwm_deb->rise_delay));

	/* config micbias voltage, micbias1 vref is only controlled by accdet
	 * if we need 2.8V, config [12:13]
	 */
	reg = accdet_read(RG_AUDPWDBMICBIAS1_ADDR);
	if (accdet_dts.mic_vol <= 7) {
		/* micbias1 <= 2.7V */
		accdet_write(RG_AUDPWDBMICBIAS1_ADDR,
		reg | (accdet_dts.mic_vol<<RG_AUDMICBIAS1VREF_SFT) | RG_AUDMICBIAS1LOWPEN_MASK_SFT);
	}
	/* mic mode setting */
	reg = accdet_read(RG_AUDACCDETMICBIAS0PULLLOW_ADDR);
	if (accdet_dts.mic_mode == HEADSET_MODE_1) {
		/* ACC mode*/
		accdet_write(RG_AUDACCDETMICBIAS0PULLLOW_ADDR,
			reg | RG_ACCDET_MODE_ANA11_MODE1);
	} else if (accdet_dts.mic_mode == HEADSET_MODE_2) {
		/* DCC mode Low cost mode without internal bias*/
		accdet_write(RG_AUDACCDETMICBIAS0PULLLOW_ADDR,
			reg | RG_ACCDET_MODE_ANA11_MODE2);
	} else if (accdet_dts.mic_mode == HEADSET_MODE_6) {
		/* DCC mode Low cost mode with internal bias,
		 * bit8 = 1 to use internal bias
		 */
		accdet_write(RG_AUDACCDETMICBIAS0PULLLOW_ADDR,
			reg | RG_ACCDET_MODE_ANA11_MODE6);
		accdet_update_bit(RG_AUDPWDBMICBIAS1_ADDR,
				RG_AUDMICBIAS1DCSW1PEN_SFT);
	}
	/* enable analog fast discharge */

	if (accdet_dts.eint_pol == IRQ_TYPE_LEVEL_LOW) {
		reg = accdet_read(RG_AUDSPARE_ADDR);
		accdet_write(RG_AUDSPARE_ADDR, reg |
			RG_AUDSPARE_FSTDSCHRG_IMPR_EN |
			RG_AUDSPARE_FSTDSCHRG_ANALOG_DIR_EN);
	} else {
		reg = accdet_read(RG_AUDSPARE_ADDR);
		accdet_write(RG_AUDSPARE_ADDR, (reg & (0xE0)));
	}

	if (HAS_CAP(accdet->data->caps, ACCDET_PMIC_EINT_IRQ)) {
		config_eint_init_by_mode();
		config_digital_init_by_mode();
	} else if (HAS_CAP(accdet->data->caps, ACCDET_AP_GPIO_EINT)) {
		//TBD
	}
	accdet_eint_high_level_support();

	/* accdet eint enable*/
	accdet_write(0x250a, 0x4);

	pr_info("%s done!\n", __func__);
}

static void accdet_init_debounce(void)
{
	/* set debounce to 1ms */
	accdet_set_debounce(eint_state000,
		accdet_dts.pwm_deb.eint_debounce0);
	/* set debounce to 128ms */
	accdet_set_debounce(eint_state011,
		accdet_dts.pwm_deb.eint_debounce3);
}

static inline void accdet_init(void)
{
	/* set and clear initial bit every eint interrutp */
	accdet_update_bit(ACCDET_SEQ_INIT_ADDR,
			ACCDET_SEQ_INIT_SFT);
	usleep_range(2000, 3000);
	accdet_clear_bit(ACCDET_SEQ_INIT_ADDR,
			ACCDET_SEQ_INIT_SFT);
	usleep_range(1000, 1500);
	/* init the debounce time (debounce/32768)sec */
	accdet_set_debounce(accdet_state000, cust_pwm_deb->debounce0);
	accdet_set_debounce(accdet_state001, cust_pwm_deb->debounce1);
	accdet_set_debounce(accdet_state011, cust_pwm_deb->debounce3);
	/* auxadc:2ms */
	accdet_set_debounce(accdet_auxadc, cust_pwm_deb->debounce4);
	accdet_set_debounce(eint_inverter_state000,
		accdet_dts.pwm_deb.eint_inverter_debounce);
	pr_info("%s() done.\n", __func__);
}

/* late init for DC trim, and this API  Will be called by audio */
void mt6358_accdet_late_init(unsigned long data)
{
	pr_info("%s()  now init accdet!\n", __func__);
	if (atomic_cmpxchg(&accdet_first, 1, 0)) {
		timer_delete_sync(&accdet_init_timer);
		accdet_init();
		accdet_init_debounce();
		accdet_init_once();
	} else
		pr_info("%s inited dts fail\n", __func__);
}
EXPORT_SYMBOL(mt6358_accdet_late_init);

static void delay_init_work_callback(struct work_struct *work)
{
	accdet_init();
	accdet_init_debounce();
	accdet_init_once();
}

static void delay_init_timerhandler(struct timer_list *t)
{
	int ret = 0;

	ret = queue_work(accdet->delay_init_workqueue,
			&accdet->delay_init_work);
	if (!ret)
		pr_notice("Error: %s (%d)\n", __func__, ret);
}

static struct snd_soc_jack_pin q25_jack_pins[] = {
	{ .pin = "Headphones", .mask = SND_JACK_HEADPHONE | SND_JACK_LINEOUT },
	{ .pin = "Headset Mic", .mask = SND_JACK_MICROPHONE },
};

/* Called by q25-mt6366-card (via symbol_get) once the card exists. */
int q25_accdet_attach(struct snd_soc_card *card)
{
	int ret;

	if (!accdet)
		return -ENODEV;
	ret = snd_soc_card_jack_new_pins(card, "Headset Jack",
					 SND_JACK_HEADSET | SND_JACK_LINEOUT |
					 SND_JACK_BTN_0 | SND_JACK_BTN_1 |
					 SND_JACK_BTN_2 | SND_JACK_BTN_3,
					 &accdet->jack, q25_jack_pins,
					 ARRAY_SIZE(q25_jack_pins));
	if (ret)
		return ret;

	snd_jack_set_key(accdet->jack.jack, SND_JACK_BTN_0, KEY_PLAYPAUSE);
	snd_jack_set_key(accdet->jack.jack, SND_JACK_BTN_1, KEY_VOLUMEDOWN);
	snd_jack_set_key(accdet->jack.jack, SND_JACK_BTN_2, KEY_VOLUMEUP);
	snd_jack_set_key(accdet->jack.jack, SND_JACK_BTN_3, KEY_VOICECOMMAND);
	accdet->jack_ready = true;
	dev_info(accdet->dev, "jack attached to card %s\n", card->name);

	mutex_lock(&accdet->res_lock);
	if (accdet->cable_type != NO_DEVICE)
		send_status_event(accdet->cable_type, 1);
	mutex_unlock(&accdet->res_lock);
	return 0;
}
EXPORT_SYMBOL_GPL(q25_accdet_attach);

static int mt6358_accdet_probe(struct platform_device *pdev)
{
	const char *irq_names[3];
	int irqs[3];
	int ret = 0, i = 0, nirq;
	struct mt6397_chip *mt6397_chip = dev_get_drvdata(pdev->dev.parent);
	const struct of_device_id *of_id =
				of_match_device(accdet_of_match, &pdev->dev);

	if (!of_id && !standalone) {
		dev_dbg(&pdev->dev, "Error: No device match found\n");
		return -ENODEV;
	}

	accdet = devm_kzalloc(&pdev->dev, sizeof(*accdet), GFP_KERNEL);
	if (!accdet)
		return -ENOMEM;

	accdet->data = of_id ? (struct accdet_priv *)of_id->data : mt6357_accdet;
	accdet->pdev = pdev;

	/* parse dts attributes */
	ret = accdet_get_dts_data();
	if (ret) {
		dev_dbg(&pdev->dev, "Error: Get dts data failed (%d)\n",
				ret);
		return ret;
	}
	/* init lock */
	accdet->wake_lock = wakeup_source_register(NULL, "accdet_wake_lock");
	if (!accdet->wake_lock)
		return -ENOMEM;
	accdet->timer_lock = wakeup_source_register(NULL, "accdet_timer_lock");
	if (!accdet->timer_lock)
		return -ENOMEM;
	mutex_init(&accdet->res_lock);

	platform_set_drvdata(pdev, accdet);

	if (!mt6397_chip || !mt6397_chip->regmap)
		return -EPROBE_DEFER;
	accdet->regmap = mt6397_chip->regmap;
	accdet->dev = &pdev->dev;

	/* get pmic auxadc iio channel handler */
	accdet->accdet_auxadc = devm_iio_channel_get(&pdev->dev, "pmic_accdet");
	ret = PTR_ERR_OR_ZERO(accdet->accdet_auxadc);
	if (ret == -EPROBE_DEFER)
		return ret;
	if (ret)
		dev_warn(&pdev->dev,
			 "no AUXADC channel (%d): buttons report as play/pause only\n", ret);

	/* get pmic efuse handler */
	accdet->accdet_efuse = devm_nvmem_device_get(&pdev->dev,
			"mt63xx-accdet-efuse");
	if (IS_ERR(accdet->accdet_efuse)) {
		dev_info(&pdev->dev, "no efuse (%ld): AUXADC offset 0\n",
			 PTR_ERR(accdet->accdet_efuse));
		accdet->accdet_efuse = NULL;
	} else {
		accdet_get_efuse();
	}

	timer_setup(&micbias_timer, dis_micbias_timerhandler, 0);
	timer_setup(&accdet_init_timer, delay_init_timerhandler, 0);
	INIT_WORK(&accdet->delay_init_work, delay_init_work_callback);
	INIT_WORK(&accdet->accdet_work, accdet_work_callback);
	INIT_WORK(&accdet->dis_micbias_work, dis_micbias_work_callback);
	INIT_WORK(&accdet->eint_work, eint_work_callback);
	accdet->delay_init_workqueue = create_singlethread_workqueue("delay_init");
	accdet->accdet_workqueue = create_singlethread_workqueue("accdet");
	accdet->dis_micbias_workqueue = create_singlethread_workqueue("dismicQueue");
	accdet->eint_workqueue = create_singlethread_workqueue("accdet_eint");
	if (!accdet->delay_init_workqueue || !accdet->accdet_workqueue ||
	    !accdet->dis_micbias_workqueue || !accdet->eint_workqueue) {
		ret = -ENOMEM;
		goto err_wq;
	}

	/* requested last: the handlers queue work on the queues above */
	nirq = 0;
	irq_names[nirq++] = "ACCDET_IRQ";
	if (HAS_CAP(accdet->data->caps, ACCDET_PMIC_EINT0) ||
	    HAS_CAP(accdet->data->caps, ACCDET_PMIC_BI_EINT))
		irq_names[nirq++] = "ACCDET_EINT0";
	if (HAS_CAP(accdet->data->caps, ACCDET_PMIC_EINT1) ||
	    HAS_CAP(accdet->data->caps, ACCDET_PMIC_BI_EINT))
		irq_names[nirq++] = "ACCDET_EINT1";
	for (i = 0; i < nirq; i++) {
		irqs[i] = platform_get_irq_byname(pdev, irq_names[i]);
		if (irqs[i] < 0) {
			ret = irqs[i];
			goto err_irq;
		}
		ret = devm_request_threaded_irq(&pdev->dev, irqs[i], NULL,
						mtk_accdet_irq_handler_thread,
						IRQF_TRIGGER_HIGH | IRQF_ONESHOT,
						irq_names[i], accdet);
		if (ret)
			goto err_irq;
		if (!strcmp(irq_names[i], "ACCDET_IRQ"))
			accdet->accdet_irq = irqs[i];
		else if (!strcmp(irq_names[i], "ACCDET_EINT0"))
			accdet->accdet_eint0 = irqs[i];
		else
			accdet->accdet_eint1 = irqs[i];
	}

	atomic_set(&accdet_first, 1);
	mod_timer(&accdet_init_timer, jiffies + ACCDET_INIT_WAIT_TIMER);
	dev_info(&pdev->dev, "probed, caps 0x%x, init in %d s\n",
		 accdet->data->caps, ACCDET_INIT_WAIT_TIMER / HZ);
	return 0;

err_irq:
	while (i--)
		devm_free_irq(&pdev->dev, irqs[i], accdet);
err_wq:
	if (accdet->eint_workqueue)
		destroy_workqueue(accdet->eint_workqueue);
	if (accdet->dis_micbias_workqueue)
		destroy_workqueue(accdet->dis_micbias_workqueue);
	if (accdet->accdet_workqueue)
		destroy_workqueue(accdet->accdet_workqueue);
	if (accdet->delay_init_workqueue)
		destroy_workqueue(accdet->delay_init_workqueue);
	return ret;
}

static int q25_accdet_probe(struct platform_device *pdev)
{
	int ret = mt6358_accdet_probe(pdev);

	if (ret) {
		if (accdet) {
			wakeup_source_unregister(accdet->timer_lock);
			wakeup_source_unregister(accdet->wake_lock);
		}
		accdet = NULL;
		dev_err_probe(&pdev->dev, ret, "probe failed\n");
	}
	return ret;
}

static struct platform_driver accdet_driver = {
	.probe = q25_accdet_probe,
	.driver = {
		.name = "q25-mt6358-accdet",
		.suppress_bind_attrs = true,
		.of_match_table = accdet_of_match,
	},
};

static struct platform_device *q25_accdet_pdev;

#define Q25_PMIC_PATH "/soc/pmic-wrapper@10026000/pmic"

static struct iio_map q25_accdet_iio_map[] = {
	IIO_MAP("acc_det", "q25-mt6358-accdet", "pmic_accdet"),
	{ }
};

static int q25_is_iio_dev(struct device *dev, const void *data)
{
	return !strncmp(dev_name(dev), "iio:device", 10);
}

static void q25_accdet_map_auxadc(struct device_node *pmic_np)
{
	struct device_node *adc_np = of_get_child_by_name(pmic_np, "adc");
	struct platform_device *adc = adc_np ? of_find_device_by_node(adc_np) : NULL;
	struct device *iio = adc ? device_find_child(&adc->dev, NULL, q25_is_iio_dev) : NULL;
	int ret = -ENODEV;

	if (iio)
		ret = iio_map_array_register(dev_to_iio_dev(iio), q25_accdet_iio_map);
	if (ret)
		pr_warn("q25-accdet: AUXADC map failed (%d), buttons degrade\n", ret);
	put_device(iio);
	if (adc)
		put_device(&adc->dev);
	of_node_put(adc_np);
}

static int q25_pmic_irq(struct device_node *pmic_np, u32 hwirq)
{
	struct irq_fwspec fwspec = {
		.fwnode = of_fwnode_handle(pmic_np),
		.param_count = 2,
		.param = { hwirq, IRQ_TYPE_NONE },
	};
	int irq = irq_create_fwspec_mapping(&fwspec);

	return irq ? irq : -ENXIO;
}

/* No DT node: same device the overlay would create, resources built in. */
static int q25_accdet_standalone_init(void)
{
	struct device_node *pmic_np = of_find_node_by_path(Q25_PMIC_PATH);
	struct platform_device *pmic = pmic_np ? of_find_device_by_node(pmic_np) : NULL;
	struct resource res[2];
	struct platform_device_info info = {
		.name = "q25-mt6358-accdet",
		.id = PLATFORM_DEVID_NONE,
		.res = res,
		.num_res = ARRAY_SIZE(res),
	};
	int irq, eint0, ret = -ENODEV;

	if (!pmic)
		goto out;
	irq = q25_pmic_irq(pmic_np, MT6358_IRQ_ACCDET);
	eint0 = q25_pmic_irq(pmic_np, MT6358_IRQ_ACCDET_EINT0);
	if (irq < 0 || eint0 < 0) {
		ret = -ENXIO;
		goto out;
	}
	res[0] = DEFINE_RES_IRQ_NAMED(irq, "ACCDET_IRQ");
	res[1] = DEFINE_RES_IRQ_NAMED(eint0, "ACCDET_EINT0");
	info.parent = &pmic->dev;

	q25_accdet_map_auxadc(pmic_np);
	ret = platform_driver_register(&accdet_driver);
	if (ret)
		goto out;
	q25_accdet_pdev = platform_device_register_full(&info);
	if (IS_ERR(q25_accdet_pdev)) {
		ret = PTR_ERR(q25_accdet_pdev);
		q25_accdet_pdev = NULL;
		platform_driver_unregister(&accdet_driver);
		goto out;
	}
	pr_info("q25-accdet: standalone device, irq %d eint0 %d\n", irq, eint0);
out:
	if (pmic)
		put_device(&pmic->dev);
	of_node_put(pmic_np);
	return ret;
}

static int __init accdet_soc_init(void)
{
	struct device_node *np = of_find_matching_node(NULL, accdet_of_match);
	struct platform_device *pmic;
	int ret;

	if (!np && standalone)
		return q25_accdet_standalone_init();
	/* stay loadable without the DT node so the card's softdep never fails */
	if (!np) {
		pr_info("q25-accdet: no accdet DT node, headset detection off\n");
		return 0;
	}
	pmic = of_find_device_by_node(np->parent);
	if (!pmic) {
		of_node_put(np);
		return -ENODEV;
	}
	ret = platform_driver_register(&accdet_driver);
	if (!ret) {
		q25_accdet_pdev = of_platform_device_create(np, NULL, &pmic->dev);
		if (!q25_accdet_pdev) {
			platform_driver_unregister(&accdet_driver);
			ret = -ENODEV;
		}
	}
	put_device(&pmic->dev);
	of_node_put(np);
	return ret;
}
module_init(accdet_soc_init);

/* Module information */
MODULE_DESCRIPTION("MT6358/MT6366 ACCDET headset detection for Zinwa Q25 (from the stock driver)");
MODULE_LICENSE("GPL v2");
