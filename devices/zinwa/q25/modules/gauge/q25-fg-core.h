/* SPDX-License-Identifier: GPL-2.0-only */
/* MT6358 snapshot protocol and vendor signed conversions; host-testable. */
#ifndef Q25_FG_CORE_H
#define Q25_FG_CORE_H

#ifdef __KERNEL__
#include <linux/errno.h>
#include <linux/math64.h>
#include <linux/types.h>
#else
#include <stdbool.h>
#include <stdint.h>
#include <errno.h>
typedef int64_t s64;
#define div_s64(n, d) ((n) / (d))
#endif

/* Roman Vivchar e49b661b05d528dd0bd279885b16a7c9ef43adfa, register patch;
 * also vendor mt6358-gauge.c RG_FGADC_* and BM_TOP_CKPDN_CON0.
 */
#define Q25_FG_CLOCK 0xc0c
#define Q25_FG_CON0 0xd08
#define Q25_FG_CON1 0xd0a
#define Q25_FG_CAR0 0xd14
#define Q25_FG_CAR1 0xd16
#define Q25_FG_CURRENT 0xd8a
#define Q25_FG_LATCH 0x8000
#define Q25_FG_READ 0x0001
#define Q25_FG_CLEAR 0x0008
#define Q25_FG_RESET 0x1f00
#define Q25_FG_CAR_MAX 0xfffff
#define Q25_FG_SHUNT_UOHM 1000
#define Q25_FG_TUNE_PERMILLE 1010

struct q25_fg_raw {
	unsigned int current_value;
	unsigned int car0;
	unsigned int car1;
};

struct q25_fg_io {
	void *ctx;
	int (*read)(void *ctx, unsigned int reg, unsigned int *val);
	int (*update)(void *ctx, unsigned int reg, unsigned int mask,
		      unsigned int val);
	int (*poll)(void *ctx, bool latched);
	bool poisoned;
};

static inline int q25_fg_release(struct q25_fg_io *io)
{
	int ret, poll, clear;

	ret = io->update(io->ctx, Q25_FG_CON1,
			 Q25_FG_READ | Q25_FG_CLEAR, Q25_FG_CLEAR);
	poll = io->poll(io->ctx, false);
	clear = io->update(io->ctx, Q25_FG_CON1, Q25_FG_CLEAR, 0);
	if (ret || poll || clear) {
		io->poisoned = true;
		return ret ? ret : (poll ? poll : clear);
	}
	return 0;
}

/* No enabling, reset, threshold, RTC or calibration register writes. */
static inline int q25_fg_snapshot(struct q25_fg_io *io, struct q25_fg_raw *out)
{
	struct q25_fg_raw raw;
	unsigned int value;
	int ret, release;

	if (io->poisoned)
		return -EIO;
	ret = io->read(io->ctx, Q25_FG_CON0, &value);
	if (ret)
		return ret;
	if (!(value & 1))
		return -EHOSTDOWN;
	ret = io->read(io->ctx, Q25_FG_CLOCK, &value);
	if (ret)
		return ret;
	if (value & 0x18)
		return -EHOSTDOWN;
	ret = io->read(io->ctx, Q25_FG_CON1, &value);
	if (ret)
		return ret;
	if (value & (Q25_FG_RESET | Q25_FG_LATCH | Q25_FG_READ | Q25_FG_CLEAR))
		return -EBUSY;
	ret = io->update(io->ctx, Q25_FG_CON1,
			 Q25_FG_READ | Q25_FG_CLEAR, Q25_FG_READ);
	if (!ret)
		ret = io->poll(io->ctx, true);
	if (!ret)
		ret = io->read(io->ctx, Q25_FG_CURRENT, &raw.current_value);
	if (!ret)
		ret = io->read(io->ctx, Q25_FG_CAR0, &raw.car0);
	if (!ret)
		ret = io->read(io->ctx, Q25_FG_CAR1, &raw.car1);
	release = q25_fg_release(io);
	if (ret || release)
		return ret ? ret : release;
	if ((raw.current_value | raw.car0 | raw.car1) & ~0xffffU)
		return -EOVERFLOW;
	*out = raw;
	return 0;
}

/* Vendor reg_to_current(): one's complement, NOT an s16 cast. */
static inline int q25_fg_current_counts(unsigned int raw)
{
	return raw > 32767 ? (int)raw - 65535 : (int)raw;
}

/* Vendor coulomb_get(): 20 payload bits and separate sign, dual zero. */
static inline int q25_fg_car_counts(unsigned int low, unsigned int high)
{
	unsigned int raw = (low >> 11) | ((high & 0x7fff) << 5);

	if (!raw || raw == Q25_FG_CAR_MAX)
		return 0;
	return high & 0x8000 ? (int)raw - Q25_FG_CAR_MAX : (int)raw;
}

/* nA/nAh silicon units at10mOhm, calibrated for stock1mOhm /1.01.
 * Use one final division: no vendor sysfs rounding to0.1mA/0.1mAh.
 */
static inline s64 q25_fg_scaled(int counts, int nano_unit)
{
	return div_s64((s64)counts * nano_unit * 10 * Q25_FG_TUNE_PERMILLE,
		       1000000);
}

static inline int q25_fg_decode(const struct q25_fg_raw *raw, int *current_ua,
			       int *car_uah, int *counts)
{
	unsigned int payload;
	int count;

	if ((raw->current_value | raw->car0 | raw->car1) & ~0xffffU)
		return -EOVERFLOW;
	payload = (raw->car0 >> 11) | ((raw->car1 & 0x7fff) << 5);
	/* Vendor maps both extremes to0 irrespective of sign. Preserve the two
	 * normal zero encodings; reject ambiguous overflow endpoints.
	 */
	if ((!payload && (raw->car1 & 0x8000)) ||
	    (payload == Q25_FG_CAR_MAX && !(raw->car1 & 0x8000)))
		return -ERANGE;
	count = q25_fg_car_counts(raw->car0, raw->car1);
	*current_ua = q25_fg_scaled(q25_fg_current_counts(raw->current_value), 381470);
	*car_uah = q25_fg_scaled(count, 108507);
	*counts = count;
	return 0;
}

/* Diagnostic adjacent-snapshot delta only. A discontinuity is NOT unwrapped:
 * hardware reset versus overflow cannot be distinguished without more state.
 */
static inline int q25_fg_delta(int previous, int current_value, int *delta)
{
	int difference = current_value - previous;

	if (difference > Q25_FG_CAR_MAX || difference < -Q25_FG_CAR_MAX)
		return -ERANGE;
	*delta = difference;
	return 0;
}
#endif
