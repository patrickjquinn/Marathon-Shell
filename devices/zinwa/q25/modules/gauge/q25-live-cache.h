/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef Q25_LIVE_CACHE_H
#define Q25_LIVE_CACHE_H
#include "q25-fg-core.h"
#ifndef __KERNEL__
typedef uint64_t u64;
#endif
#define Q25_CACHE_TTL_NS 10000000000ULL
enum q25_cached_property { Q25_CURRENT, Q25_CAR, Q25_TEMP, Q25_CAPACITY, Q25_MARGIN };
struct q25_live_cache {
	bool valid;
	u64 stamp_ns;
	int current_ua, car_uah, temp_dc, capacity_bp, margin_bp;
};
static inline bool q25_cache_fresh(const struct q25_live_cache *c, u64 now)
{
	return c->valid && c->stamp_ns && now >= c->stamp_ns &&
		now - c->stamp_ns <= Q25_CACHE_TTL_NS;
}
static inline int q25_cache_commit(struct q25_live_cache *c, u64 now, u64 stamp,
				   int ua, int car, int temp, int cap, int margin)
{
	if (!stamp || now < stamp || now - stamp > Q25_CACHE_TTL_NS ||
	    temp < -400 || temp > 600 || cap < -1 || cap > 10000 ||
	    margin < 0 || margin > 10000)
		return -EINVAL;
	*c = (struct q25_live_cache) {
		.valid = true, .stamp_ns = stamp, .current_ua = ua,
		.car_uah = car, .temp_dc = temp, .capacity_bp = cap, .margin_bp = margin,
	};
	return 0;
}
static inline int q25_cache_get(const struct q25_live_cache *c, u64 now,
				enum q25_cached_property prop, int *value)
{
	if (!q25_cache_fresh(c, now))
		return -ENODATA;
	switch (prop) {
	case Q25_CURRENT: *value = c->current_ua; break;
	case Q25_CAR: *value = c->car_uah; break;
	case Q25_TEMP: *value = c->temp_dc; break;
	case Q25_CAPACITY:
		if (c->capacity_bp < 0)
			return -ENODATA;
		*value = (c->capacity_bp + 50) / 100;
		break;
	case Q25_MARGIN:
		if (c->capacity_bp < 0)
			return -ENODATA;
		/* Extra1% covers the exposed integer-capacity rounding. */
		*value = (c->margin_bp + 99) / 100 + 1;
		if (*value > 100)
			*value = 100;
		break;
	default: return -EINVAL;
	}
	return 0;
}
#endif
