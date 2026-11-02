// SPDX-License-Identifier: GPL-2.0-only
/*
 * MediaTek MT6789 CONNSYS GNSS.
 *
 * The GNSS function of CONNSYS is a host-based receiver: a DSP, loaded from
 * the host at every power-on, tracks satellites and streams per-channel data
 * in MediaTek's binary framing; acquisition control and positioning run on
 * the host. This driver powers the function, downloads the DSP image and
 * then passes the binary stream through a GNSS device. The protocol is
 * described in docs/hardware/mt6789-gnss.md of Marathon-Shell.
 *
 * Power and the byte channel come from MediaTek's out-of-tree WMT/STP stack
 * (wmt_drv) until an upstream CONNSYS driver exists; only the functions
 * under "transport" depend on it.
 */
#include <linux/completion.h>
#include <linux/delay.h>
#include <linux/firmware.h>
#include <linux/gnss.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/of_platform.h>
#include <linux/pinctrl/consumer.h>
#include <linux/platform_device.h>
#include <linux/slab.h>
#include <linux/unaligned.h>
#include <linux/workqueue.h>

#include "osal_typedef.h"
#include "wmt_exp.h"
#include "stp_exp.h"

#define DRV_NAME		"mtk-connsys-gnss"
#define MT6789_GNSS_FW		"mediatek/mt6789/gnss-l1-dsp.bin"

/* Frame: AA F0, then len, id, payload, sum (all escaped), then AA 0F. */
#define FR_SYNC			0xaa
#define FR_START		0xf0
#define FR_END			0x0f
#define FR_ESC			0xde
#define FR_MAX_PAYLOAD		(2 + 1400)

#define MSG_HOST_CTRL		0xfe05
#define MSG_BOOT_PARAMS		0xfe08
#define MSG_BOOT_CODE		0xfe0c
#define MSG_BOOT_PARAMS_ACK	0xfe31
#define MSG_BOOT_CODE_ACK	0xfe32

/* DSP image: le16 words, start address, entry address, cipher key; code. */
#define IMG_HDR_LEN		8
#define CHUNK			1400
#define HALF_CHUNK		700
#define MAX_FRAGS		255
#define TRIES			5

/*
 * Boot parameters the stock engine sends for this SoC with its 26 MHz
 * co-clock, GPS+GLONASS+Galileo+BeiDou and no host-driven LNA pin. Bytes
 * 14-23 are filled from the image.
 */
static const u8 mt6789_boot_params[106] = {
	0x1a, 0x00, 0x00, 0x00, 0x00, 0x01, 0xc3, 0x01, 0xa5, 0x02, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x05, 0x00, 0x9d, 0x00, 0x6f, 0x3c, 0x88, 0x89,
	0xa2, 0x04, 0x02, 0x00, 0xdc, 0x00, 0xc1, 0x00, 0x28, 0x00, 0x5c, 0x4a,
	0x1e, 0x00, 0xc5, 0x37, 0x28, 0x00, 0x5c, 0x4a, 0x8f, 0x65, 0x07, 0x00,
	0x01, 0x00, 0x28, 0x00, 0xff, 0x00, 0x80, 0x00, 0x47, 0x00, 0x64, 0x00,
	0x50, 0x00, 0xd8, 0x00, 0x50, 0x00, 0xbb, 0x00, 0x03, 0x00, 0x3c, 0x00,
	0x6f, 0x00, 0x89, 0x00, 0x88, 0x00, 0x02, 0x00, 0xfb, 0x00, 0x01, 0x00,
	0x89, 0x67, 0xff, 0x0a, 0x00, 0x00, 0x01, 0x00, 0x4e, 0x4f,
};

enum rx_state { RX_HUNT, RX_START, RX_BODY, RX_ESC, RX_END };

struct mtk_gnss {
	struct device *dev;
	struct gnss_device *gdev;
	struct pinctrl *pinctrl;
	struct pinctrl_state *lna_off;
	struct pinctrl_state *lna_dsp;
	struct work_struct rx_work;
	struct mutex lock;		/* open/close */
	bool powered;
	bool booting;
	u8 rx_chunk[2048];

	/* boot-time receive state */
	enum rx_state rx_state;
	u8 rx_frame[16];
	unsigned int rx_len;
	bool rx_overflow;
	struct completion ack;
	u16 ack_id;
	u16 ack_seq;
	u16 last_seq;

	u8 frag[FR_MAX_PAYLOAD];
	u8 tx[2 * (6 + FR_MAX_PAYLOAD) + 4];
};

static struct mtk_gnss *mtk_gnss_dev;

/* transport */

static int mtk_gnss_stp_send(const u8 *buf, size_t len)
{
	int tries = 100;
	int n;

	do {
		n = mtk_wcn_stp_send_data((PUINT8)buf, len, GPS_TASK_INDX);
		if (n == len)
			return 0;
		if (n != 0)
			return -EIO;
		/* No STP window left: the firmware drains it within milliseconds. */
		usleep_range(1000, 2000);
	} while (--tries);

	return -ETIMEDOUT;
}

static void mtk_gnss_stp_event(void)
{
	if (mtk_gnss_dev && READ_ONCE(mtk_gnss_dev->powered))
		schedule_work(&mtk_gnss_dev->rx_work);
}

static void mtk_gnss_wmt_msg(ENUM_WMTDRV_TYPE_T src, ENUM_WMTDRV_TYPE_T dst,
			     ENUM_WMTMSG_TYPE_T type, PVOID buf, UINT32 sz)
{
	ENUM_WMTRSTMSG_TYPE_T msg = 0;

	if (src != WMTDRV_TYPE_WMT || dst != WMTDRV_TYPE_GPS ||
	    type != WMTMSG_TYPE_RESET || !buf || sz > sizeof(msg))
		return;
	memcpy(&msg, buf, sz);
	/* The DSP image is gone after a whole-chip reset; reopen to reload it. */
	if (msg == WMTRSTMSG_RESET_START)
		dev_warn(mtk_gnss_dev->dev, "CONNSYS reset, reopen to restart GNSS\n");
}

static int mtk_gnss_power_on(struct mtk_gnss *g)
{
	if (mtk_wcn_wmt_func_on(WMTDRV_TYPE_GPS) == MTK_WCN_BOOL_FALSE)
		return -EIO;
	if (mtk_wcn_stp_is_ready() == MTK_WCN_BOOL_FALSE) {
		mtk_wcn_wmt_func_off(WMTDRV_TYPE_GPS);
		return -EIO;
	}
	WRITE_ONCE(g->powered, true);
	mtk_wcn_stp_register_event_cb(GPS_TASK_INDX, mtk_gnss_stp_event);
	mtk_wcn_wmt_msgcb_reg(WMTDRV_TYPE_GPS, mtk_gnss_wmt_msg);
	return 0;
}

static void mtk_gnss_power_off(struct mtk_gnss *g)
{
	mtk_wcn_wmt_msgcb_unreg(WMTDRV_TYPE_GPS);
	mtk_wcn_stp_register_event_cb(GPS_TASK_INDX, NULL);
	WRITE_ONCE(g->powered, false);
	cancel_work_sync(&g->rx_work);
	if (mtk_wcn_wmt_func_off(WMTDRV_TYPE_GPS) == MTK_WCN_BOOL_FALSE)
		dev_warn(g->dev, "WMT GPS function off failed\n");
}

/* framing */

static size_t mtk_gnss_put(u8 *p, size_t n, const u8 *src, size_t len)
{
	while (len--) {
		u8 b = *src++;

		if (b == FR_SYNC || b == FR_ESC) {
			p[n++] = FR_ESC;
			b = b == FR_SYNC ? 0xdf : 0xe0;
		}
		p[n++] = b;
	}
	return n;
}

static size_t mtk_gnss_frame(u8 *p, u16 id, const u8 *payload, size_t len)
{
	u8 hdr[4], sum[2];
	u16 s = 0;
	size_t i, n = 0;

	put_unaligned_le16(len + 4, hdr);
	put_unaligned_le16(id, hdr + 2);
	for (i = 0; i < sizeof(hdr); i++)
		s += hdr[i];
	for (i = 0; i < len; i++)
		s += payload[i];
	put_unaligned_le16(s, sum);

	p[n++] = FR_SYNC;
	p[n++] = FR_START;
	n = mtk_gnss_put(p, n, hdr, sizeof(hdr));
	n = mtk_gnss_put(p, n, payload, len);
	n = mtk_gnss_put(p, n, sum, sizeof(sum));
	p[n++] = FR_SYNC;
	p[n++] = FR_END;
	return n;
}

static int mtk_gnss_send(struct mtk_gnss *g, u16 id, const u8 *payload, size_t len)
{
	return mtk_gnss_stp_send(g->tx, mtk_gnss_frame(g->tx, id, payload, len));
}

/* Only the small acknowledgements matter while booting; longer frames are skipped. */
static void mtk_gnss_rx_frame(struct mtk_gnss *g)
{
	const u8 *f = g->rx_frame;
	u16 len, sum = 0;
	unsigned int i;

	if (g->rx_overflow || g->rx_len < 8)
		return;
	len = get_unaligned_le16(f) & 0xfff;
	if (len + 2 != g->rx_len)
		return;
	for (i = 0; i < g->rx_len - 2; i++)
		sum += f[i];
	if (sum != get_unaligned_le16(f + g->rx_len - 2))
		return;

	g->ack_id = get_unaligned_le16(f + 2);
	g->ack_seq = get_unaligned_le16(f + 4);
	if (g->ack_id == MSG_BOOT_CODE_ACK && g->ack_seq == g->last_seq)
		WRITE_ONCE(g->booting, false);
	complete(&g->ack);
}

static void mtk_gnss_rx_byte(struct mtk_gnss *g, u8 b)
{
	switch (g->rx_state) {
	case RX_HUNT:
		if (b == FR_SYNC)
			g->rx_state = RX_START;
		return;
	case RX_START:
		g->rx_state = b == FR_START ? RX_BODY : b == FR_SYNC ? RX_START : RX_HUNT;
		g->rx_len = 0;
		g->rx_overflow = false;
		return;
	case RX_BODY:
		if (b == FR_SYNC) {
			g->rx_state = RX_END;
			return;
		}
		if (b == FR_ESC) {
			g->rx_state = RX_ESC;
			return;
		}
		break;
	case RX_ESC:
		g->rx_state = RX_BODY;
		if (b != 0xdf && b != 0xe0) {
			g->rx_state = RX_HUNT;
			return;
		}
		b = b == 0xdf ? FR_SYNC : FR_ESC;
		break;
	case RX_END:
		g->rx_state = RX_HUNT;
		if (b == FR_END) {
			mtk_gnss_rx_frame(g);
		} else if (b == FR_START) {
			/* AA F0 inside a frame: the previous one was cut short. */
			g->rx_state = RX_START;
			mtk_gnss_rx_byte(g, b);
		}
		return;
	}
	if (g->rx_len < sizeof(g->rx_frame))
		g->rx_frame[g->rx_len++] = b;
	else
		g->rx_overflow = true;
}

static void mtk_gnss_rx_work(struct work_struct *work)
{
	struct mtk_gnss *g = container_of(work, struct mtk_gnss, rx_work);
	int n, i;

	while (READ_ONCE(g->powered) && !mtk_wcn_stp_is_rxqueue_empty(GPS_TASK_INDX)) {
		n = mtk_wcn_stp_receive_data(g->rx_chunk, sizeof(g->rx_chunk), GPS_TASK_INDX);
		if (n <= 0)
			break;
		for (i = 0; i < n && READ_ONCE(g->booting); i++)
			mtk_gnss_rx_byte(g, g->rx_chunk[i]);
		if (i < n)
			gnss_insert_raw(g->gdev, g->rx_chunk + i, n - i);
	}
}

/* DSP boot */

static bool mtk_gnss_split(const u8 *p, size_t len, bool last)
{
	size_t i, esc = 0;

	for (i = 0; i < len; i++)
		esc += p[i] == FR_SYNC || p[i] == FR_ESC;
	if (esc < 14)
		return false;
	return !last || esc + len >= 0x586;
}

/*
 * Chunks of 1400 bytes; one that would grow too much when escaped goes as
 * two fragments, the first 700 bytes long. Returns the fragment count and
 * fills sizes[], or 0 if the image needs more than the DSP accepts.
 */
static unsigned int mtk_gnss_plan(const u8 *code, size_t len, u16 *sizes)
{
	size_t chunks = (len + IMG_HDR_LEN + CHUNK - 1) / CHUNK;
	unsigned int n = 0;
	size_t c;

	for (c = 0; c < chunks; c++) {
		bool last = c == chunks - 1;
		size_t sz = last ? len - c * CHUNK : CHUNK;

		if (n + 2 > MAX_FRAGS || c * CHUNK > len)
			return 0;
		if (sz && mtk_gnss_split(code + c * CHUNK, sz, last)) {
			sizes[n++] = HALF_CHUNK;
			sizes[n++] = sz - HALF_CHUNK;
		} else {
			sizes[n++] = sz;
		}
	}
	return n;
}

static int mtk_gnss_wait_ack(struct mtk_gnss *g, u16 id, u16 seq, unsigned int ms)
{
	unsigned long left = msecs_to_jiffies(ms);

	while ((left = wait_for_completion_timeout(&g->ack, left)))
		if (g->ack_id == id && g->ack_seq == seq)
			return 0;
	return -ETIMEDOUT;
}

static int mtk_gnss_boot_params(struct mtk_gnss *g, const u8 *hdr, unsigned int frags)
{
	static const u8 reset[2] = { 0x04, 0x00 };
	u8 params[sizeof(mt6789_boot_params)];
	int r, i, ret;

	memcpy(params, mt6789_boot_params, sizeof(params));
	memcpy(params + 14, hdr, IMG_HDR_LEN);
	put_unaligned_le16(frags, params + 22);

	for (r = 0; r < TRIES; r++) {
		reinit_completion(&g->ack);
		ret = mtk_gnss_send(g, MSG_BOOT_PARAMS, params, sizeof(params));
		if (ret)
			return ret;
		if (!mtk_gnss_wait_ack(g, MSG_BOOT_PARAMS_ACK, 0, 200 << r))
			return 0;
		/* Kick the boot ROM as the stock engine does, then retry. */
		for (i = 0; i < 3; i++) {
			ret = mtk_gnss_send(g, MSG_HOST_CTRL, reset, sizeof(reset));
			if (ret)
				return ret;
		}
		msleep(500 * (r + 1));
	}
	return -ETIMEDOUT;
}

static int mtk_gnss_boot_code(struct mtk_gnss *g, const u8 *code, const u16 *sizes,
			      unsigned int frags)
{
	u8 *buf = g->frag;
	unsigned int seq;
	int r, ret;

	for (seq = 1; seq <= frags; seq++) {
		size_t sz = sizes[seq - 1];

		put_unaligned_le16(seq, buf);
		memcpy(buf + 2, code, sz);
		code += sz;
		for (r = 0; r < TRIES; r++) {
			reinit_completion(&g->ack);
			ret = mtk_gnss_send(g, MSG_BOOT_CODE, buf, sz + 2);
			if (ret)
				return ret;
			if (!mtk_gnss_wait_ack(g, MSG_BOOT_CODE_ACK, seq, 200 << r))
				break;
		}
		if (r == TRIES) {
			dev_err(g->dev, "DSP did not take fragment %u of %u\n", seq, frags);
			return -ETIMEDOUT;
		}
	}
	return 0;
}

static int mtk_gnss_boot(struct mtk_gnss *g)
{
	const struct firmware *fw;
	unsigned int frags;
	u16 *sizes;
	size_t len;
	int ret;

	ret = request_firmware(&fw, MT6789_GNSS_FW, g->dev);
	if (ret)
		return ret;
	len = fw->size - IMG_HDR_LEN;
	if (fw->size < IMG_HDR_LEN || 2 * get_unaligned_le16(fw->data) != len) {
		dev_err(g->dev, "%s: bad image header\n", MT6789_GNSS_FW);
		ret = -EINVAL;
		goto out_fw;
	}
	sizes = kcalloc(MAX_FRAGS, sizeof(*sizes), GFP_KERNEL);
	if (!sizes) {
		ret = -ENOMEM;
		goto out_fw;
	}
	frags = mtk_gnss_plan(fw->data + IMG_HDR_LEN, len, sizes);
	if (!frags) {
		ret = -EINVAL;
		goto out_sizes;
	}

	g->rx_state = RX_HUNT;
	g->last_seq = frags;
	WRITE_ONCE(g->booting, true);
	ret = mtk_gnss_boot_params(g, fw->data, frags);
	if (ret)
		dev_err(g->dev, "DSP boot ROM did not answer\n");
	else
		ret = mtk_gnss_boot_code(g, fw->data + IMG_HDR_LEN, sizes, frags);
	if (ret)
		WRITE_ONCE(g->booting, false);
	else
		dev_info(g->dev, "DSP running (%u fragments)\n", frags);

out_sizes:
	kfree(sizes);
out_fw:
	release_firmware(fw);
	return ret;
}

/* GNSS device */

static void mtk_gnss_lna(struct mtk_gnss *g, struct pinctrl_state *s)
{
	if (s && pinctrl_select_state(g->pinctrl, s))
		dev_warn(g->dev, "cannot set the LNA pin state\n");
}

static int mtk_gnss_open(struct gnss_device *gdev)
{
	struct mtk_gnss *g = gnss_get_drvdata(gdev);
	int ret;

	mutex_lock(&g->lock);
	/* The DSP drives the LNA enable once its pin is muxed to it. */
	mtk_gnss_lna(g, g->lna_dsp);
	ret = mtk_gnss_power_on(g);
	if (ret) {
		dev_err(g->dev, "WMT GPS function on failed\n");
		goto err_lna;
	}
	ret = mtk_gnss_boot(g);
	if (ret)
		goto err_power;
	mutex_unlock(&g->lock);
	return 0;

err_power:
	mtk_gnss_power_off(g);
err_lna:
	mtk_gnss_lna(g, g->lna_off);
	mutex_unlock(&g->lock);
	return ret;
}

static void mtk_gnss_close(struct gnss_device *gdev)
{
	struct mtk_gnss *g = gnss_get_drvdata(gdev);

	mutex_lock(&g->lock);
	mtk_gnss_power_off(g);
	mtk_gnss_lna(g, g->lna_off);
	mutex_unlock(&g->lock);
}

static int mtk_gnss_write_raw(struct gnss_device *gdev, const unsigned char *buf,
			      size_t count)
{
	int ret = mtk_gnss_stp_send(buf, count);

	return ret ? ret : count;
}

static const struct gnss_operations mtk_gnss_ops = {
	.open		= mtk_gnss_open,
	.close		= mtk_gnss_close,
	.write_raw	= mtk_gnss_write_raw,
};

static struct pinctrl_state *mtk_gnss_state(struct mtk_gnss *g, const char *name)
{
	struct pinctrl_state *s = pinctrl_lookup_state(g->pinctrl, name);

	return IS_ERR(s) ? NULL : s;
}

static int mtk_gnss_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct gnss_device *gdev;
	struct mtk_gnss *g;
	int ret;

	g = devm_kzalloc(dev, sizeof(*g), GFP_KERNEL);
	if (!g)
		return -ENOMEM;
	g->dev = dev;
	mutex_init(&g->lock);
	init_completion(&g->ack);
	INIT_WORK(&g->rx_work, mtk_gnss_rx_work);

	g->pinctrl = devm_pinctrl_get(dev);
	if (IS_ERR(g->pinctrl))
		return dev_err_probe(dev, PTR_ERR(g->pinctrl), "pinctrl\n");
	g->lna_off = mtk_gnss_state(g, PINCTRL_STATE_DEFAULT);
	g->lna_dsp = mtk_gnss_state(g, "active");
	if (!g->lna_dsp)
		dev_warn(dev, "no LNA pin state, the receiver may hear nothing\n");

	gdev = gnss_allocate_device(dev);
	if (!gdev)
		return -ENOMEM;
	gdev->type = GNSS_TYPE_MTK;
	gdev->ops = &mtk_gnss_ops;
	gnss_set_drvdata(gdev, g);
	g->gdev = gdev;
	platform_set_drvdata(pdev, g);
	mtk_gnss_dev = g;

	ret = gnss_register_device(gdev);
	if (ret) {
		mtk_gnss_dev = NULL;
		gnss_put_device(gdev);
	}
	return ret;
}

static void mtk_gnss_remove(struct platform_device *pdev)
{
	struct mtk_gnss *g = platform_get_drvdata(pdev);

	gnss_deregister_device(g->gdev);
	gnss_put_device(g->gdev);
	mtk_gnss_dev = NULL;
}

static const struct of_device_id mtk_gnss_of_match[] = {
	{ .compatible = "mediatek,mt6789-gnss" },
	{ }
};
MODULE_DEVICE_TABLE(of, mtk_gnss_of_match);

static struct platform_driver mtk_gnss_driver = {
	.probe = mtk_gnss_probe,
	.remove = mtk_gnss_remove,
	.driver = {
		.name = DRV_NAME,
		.of_match_table = mtk_gnss_of_match,
	},
};

static struct platform_device *mtk_gnss_pdev;

/*
 * Interim: wmt_drv does not populate the CONNSYS node's children, so create
 * the device here; without a DT node it runs without LNA control.
 */
static int __init mtk_gnss_init(void)
{
	struct device_node *np;
	int ret;

	ret = platform_driver_register(&mtk_gnss_driver);
	if (ret)
		return ret;
	np = of_find_compatible_node(NULL, NULL, "mediatek,mt6789-gnss");
	if (np)
		mtk_gnss_pdev = of_platform_device_create(np, NULL, NULL);
	else
		mtk_gnss_pdev = platform_device_register_simple(DRV_NAME, PLATFORM_DEVID_NONE,
								NULL, 0);
	of_node_put(np);
	if (IS_ERR_OR_NULL(mtk_gnss_pdev)) {
		platform_driver_unregister(&mtk_gnss_driver);
		return mtk_gnss_pdev ? PTR_ERR(mtk_gnss_pdev) : -ENODEV;
	}
	return 0;
}
module_init(mtk_gnss_init);

static void __exit mtk_gnss_exit(void)
{
	platform_device_unregister(mtk_gnss_pdev);
	platform_driver_unregister(&mtk_gnss_driver);
}
module_exit(mtk_gnss_exit);

MODULE_FIRMWARE(MT6789_GNSS_FW);
MODULE_DESCRIPTION("MediaTek MT6789 CONNSYS GNSS");
MODULE_LICENSE("GPL");
