// SPDX-License-Identifier: GPL-2.0-only
/*
 * Native BlueZ HCI driver for the MT6789 CONNSYS Bluetooth function on the
 * Zinwa Q25, carried over WMT/STP/BTIF. It replaces the Android stp_chrdev_bt
 * (/dev/stpbt) plus a userspace H4 relay: the same STP calls as the stock
 * driver (func_on/off, BT_TASK_INDX send/receive, reset message callback),
 * but packets go straight to hci_core.
 *
 * STP BT payloads are H4 (packet-type byte + HCI packet). RX is drained from
 * the STP queue in process context and reassembled defensively.
 */
#include <linux/module.h>
#include <linux/skbuff.h>
#include <linux/workqueue.h>
#include <linux/mutex.h>
#include <linux/unaligned.h>
#include <net/bluetooth/bluetooth.h>
#include <net/bluetooth/hci_core.h>

#include "osal_typedef.h"
#include "wmt_exp.h"
#include "stp_exp.h"

#define Q25_BT_RX_CHUNK		2048
#define HCI_OP_MTK_SET_BD_ADDR	0xfc1a
/* page 2 byte 0 bit 2: Synchronization Train, advertised but not implemented */
#define Q25_LMP_SYNC_TRAIN	0x04

struct q25_bt {
	struct hci_dev *hdev;
	struct work_struct rx_work;
	struct mutex lock;		/* open/close/reset */
	bool powered;
	u8 rx_chunk[Q25_BT_RX_CHUNK];
	struct sk_buff *rx_skb;		/* packet under reassembly */
	unsigned int rx_need;		/* bytes still expected for rx_skb */
	bool rx_in_header;
};

static struct q25_bt *q25bt;

static void q25_bt_rx_reset(struct q25_bt *bt)
{
	kfree_skb(bt->rx_skb);
	bt->rx_skb = NULL;
	bt->rx_need = 0;
	bt->rx_in_header = false;
}

/* Same fix-up lagos-wmt applies on MT6768: hide Sync Train so init completes. */
static void q25_bt_fixup_event(struct sk_buff *skb)
{
	u8 *d = skb->data;

	/* evt 0x0e plen ncmd op_lo op_hi status page max_page features[8] */
	if (skb->len >= 9 && d[0] == HCI_EV_CMD_COMPLETE &&
	    get_unaligned_le16(d + 3) == HCI_OP_READ_LOCAL_EXT_FEATURES &&
	    d[5] == 0 && d[6] == 2)
		d[8] &= ~Q25_LMP_SYNC_TRAIN;
}

static unsigned int q25_bt_header_len(u8 type)
{
	switch (type) {
	case HCI_EVENT_PKT:	return HCI_EVENT_HDR_SIZE;
	case HCI_ACLDATA_PKT:	return HCI_ACL_HDR_SIZE;
	case HCI_SCODATA_PKT:	return HCI_SCO_HDR_SIZE;
	case HCI_ISODATA_PKT:	return HCI_ISO_HDR_SIZE;
	default:		return 0;
	}
}

static unsigned int q25_bt_payload_len(struct sk_buff *skb)
{
	switch (hci_skb_pkt_type(skb)) {
	case HCI_EVENT_PKT:
		return ((struct hci_event_hdr *)skb->data)->plen;
	case HCI_ACLDATA_PKT:
		return __le16_to_cpu(((struct hci_acl_hdr *)skb->data)->dlen);
	case HCI_SCODATA_PKT:
		return ((struct hci_sco_hdr *)skb->data)->dlen;
	case HCI_ISODATA_PKT:
		return hci_iso_data_len(__le16_to_cpu(((struct hci_iso_hdr *)skb->data)->dlen));
	}
	return 0;
}

static void q25_bt_feed(struct q25_bt *bt, const u8 *data, int len)
{
	while (len > 0) {
		unsigned int n;

		if (!bt->rx_skb) {
			unsigned int hlen = q25_bt_header_len(data[0]);

			if (!hlen) {
				bt_dev_err(bt->hdev, "unknown H4 type 0x%02x, dropping %d bytes",
					   data[0], len);
				bt->hdev->stat.err_rx++;
				return;
			}
			bt->rx_skb = bt_skb_alloc(HCI_MAX_FRAME_SIZE, GFP_KERNEL);
			if (!bt->rx_skb) {
				bt->hdev->stat.err_rx++;
				return;
			}
			hci_skb_pkt_type(bt->rx_skb) = data[0];
			bt->rx_need = hlen;
			bt->rx_in_header = true;
			data++;
			len--;
			continue;
		}

		n = min_t(unsigned int, len, bt->rx_need);
		if (skb_tailroom(bt->rx_skb) < n) {
			bt_dev_err(bt->hdev, "oversized packet, resyncing");
			q25_bt_rx_reset(bt);
			bt->hdev->stat.err_rx++;
			return;
		}
		skb_put_data(bt->rx_skb, data, n);
		data += n;
		len -= n;
		bt->rx_need -= n;
		if (bt->rx_need)
			continue;

		if (bt->rx_in_header) {
			bt->rx_in_header = false;
			bt->rx_need = q25_bt_payload_len(bt->rx_skb);
			if (bt->rx_need)
				continue;
		}

		if (hci_skb_pkt_type(bt->rx_skb) == HCI_EVENT_PKT)
			q25_bt_fixup_event(bt->rx_skb);
		bt->hdev->stat.byte_rx += bt->rx_skb->len;
		hci_recv_frame(bt->hdev, bt->rx_skb);
		bt->rx_skb = NULL;
	}
}

static void q25_bt_rx_work(struct work_struct *work)
{
	struct q25_bt *bt = container_of(work, struct q25_bt, rx_work);
	int n;

	while (READ_ONCE(bt->powered) &&
	       !mtk_wcn_stp_is_rxqueue_empty(BT_TASK_INDX)) {
		n = mtk_wcn_stp_receive_data(bt->rx_chunk, sizeof(bt->rx_chunk),
					     BT_TASK_INDX);
		if (n <= 0)
			break;
		q25_bt_feed(bt, bt->rx_chunk, n);
	}
}

/* STP event callback: may run in the BTIF rx context, defer the drain. */
static void q25_bt_stp_event(void)
{
	if (q25bt && READ_ONCE(q25bt->powered))
		schedule_work(&q25bt->rx_work);
}

static void q25_bt_wmt_msg(ENUM_WMTDRV_TYPE_T src, ENUM_WMTDRV_TYPE_T dst,
			   ENUM_WMTMSG_TYPE_T type, PVOID buf, UINT32 sz)
{
	ENUM_WMTRSTMSG_TYPE_T msg = 0;

	if (src != WMTDRV_TYPE_WMT || dst != WMTDRV_TYPE_BT ||
	    type != WMTMSG_TYPE_RESET || !buf || sz > sizeof(msg))
		return;
	memcpy(&msg, buf, sz);
	if (msg == WMTRSTMSG_RESET_START) {
		bt_dev_warn(q25bt->hdev, "CONNSYS whole-chip reset started");
	} else if (msg == WMTRSTMSG_RESET_END || msg == WMTRSTMSG_RESET_END_FAIL) {
		bt_dev_warn(q25bt->hdev, "CONNSYS whole-chip reset %s",
			    msg == WMTRSTMSG_RESET_END ? "done" : "FAILED");
		/* Firmware state is gone: have hci_core re-initialise. */
		hci_reset_dev(q25bt->hdev);
	}
}

static int q25_bt_open(struct hci_dev *hdev)
{
	struct q25_bt *bt = hci_get_drvdata(hdev);
	int ret = 0;

	mutex_lock(&bt->lock);
	if (bt->powered)
		goto out;

	if (mtk_wcn_wmt_func_on(WMTDRV_TYPE_BT) == MTK_WCN_BOOL_FALSE) {
		bt_dev_err(hdev, "WMT BT power on failed");
		ret = -EIO;
		goto out;
	}
	if (mtk_wcn_stp_is_ready() == MTK_WCN_BOOL_FALSE) {
		bt_dev_err(hdev, "STP not ready");
		mtk_wcn_wmt_func_off(WMTDRV_TYPE_BT);
		ret = -EIO;
		goto out;
	}
	/* Queue mode (as the stock chrdev), drained by rx_work. */
	mtk_wcn_stp_set_bluez(0);
	q25_bt_rx_reset(bt);
	WRITE_ONCE(bt->powered, true);
	mtk_wcn_stp_register_event_cb(BT_TASK_INDX, q25_bt_stp_event);
	mtk_wcn_wmt_msgcb_reg(WMTDRV_TYPE_BT, q25_bt_wmt_msg);
	/* Anything the firmware sent during power-on. */
	schedule_work(&bt->rx_work);
	bt_dev_info(hdev, "CONNSYS BT on");
out:
	mutex_unlock(&bt->lock);
	return ret;
}

static int q25_bt_close(struct hci_dev *hdev)
{
	struct q25_bt *bt = hci_get_drvdata(hdev);

	mutex_lock(&bt->lock);
	if (!bt->powered)
		goto out;

	WRITE_ONCE(bt->powered, false);
	mtk_wcn_wmt_msgcb_unreg(WMTDRV_TYPE_BT);
	mtk_wcn_stp_register_event_cb(BT_TASK_INDX, NULL);
	cancel_work_sync(&bt->rx_work);
	q25_bt_rx_reset(bt);
	if (mtk_wcn_wmt_func_off(WMTDRV_TYPE_BT) == MTK_WCN_BOOL_FALSE)
		bt_dev_err(hdev, "WMT BT power off failed");
	else
		bt_dev_info(hdev, "CONNSYS BT off");
out:
	mutex_unlock(&bt->lock);
	return 0;
}

static int q25_bt_flush(struct hci_dev *hdev)
{
	return 0;
}

static int q25_bt_send(struct hci_dev *hdev, struct sk_buff *skb)
{
	struct q25_bt *bt = hci_get_drvdata(hdev);
	int ret;

	if (!READ_ONCE(bt->powered)) {
		kfree_skb(skb);
		return -ENETDOWN;
	}

	switch (hci_skb_pkt_type(skb)) {
	case HCI_COMMAND_PKT:
		hdev->stat.cmd_tx++;
		break;
	case HCI_ACLDATA_PKT:
		hdev->stat.acl_tx++;
		break;
	case HCI_SCODATA_PKT:
		hdev->stat.sco_tx++;
		break;
	}

	memcpy(skb_push(skb, 1), &hci_skb_pkt_type(skb), 1);
	ret = mtk_wcn_stp_send_data(skb->data, skb->len, BT_TASK_INDX);
	if (ret != skb->len) {
		bt_dev_err(hdev, "STP send %u bytes returned %d", skb->len, ret);
		hdev->stat.err_tx++;
		kfree_skb(skb);
		return -EIO;
	}
	hdev->stat.byte_tx += skb->len;
	kfree_skb(skb);
	return 0;
}

static int q25_bt_set_bdaddr(struct hci_dev *hdev, const bdaddr_t *bdaddr)
{
	struct sk_buff *skb;

	skb = __hci_cmd_sync(hdev, HCI_OP_MTK_SET_BD_ADDR, sizeof(*bdaddr),
			     bdaddr, HCI_INIT_TIMEOUT);
	if (IS_ERR(skb))
		return PTR_ERR(skb);
	kfree_skb(skb);
	return 0;
}

static int __init q25_bt_init(void)
{
	struct hci_dev *hdev;
	int ret;

	q25bt = kzalloc(sizeof(*q25bt), GFP_KERNEL);
	if (!q25bt)
		return -ENOMEM;
	mutex_init(&q25bt->lock);
	INIT_WORK(&q25bt->rx_work, q25_bt_rx_work);

	hdev = hci_alloc_dev();
	if (!hdev) {
		ret = -ENOMEM;
		goto err_free;
	}
	q25bt->hdev = hdev;
	hci_set_drvdata(hdev, q25bt);
	hdev->bus = HCI_UART;	/* BTIF is the SoC UART-style BT interface */
	hdev->open = q25_bt_open;
	hdev->close = q25_bt_close;
	hdev->flush = q25_bt_flush;
	hdev->send = q25_bt_send;
	hdev->set_bdaddr = q25_bt_set_bdaddr;
	/*
	 * The controller reports a placeholder address and close() powers the
	 * BT core off, so stay unconfigured until userspace sets an address
	 * and program it again on every power-on.
	 */
	hci_set_quirk(hdev, HCI_QUIRK_INVALID_BDADDR);
	hci_set_quirk(hdev, HCI_QUIRK_NON_PERSISTENT_SETUP);

	ret = hci_register_dev(hdev);
	if (ret < 0)
		goto err_hdev;

	pr_info("q25-btmtk-stp: registered %s (CONNSYS BT over WMT/STP)\n", hdev->name);
	return 0;

err_hdev:
	hci_free_dev(hdev);
err_free:
	kfree(q25bt);
	q25bt = NULL;
	return ret;
}
module_init(q25_bt_init);

static void __exit q25_bt_exit(void)
{
	hci_unregister_dev(q25bt->hdev);
	hci_free_dev(q25bt->hdev);
	kfree(q25bt);
}
module_exit(q25_bt_exit);

MODULE_DESCRIPTION("Zinwa Q25 MT6789 CONNSYS Bluetooth over WMT/STP (BlueZ)");
MODULE_LICENSE("GPL");
