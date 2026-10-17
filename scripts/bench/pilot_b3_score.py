#!/usr/bin/env python3
"""B3 (host side): timings and valid-tool-call rate from pilot_b3.py output.

A turn counts as valid when one of its tool calls names the expected tool
and its arguments parse and validate against that tool's schema.

usage: pilot_b3_score.py PREFIX   (reads PREFIX_{cold,warm,restore,turns}.json)
"""
import json
import statistics
import sys

import jsonschema

# Argument values a correct call must carry, for turns where one is unambiguous.
EXPECT = {
    "set a timer for ten minutes": {"seconds": 600}, "timer for 90 seconds": {"seconds": 90},
    "start a 25 minute countdown called focus": {"seconds": 1500},
    "count down 3 minutes for the eggs": {"seconds": 180}, "half an hour timer please": {"seconds": 1800},
    "set a timer for an hour and a half": {"seconds": 5400}, "can you time 45 seconds": {"seconds": 45},
    "pizza timer, twelve minutes": {"seconds": 720},
    "wake me up at 7": {"time": "07:00"}, "set an alarm for 6:15": {"time": "06:15"},
    "alarm at quarter to eight labelled gym": {"time": "07:45"}, "I need to be up at 5:30 tomorrow": {"time": "05:30"},
    "set an alarm for 9 pm": {"time": "21:00"}, "alarm for noon": {"time": "12:00"},
    "get me up at half seven": {"time": "07:30"}, "alarm 23:00 for bed": {"time": "23:00"},
    "pause the music": {"action": "pause"}, "skip this song": {"action": "next"},
    "go back to the previous track": {"action": "previous"}, "stop the music": {"action": "stop"},
    "next track please": {"action": "next"}, "pause": {"action": "pause"},
    "turn on wifi": {"target": "wifi", "on": True}, "switch bluetooth off": {"target": "bluetooth", "on": False},
    "disable mobile data": {"target": "mobile_data", "on": False},
    "put the phone in flight mode": {"target": "flight_mode", "on": True},
    "turn wifi off": {"target": "wifi", "on": False}, "enable bluetooth": {"target": "bluetooth", "on": True},
    "turn off aeroplane mode": {"target": "flight_mode", "on": False},
    "switch on mobile data": {"target": "mobile_data", "on": True},
    "is wifi on": {"target": "wifi"}, "is bluetooth on right now": {"target": "bluetooth"},
    "am I in flight mode": {"target": "flight_mode"}, "is mobile data enabled": {"target": "mobile_data"},
    "check if wifi is connected": {"target": "wifi"}, "is my bluetooth off": {"target": "bluetooth"},
    "tell me whether flight mode is on": {"target": "flight_mode"}, "is data on": {"target": "mobile_data"},
}


def calls(msg):
    for c in msg.get("tool_calls") or []:
        f = c["function"]
        a = f.get("arguments")
        try:
            a = json.loads(a) if isinstance(a, str) else a
        except ValueError:
            a = None
        yield f["name"], a


def main():
    pre = sys.argv[1]
    for ph in ("cold", "warm", "restore"):
        r = json.load(open(f"{pre}_{ph}.json"))["results"][0]
        t = r["timings"]
        print(f"{ph}: prompt_n={t['prompt_n']} prompt_ms={t['prompt_ms']:.0f} "
              f"pp={t['prompt_per_second']:.1f} tg={t['predicted_per_second']:.1f} "
              f"n_gen={t['predicted_n']} wall_ms={r['wall_ms']:.0f} "
              f"call={list(calls(r['message']))}")
    d = json.load(open(f"{pre}_turns.json"))
    schemas = {t["function"]["name"]: t["function"]["parameters"] for t in d["tools"]}
    ok = any_valid = no_call = clean = bad_calls = right = checked = 0
    fails = []
    pms, tgs, walls, pns = [], [], [], []
    for r in d["results"]:
        t = r["timings"]
        pms.append(t["prompt_ms"]); tgs.append(t["predicted_per_second"]); walls.append(r["wall_ms"]); pns.append(t["prompt_n"])
        cs = list(calls(r["message"]))
        if not cs:
            no_call += 1
        good = []
        args = {}
        for name, a in cs:
            if name in schemas and a is not None:
                try:
                    jsonschema.validate(a, schemas[name])
                    good.append(name)
                    args.setdefault(name, a)
                except jsonschema.ValidationError:
                    pass
        exp = EXPECT.get(r["utt"])
        if exp is not None:
            checked += 1
            got = args.get(r["want"], {})
            if all(got.get(k) == v for k, v in exp.items()):
                right += 1
        bad_calls += len(cs) - len(good)
        if len(cs) == len(good) == 1 and good[0] == r["want"]:
            clean += 1
        if good:
            any_valid += 1
        if r["want"] in good:
            ok += 1
        else:
            fails.append((r["utt"], r["want"], cs, (r["message"].get("content") or "")[:80]))
    n = len(d["results"])
    q = statistics.quantiles
    print(f"turns n={n}: valid expected-tool call {ok}/{n} ({ok / n:.0%}); any schema-valid call {any_valid}/{n}; no call {no_call}; "
          f"exactly one call, valid and expected {clean}/{n}; invalid extra calls {bad_calls}; "
          f"right argument values {right}/{checked}")
    print(f"  prompt_n median {statistics.median(pns)}; prompt_ms p50 {statistics.median(pms):.0f} p95 {q(pms, n=20)[18]:.0f}; "
          f"tg median {statistics.median(tgs):.1f} t/s; wall p50 {statistics.median(walls):.0f} p95 {q(walls, n=20)[18]:.0f} ms")
    for f in fails:
        print("  FAIL", f)


if __name__ == "__main__":
    main()
