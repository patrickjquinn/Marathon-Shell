#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Native power_supply model producer, never writes charger/PMIC controls.

Only hardware-writing path is explicit read of the reviewed kernel snapshot
endpoint, plus ordinary existing IIO ADC conversions. Kernel callbacks are
cache-only. Root commit carries sample identity/temp/SOC/margin, not fake I/CAR.
"""
import argparse
import fcntl
import json
import math
import signal
import os
import sys
import statistics
import time
from fractions import Fraction as F
from pathlib import Path
# -I removes the script directory. Only import this explicitly verified bundle;
# never import a model through CWD/PYTHONPATH.
BUNDLE = Path(__file__).resolve().parent
for owned in [BUNDLE, BUNDLE / "q25_soc.py", BUNDLE / "stock-profile0.json"]:
    info = owned.stat()
    if info.st_uid != os.geteuid() or info.st_mode & 0o022:
        raise RuntimeError("producer bundle must be owned by effective uid and not group/world writable")
sys.path.insert(0, str(BUNDLE))
import q25_soc as model  # noqa: E402 - only after the bundle check above

ENDPOINT = Path("/sys/bus/platform/devices/q25-mt6358-live")
ADC_SUFFIX = "/soc/pmic-wrapper@10026000/pmic/adc"
STOP = False


def boottime_ns():
    return time.clock_gettime_ns(time.CLOCK_BOOTTIME)


def invalidate(endpoint):
    try:
        (endpoint / "invalidate").write_text("1\n")
    except OSError as error:
        print(json.dumps({"invalidate_error": str(error)}), flush=True)


def find_adc(root=Path("/sys/bus/iio/devices")):
    matches = []
    for device in root.glob("iio:device*"):
        node = device / "of_node"
        if not str(node.resolve()).endswith(ADC_SUFFIX):
            continue
        if b"mediatek,mt6358-auxadc" not in (node / "compatible").read_bytes().split(b"\0"):
            continue
        labels = {p.read_text().strip(): p.name[:-6] for p in device.glob("in_*_label")}
        if "bat_adc" in labels and "batt_temp" in labels:
            matches.append((device, labels))
    if len(matches) != 1:
        raise ValueError("need exactly one OF-verified MT6358 ADC with bat_adc/batt_temp")
    return matches[0]


def adc_uv(device, prefix):
    raw = int((device / (prefix + "_raw")).read_text())
    scale_mv = F((device / (prefix + "_scale")).read_text().strip())
    if raw < 0 or scale_mv <= 0:
        raise ValueError("invalid IIO raw/scale")
    return raw * scale_mv * 1000, scale_mv * 1000


def read_sample(endpoint, adc):
    start = boottime_ns()
    words = dict(item.split("=", 1) for item in (endpoint / "snapshot").read_text().split())
    gauge = {name: int(value, 16 if name in ["car0", "car1"] else 10)
             for name, value in words.items()}
    device, labels = adc
    voltage, voltage_lsb = adc_uv(device, labels["bat_adc"])
    ntc, ntc_lsb = adc_uv(device, labels["batt_temp"])
    end = boottime_ns()
    if not start <= gauge["mono_ns"] <= end or end - start > 250000000:
        raise ValueError("paired measurement skew exceeds250ms")
    temp = model.ntc_temperature_mc(ntc, gauge["current_ua"])
    return dict(gauge=gauge, voltage_uv=voltage, voltage_lsb_uv=voltage_lsb,
                ntc_uv=ntc, ntc_lsb_uv=ntc_lsb, temp_mc=temp,
                skew_ms=math.ceil((end - start) / 1000000))


def point_estimate(sample, margin_bp):
    g = sample["gauge"]
    current_error = 3853  #ceil(source current1LSB3852.847uA)
    ntc = sample["ntc_uv"]
    step = sample["ntc_lsb_uv"]
    temps = [model.ntc_temperature_mc(ntc + sign * step,
             g["current_ua"] + current_sign * current_error)
             for sign in [-1, 1] for current_sign in [-1, 1]]
    obs = dict(voltage_uv=int(sample["voltage_uv"]), current_ua=g["current_ua"],
               temperature_lo_mc=math.floor(min(temps)), temperature_hi_mc=math.ceil(max(temps)),
               age_ms=math.ceil((boottime_ns() - g["mono_ns"]) / 1000000),
               skew_ms=sample["skew_ms"])
    policy = dict(voltage_error_uv=math.ceil(sample["voltage_lsb_uv"]),
                  current_error_ua=current_error, seed_current_limit_ua=180000,
                  max_age_ms=3000, max_skew_ms=250, model_margin_bp=margin_bp,
                  max_width_bp=1500)
    estimate = model.estimate(obs, policy)
    a, b, _ = model.lookup(obs["voltage_uv"], obs["current_ua"], int(sample["temp_mc"]))
    estimate["percentage"] = float((a + b) / 200)
    return estimate


def validate_history(history, *, complete=False):
    if not history:
        raise model.InvalidMeasurement("empty seed history")
    if any(abs(row["gauge"]["current_ua"]) + 3853 > 50000 for row in history):
        raise model.InvalidMeasurement("seed current+quantization exceeds50mA")
    voltages = [row["voltage_uv"] for row in history]
    temps = [row["temp_mc"] for row in history]
    if max(voltages) - min(voltages) > 5000:
        raise model.InvalidMeasurement("seed voltage span exceeds5mV")
    if max(temps) - min(temps) > 1000:
        raise model.InvalidMeasurement("seed temperature span exceeds1C")
    for before, after in zip(history, history[1:]):
        if not 0 < after["gauge"]["mono_ns"] - before["gauge"]["mono_ns"] <= 1500000000:
            raise model.InvalidMeasurement("seed gap exceeds1.5s")
    if complete and (len(history) != 30 or history[-1]["gauge"]["mono_ns"] - history[0]["gauge"]["mono_ns"] < 25000000000):
        raise model.InvalidMeasurement("need30 stable samples spanning at least25s")


def make_tracker(history, margin_bp):
    validate_history(history, complete=True)
    estimates = [s["estimate"] for s in history]
    first = history[0]["gauge"]
    origin = model.full_car_counts(first["car0"], first["car1"])
    points, lows, highs = [], [], []
    for sample, estimate in zip(history, estimates):
        g = sample["gauge"]
        delta_uah = (model.full_car_counts(g["car0"], g["car1"]) - origin) * model.NAH_PER_FULL_COUNT / 1000
        qmid = (estimate["qmax_low_uah"] + estimate["qmax_high_uah"]) / 2
        offset = float(delta_uah * 100 / F(qmid))
        points.append(estimate["percentage"] - offset)
        lows.append(estimate["percentage_low"] - offset)
        highs.append(estimate["percentage_high"] - offset)
    seed = dict(estimated=True, percentage=statistics.median(points),
                percentage_low=min(lows), percentage_high=max(highs),
                qmax_low_uah=min(e["qmax_low_uah"] for e in estimates),
                qmax_high_uah=max(e["qmax_high_uah"] for e in estimates))
    if seed["percentage_high"] - seed["percentage_low"] > 15:
        raise model.InvalidMeasurement("seed history sensitivity exceeds15points")
    tracker = model.CounterTrack(seed, first["car0"], first["car1"], first["mono_ns"] // 1000000)
    result = dict(seed)
    for sample in history[1:]:
        result = advance(tracker, sample)
    return tracker, result


def advance(tracker, sample):
    g = sample["gauge"]
    # Full ADC current measurement range, not an invented load limit.
    maximum_ua = math.ceil(F(32767 * 381470 * 10 * 1010, 1000000))
    result = tracker.update(g["car0"], g["car1"], g["mono_ns"] // 1000000,
                            max_gap_ms=10000, max_abs_current_ua=maximum_ua,
                            charge_error_uah=2, continuity_verified=True)
    qmid = (tracker.seed["qmax_low_uah"] + tracker.seed["qmax_high_uah"]) / 2
    result["percentage"] = max(0, min(100, tracker.seed["percentage"] + result["delta_uah"] * 100 / qmid))
    return result


def commit(endpoint, sample, result=None):
    g = sample["gauge"]
    cap = -1
    margin = 0
    if result is not None:
        cap = max(0, min(10000, round(result["percentage"] * 100)))
        margin = math.ceil(max(result["percentage"] - result["percentage_low"],
                               result["percentage_high"] - result["percentage"]) * 100)
    temp_dc = round(sample["temp_mc"] / 100)
    (endpoint / "commit").write_text(f'{g["sequence"]} {g["mono_ns"]} {temp_dc} {cap} {margin}\n')


def run(endpoint, margin_bp, runtime_seconds):
    global STOP
    adc = find_adc()
    history = []
    tracker = None
    start = boottime_ns()
    deadline = start
    consecutive_errors = 0
    reported_seed = False
    last_percent = None
    last_state = None
    try:
        while not STOP and (runtime_seconds == 0 or boottime_ns() - start < runtime_seconds * 1000000000):
            delay = (deadline - boottime_ns()) / 1000000000
            if delay > 0:
                time.sleep(delay)
            if STOP:
                break
            try:
                sample = read_sample(endpoint, adc)
                result = None
                if tracker is None:
                    # Every seed row is qualified, not just the median.
                    sample["estimate"] = point_estimate(sample, margin_bp)
                    if history and sample["gauge"]["mono_ns"] - history[-1]["gauge"]["mono_ns"] > 1500000000:
                        history.clear()
                    history.append(sample)
                    validate_history(history)
                    if len(history) == 30:
                        tracker, result = make_tracker(history, margin_bp)
                        tracker.seed_temp_mc = statistics.median(s["temp_mc"] for s in history)
                else:
                    model.profile(int(sample["temp_mc"]))
                    if abs(sample["temp_mc"] - tracker.seed_temp_mc) > 5000:
                        raise model.InvalidMeasurement("temperature moved5C; new model seed needed")
                    result = advance(tracker, sample)
                commit(endpoint, sample, result)
                if result is not None and (not reported_seed or round(result["percentage"]) != last_percent):
                    print(json.dumps({"state": "estimated", "seed_samples": len(history),
                                      "sample_ns": sample["gauge"]["mono_ns"], "model": result}), flush=True)
                    reported_seed = True
                    last_percent = round(result["percentage"])
                last_state = "estimated" if result else "seeding"
                consecutive_errors = 0
            except model.InvalidMeasurement as error:
                invalidate(endpoint)
                tracker = None
                reported_seed = False
                history.clear()
                consecutive_errors = 0
                if last_state != "unqualified":
                    print(json.dumps({"state": "unqualified", "reason": str(error)}), flush=True)
                last_state = "unqualified"
            except (OSError, ValueError, KeyError, ArithmeticError) as error:
                invalidate(endpoint)
                tracker = None
                reported_seed = False
                history.clear()
                consecutive_errors += 1
                print(json.dumps({"state": "invalid", "error": str(error)}), flush=True)
                if consecutive_errors >= 5:
                    raise RuntimeError("five consecutive gauge/sensor/model errors") from error
            deadline = boottime_ns() + (5000000000 if tracker else 1000000000)
    finally:
        invalidate(endpoint)


def main():
    global STOP
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--endpoint", type=Path, default=ENDPOINT)
    parser.add_argument("--invalidate-only", action="store_true")
    parser.add_argument("--model-margin-bp", type=int)
    parser.add_argument("--runtime-seconds", type=int, default=0)
    parser.add_argument("--lock", type=Path, default=Path("/run/q25-native-gauge.lock"))
    args = parser.parse_args()
    if args.invalidate_only:
        invalidate(args.endpoint)
        return
    if args.model_margin_bp is None or not 0 <= args.model_margin_bp <= 2000 or not (args.runtime_seconds == 0 or 30 <= args.runtime_seconds <= 86400):
        parser.error("explicit provisional model margin0..2000bp and runtime0(unlimited) or30..86400s required")
    def stop(signum, frame):
        global STOP
        STOP = True
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    with args.lock.open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        run(args.endpoint, args.model_margin_bp, args.runtime_seconds)


if __name__ == "__main__":
    main()
