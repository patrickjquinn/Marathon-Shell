#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Offline stock-profile SOC candidate. No device, D-Bus or hardware access.

Input uncertainty is an explicit reviewed policy, not invented calibration.
Outputs remain ESTIMATED; this program cannot authorize shutdown or seed100%
from charger Full. Fraction arithmetic preserves CAR sub-uAh resolution.
"""
import argparse
import json
from fractions import Fraction as F
from pathlib import Path

TABLES = sorted(json.loads(Path(__file__).with_name("stock-profile0.json").read_text())["tables"],
                key=lambda t: t["temperature_mC"])
SHUNT_UOHM = 1000
TUNE_PERMILLE = 1010
# Vendor drops11fraction bits in coulomb_get(), but threshold programming
# uses all32register bits. Full-bit interpretation is a review hypothesis
# until longer runtime current/CAR comparison validates it.
NAH_PER_FULL_COUNT = F(108507 * 10 * TUNE_PERMILLE, 2048 * 1000)
NTC = [(-40, 195652), (-35, 148171), (-30, 113347), (-25, 87559),
       (-20, 68237), (-15, 53650), (-10, 42506), (-5, 33892), (0, 27219),
       (5, 22021), (10, 17926), (15, 14674), (20, 12081), (25, 10000),
       (30, 8315), (35, 6948), (40, 5834), (45, 4917), (50, 4161),
       (55, 3535), (60, 3014)]


class InvalidMeasurement(ValueError):
    pass


def lerp(x, x0, y0, x1, y1):
    if x0 == x1:
        return F(y0)
    return F(y0) + F(x - x0, x1 - x0) * (y1 - y0)


def ntc_temperature_mc(voltage_uv, current_ua, *, bif_uv=None):
    """Vendor10kNTC/24k pullup, stock2.8V fallback, explicit IR compensation.

    mtk_battery_table.h:450..490, mtk_battery.c:volttotemp and
    force_get_tbat_internal; base COM_R_FG_VALUE0/COM_FG_METER_RESISTANCE100.
    These are source-backed circuit assumptions, not precision calibration.
    Supply voltage/BIF error must be included in caller temperature bounds.
    """
    correction_uv = F(current_ua * 100, 10000)  #100*0.1mOhm=10mOhm
    node_uv = F(voltage_uv) - correction_uv
    pull_uv = F(2800000) if bif_uv is None else F(bif_uv) - correction_uv
    if not 0 < node_uv < pull_uv:
        raise InvalidMeasurement("NTC open/short or invalid reference")
    resistance = 24000 * node_uv / (pull_uv - node_uv)
    for (t0, r0), (t1, r1) in zip(NTC, NTC[1:]):
        if r1 <= resistance <= r0:
            return lerp(resistance, r0, t0 * 1000, r1, t1 * 1000)
    raise InvalidMeasurement("NTC outside source table; no clamp")


def profile(temp_mc):
    if not TABLES[0]["temperature_mC"] <= temp_mc <= TABLES[-1]["temperature_mC"]:
        raise InvalidMeasurement("temperature outside measured stock profile grid")
    for low, high in zip(TABLES, TABLES[1:]):
        a, b = low["temperature_mC"], high["temperature_mC"]
        if a <= temp_mc <= b:
            rows = [[lerp(temp_mc, a, x, b, y) for x, y in zip(r0, r1)]
                    for r0, r1 in zip(low["rows"], high["rows"])]
            qmax = lerp(temp_mc, a, low["qmax_uah"], b, high["qmax_uah"])
            return rows, qmax
    raise InvalidMeasurement("no temperature bracket")


def lookup(voltage_uv, current_ua, temp_mc):
    """Invert the stock loaded curve, retaining every crossing if ambiguous.

    Voltage0.1mV=>100uV; resistance0.1mOhm; mah0.1mAh=>100uAh.
    The extra8mOhm is stock R_FG_VALUE1 + FG_METER_RESISTANCE7mOhm.
    Charge uses4th-column resistance; discharge uses3rd; DC_ratio100.
    This is a reviewed subset, not the vendor aging/hysteresis algorithm.
    """
    rows, qmax = profile(temp_mc)
    loaded = [(r[0] * 100,
               r[1] * 100 + F(current_ua * (r[3 if current_ua >= 0 else 2] + 80), 10000))
              for r in rows]
    discharged = []
    for (q0, v0), (q1, v1) in zip(loaded, loaded[1:]):
        if min(v0, v1) <= voltage_uv <= max(v0, v1):
            if v0 == v1:
                discharged.extend([q0, q1])
            else:
                discharged.append(lerp(voltage_uv, v0, q0, v1, q1))
    if not discharged:
        # No arbitrary linear extrapolation or high/low-voltage clamp.
        raise InvalidMeasurement("voltage outside stock loaded curve")
    soc = [max(F(0), min(F(10000), (qmax - q) * 10000 / qmax)) for q in discharged]
    return min(soc), max(soc), qmax


def estimate(sample, policy):
    """Source candidate; input bounds are mandatory and exported with result.

    The interval spans profile temperatures/knots and voltage/current corners.
    It is a sensitivity envelope, NOT a statistical confidence interval or a
    bound on unmodelled aging/hysteresis/calibration errors.
    """
    for name in ("voltage_uv", "current_ua", "temperature_lo_mc", "temperature_hi_mc",
                 "age_ms", "skew_ms"):
        if type(sample.get(name)) is not int:
            raise InvalidMeasurement("missing/invalid " + name)
    for name in ("voltage_error_uv", "current_error_ua", "max_age_ms", "max_skew_ms",
                 "seed_current_limit_ua", "model_margin_bp", "max_width_bp"):
        if type(policy.get(name)) is not int or policy[name] < 0:
            raise InvalidMeasurement("missing/invalid policy " + name)
    if not (0 <= sample["age_ms"] <= policy["max_age_ms"] and
            0 <= sample["skew_ms"] <= policy["max_skew_ms"]):
        raise InvalidMeasurement("stale or skewed sample")
    if abs(sample["current_ua"]) + policy["current_error_ua"] >= policy["seed_current_limit_ua"]:
        raise InvalidMeasurement("initial seed requires qualified low battery current")
    lo, hi = sample["temperature_lo_mc"], sample["temperature_hi_mc"]
    if lo > hi:
        raise InvalidMeasurement("reversed temperature interval")
    profile(lo)
    profile(hi)
    temperatures = {lo, hi} | {t["temperature_mC"] for t in TABLES if lo < t["temperature_mC"] < hi}
    answers, capacities = [], []
    for temp in temperatures:
        for voltage in {sample["voltage_uv"] - policy["voltage_error_uv"],
                        sample["voltage_uv"] + policy["voltage_error_uv"]}:
            for current in {sample["current_ua"] - policy["current_error_ua"],
                            sample["current_ua"] + policy["current_error_ua"]}:
                a, b, q = lookup(voltage, current, temp)
                answers.extend([a, b])
                capacities.append(q)
    lower = max(F(0), min(answers) - policy["model_margin_bp"])
    upper = min(F(10000), max(answers) + policy["model_margin_bp"])
    if upper - lower > policy["max_width_bp"]:
        raise InvalidMeasurement("model sensitivity too wide for a point estimate")
    return {"estimated": True, "basis": "exact-stock-profile0-temperature-and-IR",
            "percentage": float((lower + upper) / 200),
            "percentage_low": float(lower / 100), "percentage_high": float(upper / 100),
            "qmax_low_uah": float(min(capacities)), "qmax_high_uah": float(max(capacities)),
            "temperature_interval_mc": [lo, hi], "critical_actions_allowed": False,
            "charger_full_is_nominal_full": False, "input": sample, "policy": policy}


def full_car_counts(car0, car1):
    if not (0 <= car0 <= 65535 and 0 <= car1 <= 65535):
        raise InvalidMeasurement("invalid CAR register word")
    word = car1 * 65536 + car0
    return word - 0xffffffff if word & 0x80000000 else word


class CounterTrack:
    """No persisted anchor, reset or guessed overflow unwrap. Fractional deltas.

    A caller must establish counter encoding/current agreement before trusting
    this candidate. A missed reset can be indistinguishable from a small delta;
    battery continuity/reset indication remains an integration requirement.
    """
    def __init__(self, seed, car0, car1, time_ms):
        if not seed.get("estimated"):
            raise InvalidMeasurement("missing qualified model seed")
        self.seed = seed
        self.origin = full_car_counts(car0, car1)
        self.previous = self.origin
        self.last_ms = time_ms
        self.valid = True

    def update(self, car0, car1, time_ms, *, max_gap_ms, max_abs_current_ua,
               charge_error_uah=0, continuity_verified=False):
        if not self.valid:
            raise InvalidMeasurement("anchor invalidated")
        new = full_car_counts(car0, car1)
        dt = time_ms - self.last_ms
        delta = new - self.previous
        dq_nah = delta * NAH_PER_FULL_COUNT
        limit_nah = F(max_abs_current_ua * max(dt, 0), 3600) + abs(NAH_PER_FULL_COUNT) * 2
        if (not continuity_verified or not 0 < dt <= max_gap_ms or
                abs(delta) > 0x7fffffff or abs(dq_nah) > limit_nah):
            self.valid = False
            raise InvalidMeasurement("gap/reset/rollover/current-bound discontinuity")
        # Difference from a fixed baseline avoids accumulating per-sample rounding.
        total_uah = (new - self.origin) * NAH_PER_FULL_COUNT / 1000
        if total_uah >= 0:
            low_shift = (total_uah - charge_error_uah) * 100 / F(self.seed["qmax_high_uah"])
            high_shift = (total_uah + charge_error_uah) * 100 / F(self.seed["qmax_low_uah"])
        else:
            low_shift = (total_uah - charge_error_uah) * 100 / F(self.seed["qmax_low_uah"])
            high_shift = (total_uah + charge_error_uah) * 100 / F(self.seed["qmax_high_uah"])
        low = max(0, min(100, self.seed["percentage_low"] + float(low_shift)))
        high = max(0, min(100, self.seed["percentage_high"] + float(high_shift)))
        self.previous, self.last_ms = new, time_ms
        return {"estimated": True, "percentage": (low + high) / 2,
                "percentage_low": low, "percentage_high": high,
                "delta_uah": float(total_uah), "critical_actions_allowed": False}


def termination_qualifies(samples, *, dwell_ms, max_gap_ms, cv_error_uv, term_error_ua):
    """Qualifies only the configured charge ceiling, never nominal100%.

    Tolerances/dwell are explicit review policy; no built-in calibration claim.
    Full/USB/CV/term must remain stable and all simultaneous current/V samples
    qualify over the dwell. Two instantaneous low-current reads are insufficient
    unless their time span actually meets the reviewed dwell.
    """
    if len(samples) < 2 or dwell_ms <= 0 or max_gap_ms <= 0 or cv_error_uv < 0 or term_error_ua < 0:
        return False
    first = samples[0]
    for i, s in enumerate(samples):
        if (s["status"] != "Full" or not s["online"] or s["cv_uv"] != first["cv_uv"] or
                s["term_ua"] != first["term_ua"] or s["term_ua"] <= term_error_ua or
                abs(s["current_ua"]) + term_error_ua >= s["term_ua"] or
                abs(s["voltage_uv"] - s["cv_uv"]) > cv_error_uv or
                not s.get("fresh", False)):
            return False
        if i and not 0 < s["time_ms"] - samples[i - 1]["time_ms"] <= max_gap_ms:
            return False
    return samples[-1]["time_ms"] - first["time_ms"] >= dwell_ms


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path, help="regular JSON file: sample and reviewed policy")
    args = parser.parse_args()
    payload = json.loads(args.input.read_text())
    try:
        result = estimate(payload["sample"], payload["policy"])
    except InvalidMeasurement as error:
        result = {"estimated": False, "percentage": None,
                  "critical_actions_allowed": False, "reason": str(error)}
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
