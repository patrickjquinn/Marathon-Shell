// SPDX-License-Identifier: GPL-2.0
/*
 * Q25 camera DT overlay loader. The boot DTB has no SENINF/CAMSV nodes and
 * this kernel has no userspace overlay interface, so this applies
 * q25-camera.dtbo from the firmware path at runtime. Loaded at boot.
 */
#include <linux/debugfs.h>
#include <linux/firmware.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/platform_device.h>

static bool enable;
module_param(enable, bool, 0444);
MODULE_PARM_DESC(enable, "apply the camera overlay (review gate)");

static DEFINE_MUTEX(q25_cam_dt_lock);
static struct platform_device *q25_cam_dt_pdev;
static int q25_cam_dt_ovcs = -1;

static int q25_cam_dt_apply(void)
{
	const struct firmware *fw;
	int ovcs = 0, ret;

	ret = request_firmware(&fw, "q25-camera.dtbo", &q25_cam_dt_pdev->dev);
	if (ret)
		return ret;
	ret = of_overlay_fdt_apply(fw->data, fw->size, &ovcs, NULL);
	release_firmware(fw);
	if (ret) {
		/* A failed apply may leave a changeset that must be removed. */
		if (ovcs > 0)
			of_overlay_remove(&ovcs);
		return ret;
	}
	q25_cam_dt_ovcs = ovcs;
	pr_info("q25-cam-dt: overlay applied, changeset %d\n", ovcs);
	return 0;
}

static int q25_cam_dt_get(void *data, u64 *val)
{
	*val = q25_cam_dt_ovcs > 0;
	return 0;
}

static int q25_cam_dt_set(void *data, u64 val)
{
	int ret = 0;

	mutex_lock(&q25_cam_dt_lock);
	if (val && q25_cam_dt_ovcs <= 0) {
		ret = q25_cam_dt_apply();
	} else if (!val && q25_cam_dt_ovcs > 0) {
		ret = of_overlay_remove(&q25_cam_dt_ovcs);
		if (!ret) {
			q25_cam_dt_ovcs = -1;
			pr_info("q25-cam-dt: overlay removed\n");
		}
	}
	mutex_unlock(&q25_cam_dt_lock);
	return ret;
}

DEFINE_DEBUGFS_ATTRIBUTE(q25_cam_dt_fops, q25_cam_dt_get, q25_cam_dt_set, "%llu\n");

static int __init q25_cam_dt_init(void)
{
	struct dentry *dir;
	int ret;

	if (!enable) {
		pr_info("q25-cam-dt: review gate: load with enable=1\n");
		return -EPERM;
	}
	q25_cam_dt_pdev = platform_device_register_simple("q25-cam-dt", PLATFORM_DEVID_NONE,
							  NULL, 0);
	if (IS_ERR(q25_cam_dt_pdev))
		return PTR_ERR(q25_cam_dt_pdev);
	mutex_lock(&q25_cam_dt_lock);
	ret = q25_cam_dt_apply();
	mutex_unlock(&q25_cam_dt_lock);
	if (ret) {
		pr_err("q25-cam-dt: overlay not applied: %d\n", ret);
		platform_device_unregister(q25_cam_dt_pdev);
		return ret;
	}
	dir = debugfs_create_dir("q25-cam-dt", NULL);
	debugfs_create_file_unsafe("applied", 0600, dir, NULL, &q25_cam_dt_fops);
	return 0;
}
module_init(q25_cam_dt_init);

MODULE_DESCRIPTION("Zinwa Q25 camera DT overlay loader");
MODULE_LICENSE("GPL");
