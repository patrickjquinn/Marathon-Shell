// SPDX-License-Identifier: GPL-2.0-only
/* Explicit snapshot input; cached native extension on existing fuel-gauge. */
#include <linux/device.h>
#include <linux/jiffies.h>
#include <linux/ktime.h>
#include <linux/mfd/mt6397/core.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/power_supply.h>
#include <linux/regmap.h>
#include <linux/slab.h>
#include <linux/workqueue.h>
#include "q25-live-cache.h"
#define Q25_NAME "q25-mt6358-live"
static bool enable_snapshot;
module_param(enable_snapshot, bool, 0444);
static unsigned int max_samples;
module_param(max_samples, uint, 0644);
MODULE_PARM_DESC(max_samples, "Optional snapshot cap;0 unlimited explicit root reads");
static char *parent_name;
module_param(parent_name, charp, 0444);
static struct platform_device *q25_child;
static struct device *q25_parent;
static int q25_read(void *ctx, unsigned int reg, unsigned int *val)
{
	return regmap_read(ctx, reg, val);
}

static int q25_update(void *ctx, unsigned int reg, unsigned int mask,
		      unsigned int val)
{
	/* Fail closed if later code tries to extend the write surface. */
	if (reg != Q25_FG_CON1 || (mask & ~(Q25_FG_READ | Q25_FG_CLEAR)) ||
	    (val & ~mask))
		return -EPERM;
	return regmap_update_bits(ctx, reg, mask, val);
}

static int q25_poll(void *ctx, bool latched)
{
	unsigned int val;

	return regmap_read_poll_timeout(ctx, Q25_FG_CON1, val,
				       !!(val & Q25_FG_LATCH) == latched,
				       50, 20000);
}

/* SPDX-License-Identifier: GPL-2.0-only */
struct q25_live {
	struct mutex lock;
	struct mutex control;
	struct q25_fg_io io;
	struct q25_live_cache cache;
	struct delayed_work expiry;
	struct power_supply *psy;
	struct q25_fg_raw raw;
	u64 sample_ns;
	unsigned int sequence, errors;
	int last_error;
	bool stopped, soc_registered;
};

static const enum power_supply_property measurement_props[] = {
	POWER_SUPPLY_PROP_CURRENT_NOW, POWER_SUPPLY_PROP_CHARGE_COUNTER,
	POWER_SUPPLY_PROP_TEMP,
};
static const enum power_supply_property soc_props[] = {
	POWER_SUPPLY_PROP_CAPACITY, POWER_SUPPLY_PROP_CAPACITY_ERROR_MARGIN,
};

static int cached_get(struct power_supply *psy, const struct power_supply_ext *ext,
		      void *data, enum power_supply_property prop,
		      union power_supply_propval *val)
{
	struct q25_live *fg = data;
	enum q25_cached_property field;
	int ret;

	switch (prop) {
	case POWER_SUPPLY_PROP_CURRENT_NOW: field = Q25_CURRENT; break;
	case POWER_SUPPLY_PROP_CHARGE_COUNTER: field = Q25_CAR; break;
	case POWER_SUPPLY_PROP_TEMP: field = Q25_TEMP; break;
	case POWER_SUPPLY_PROP_CAPACITY: field = Q25_CAPACITY; break;
	case POWER_SUPPLY_PROP_CAPACITY_ERROR_MARGIN: field = Q25_MARGIN; break;
	default: return -EINVAL;
	}
	mutex_lock(&fg->lock);
	ret = q25_cache_get(&fg->cache, ktime_get_boottime_ns(), field, &val->intval);
	mutex_unlock(&fg->lock);
	return ret;
}
static const struct power_supply_ext measurement_ext = {
	.name = "q25-stock-measurements", .properties = measurement_props,
	.num_properties = ARRAY_SIZE(measurement_props), .get_property = cached_get,
};
static const struct power_supply_ext soc_ext = {
	.name = "q25-stock-gauge", .properties = soc_props,
	.num_properties = ARRAY_SIZE(soc_props), .get_property = cached_get,
};

/* control mutex serializes extension registration, expiry and commit.
 * Never hold cache lock across core calls which may call cached_get().
 */
static void invalidate(struct q25_live *fg)
{
	mutex_lock(&fg->lock);
	fg->cache.valid = false;
	fg->cache.capacity_bp = -1;
	mutex_unlock(&fg->lock);
	if (fg->soc_registered) {
		power_supply_unregister_extension(fg->psy, &soc_ext);
		fg->soc_registered = false;
	}
	power_supply_changed(fg->psy);
}

static void expiry_work(struct work_struct *work)
{
	struct q25_live *fg = container_of(to_delayed_work(work), struct q25_live, expiry);
	bool expired, stopped;

	mutex_lock(&fg->control);
	mutex_lock(&fg->lock);
	expired = fg->cache.valid && !q25_cache_fresh(&fg->cache, ktime_get_boottime_ns());
	stopped = fg->stopped;
	mutex_unlock(&fg->lock);
	if (expired)
		invalidate(fg);
	if (!stopped)
		schedule_delayed_work(&fg->expiry, HZ);
	mutex_unlock(&fg->control);
}

static ssize_t snapshot_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	struct q25_live *fg = dev_get_drvdata(dev);
	struct q25_fg_raw raw;
	u32 full_raw;
	s64 counts;
	int ret, ua, car, coarse;

	mutex_lock(&fg->control);
	mutex_lock(&fg->lock);
	if (fg->stopped || (READ_ONCE(max_samples) && fg->sequence >= READ_ONCE(max_samples))) {
		ret = -ESHUTDOWN;
		goto unlock;
	}
	fg->sequence++;
	ret = q25_fg_snapshot(&fg->io, &raw);
	if (!ret)
		ret = q25_fg_decode(&raw, &ua, &car, &coarse);
	if (ret) {
		fg->errors++;
		fg->last_error = ret;
		fg->sample_ns = 0;
		goto unlock;
	}
	fg->raw = raw;
	fg->sample_ns = ktime_get_boottime_ns();
	full_raw = (raw.car1 << 16) | raw.car0;
	counts = full_raw & BIT(31) ? (s64)full_raw - 0xffffffffLL : full_raw;
	fg->last_error = 0;
	ret = sysfs_emit(buf,
		"sequence=%u mono_ns=%llu current_ua=%d car0=%04x car1=%04x full_counts=%lld\n",
		fg->sequence, fg->sample_ns, ua, raw.car0, raw.car1, counts);
unlock:
	if (ret < 0)
		fg->sample_ns = 0;
	mutex_unlock(&fg->lock);
	if (ret < 0)
		invalidate(fg);
	mutex_unlock(&fg->control);
	return ret;
}
static DEVICE_ATTR(snapshot, 0400, snapshot_show, NULL);

/* Wire: sequence sample_boottime_ns temperature_deciC capacity_basis_points
 * margin_basis_points. Current/CAR are ALWAYS taken from that kernel sample.
 */
static ssize_t commit_store(struct device *dev, struct device_attribute *attr,
			    const char *buf, size_t count)
{
	struct q25_live *fg = dev_get_drvdata(dev);
	unsigned long long stamp;
	unsigned int seq;
	int temp, cap, margin, ua, car, coarse, ret;
	s64 full_counts;
	char extra;

	if (sscanf(buf, "%u %llu %d %d %d %c", &seq, &stamp, &temp, &cap, &margin, &extra) != 5)
		return -EINVAL;
	mutex_lock(&fg->control);
	mutex_lock(&fg->lock);
	if (fg->stopped || !fg->sample_ns || seq != fg->sequence || stamp != fg->sample_ns) {
		ret = -ESTALE;
		goto unlock;
	}
	ret = q25_fg_decode(&fg->raw, &ua, &car, &coarse);
	if (ret)
		goto unlock;
	full_counts = ((u32)fg->raw.car1 << 16) | fg->raw.car0;
	if (full_counts & BIT_ULL(31))
		full_counts -= 0xffffffffLL;
	car = div_s64(full_counts * 1095920700LL, 2048000000);
	ret = q25_cache_commit(&fg->cache, ktime_get_boottime_ns(), stamp,
			      ua, car, temp, cap, margin);
unlock:
	mutex_unlock(&fg->lock);
	if (ret)
		invalidate(fg);
	else if (cap >= 0 && !fg->soc_registered) {
		ret = power_supply_register_extension(fg->psy, &soc_ext, dev, fg);
		if (!ret)
			fg->soc_registered = true;
		else
			invalidate(fg);
	} else if (cap < 0 && fg->soc_registered) {
		power_supply_unregister_extension(fg->psy, &soc_ext);
		fg->soc_registered = false;
	}
	power_supply_changed(fg->psy);
	mutex_unlock(&fg->control);
	return ret ? ret : count;
}
static DEVICE_ATTR_WO(commit);

static ssize_t invalidate_store(struct device *dev, struct device_attribute *attr,
				const char *buf, size_t count)
{
	struct q25_live *fg = dev_get_drvdata(dev);

	mutex_lock(&fg->control);
	invalidate(fg);
	mutex_unlock(&fg->control);
	return count;
}
static DEVICE_ATTR_WO(invalidate);

static ssize_t stop_store(struct device *dev, struct device_attribute *attr,
			  const char *buf, size_t count)
{
	struct q25_live *fg = dev_get_drvdata(dev);

	mutex_lock(&fg->control);
	mutex_lock(&fg->lock);
	fg->stopped = true;
	mutex_unlock(&fg->lock);
	invalidate(fg);
	mutex_unlock(&fg->control);
	cancel_delayed_work_sync(&fg->expiry);
	return count;
}
static DEVICE_ATTR_WO(stop);

static ssize_t capacity_valid_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	struct q25_live *fg = dev_get_drvdata(dev);
	bool valid;

	mutex_lock(&fg->lock);
	valid = q25_cache_fresh(&fg->cache, ktime_get_boottime_ns()) && fg->cache.capacity_bp >= 0;
	mutex_unlock(&fg->lock);
	return sysfs_emit(buf, "%u\n", valid);
}
static DEVICE_ATTR_RO(capacity_valid);

static ssize_t estimated_capacity_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	return sysfs_emit(buf, "1\n");
}
static DEVICE_ATTR_RO(estimated_capacity);

static ssize_t diagnostics_show(struct device *dev, struct device_attribute *attr, char *buf)
{
	struct q25_live *fg = dev_get_drvdata(dev);
	int ret;

	mutex_lock(&fg->lock);
	ret = sysfs_emit(buf, "samples=%u errors=%u last_error=%d poisoned=%u stopped=%u ttl_ms=10000 estimated=1\n",
		fg->sequence, fg->errors, fg->last_error, fg->io.poisoned, fg->stopped);
	mutex_unlock(&fg->lock);
	return ret;
}
static DEVICE_ATTR_RO(diagnostics);
static struct attribute *live_attrs[] = {
	&dev_attr_snapshot.attr, &dev_attr_commit.attr, &dev_attr_invalidate.attr,
	&dev_attr_stop.attr, &dev_attr_capacity_valid.attr, &dev_attr_estimated_capacity.attr,
	&dev_attr_diagnostics.attr, NULL,
};
static const struct attribute_group live_group = { .attrs = live_attrs };

static void cleanup_live(void *data)
{
	struct q25_live *fg = data;

	mutex_lock(&fg->control);
	mutex_lock(&fg->lock);
	fg->stopped = true;
	fg->cache.valid = false;
	mutex_unlock(&fg->lock);
	mutex_unlock(&fg->control);
	cancel_delayed_work_sync(&fg->expiry);
	if (fg->soc_registered)
		power_supply_unregister_extension(fg->psy, &soc_ext);
	power_supply_unregister_extension(fg->psy, &measurement_ext);
	power_supply_put(fg->psy);
}

static int q25_probe(struct platform_device *pdev)
{
	struct device *parent = pdev->dev.parent;
	struct mt6397_chip *chip;
	struct q25_live *fg;
	int ret;

	if (!enable_snapshot || !parent || !parent->driver ||
	    strcmp(parent->driver->name, "mt6397") ||
	    !of_device_is_compatible(parent->of_node, "mediatek,mt6358"))
		return -ENODEV;
	chip = dev_get_drvdata(parent);
	if (!chip || !chip->regmap || (chip->chip_id != MT6358_CHIP_ID && chip->chip_id != MT6366_CHIP_ID))
		return -ENODEV;
	fg = devm_kzalloc(&pdev->dev, sizeof(*fg), GFP_KERNEL);
	if (!fg)
		return -ENOMEM;
	mutex_init(&fg->lock);
	mutex_init(&fg->control);
	fg->io = (struct q25_fg_io) { .ctx = chip->regmap, .read = q25_read,
		.update = q25_update, .poll = q25_poll };
	fg->cache.capacity_bp = -1;
	fg->psy = power_supply_get_by_name("fuel-gauge");
	if (!fg->psy)
		return -EPROBE_DEFER;
	ret = power_supply_register_extension(fg->psy, &measurement_ext, &pdev->dev, fg);
	if (ret) {
		power_supply_put(fg->psy);
		return ret;
	}
	INIT_DELAYED_WORK(&fg->expiry, expiry_work);
	ret = devm_add_action_or_reset(&pdev->dev, cleanup_live, fg);
	if (ret)
		return ret;
	platform_set_drvdata(pdev, fg);
	ret = devm_device_add_group(&pdev->dev, &live_group);
	if (ret) {
		platform_set_drvdata(pdev, NULL);
		return ret;
	}
	schedule_delayed_work(&fg->expiry, HZ);
	return 0;
}
static struct platform_driver q25_driver = {
	.probe = q25_probe,
	.driver.name = Q25_NAME,
};

static int __init q25_init(void)
{
	struct platform_device_info info = { .name = Q25_NAME,
		.id = PLATFORM_DEVID_NONE };
	int ret;

	if (!enable_snapshot || !parent_name || !*parent_name)
		return -EPERM;
	q25_parent = bus_find_device_by_name(&platform_bus_type, NULL, parent_name);
	if (!q25_parent)
		return -ENODEV;
	ret = platform_driver_register(&q25_driver);
	if (ret)
		goto put;
	info.parent = q25_parent;
	q25_child = platform_device_register_full(&info);
	if (IS_ERR(q25_child)) {
		ret = PTR_ERR(q25_child);
		goto unregister;
	}
	if (!platform_get_drvdata(q25_child)) {
		ret = -ENODEV;
		platform_device_unregister(q25_child);
		goto unregister;
	}
	return 0;
unregister:
	platform_driver_unregister(&q25_driver);
put:
	put_device(q25_parent);
	return ret;
}
module_init(q25_init);

static void __exit q25_exit(void)
{
	platform_device_unregister(q25_child);
	platform_driver_unregister(&q25_driver);
	put_device(q25_parent);
}
module_exit(q25_exit);

/* Intentionally no MODULE_DEVICE_TABLE: no modalias autoload. */
MODULE_DESCRIPTION("Q25 cached power_supply extension and explicit MT6358 snapshots");
MODULE_AUTHOR("Q25 native gauge source review");
MODULE_LICENSE("GPL");
