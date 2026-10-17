#!/usr/bin/env python3
"""B4: Pilot's intent question as a restricted softmax over llama-server.

Prompt is pilotd jev.rs ScoreJev::prompt + "Answer:". Order "pilot" puts the
state (utterance) first as pilotd does; "reorder" puts it last so the
question and options are a cacheable prefix. Stdlib only; runs on the device.

usage: pilot_b4.py PORT UTTS.jsonl OUT.json [fresh]
  fresh: a second set of utterances, cache on only, so no prompt repeats an earlier one
"""
import json
import math
import sys
import time
import urllib.request

INTENTS = ["alarm", "timer", "reminder", "call", "message", "calendar_add", "calendar_query",
           "media", "device_toggle", "navigation", "camera_vision", "open_ended", "cancel"]
LABELS = [chr(ord("A") + i) for i in range(len(INTENTS))]
QUESTION = "The single action the user wants Pilot to perform."
OPTIONS = "Options:\n" + "".join(f"{l}. {t}\n" for l, t in zip(LABELS, INTENTS))


def state(u):
    return json.dumps({"utterance": u, "context": {"time": "18:42", "location_class": "commuting",
                                                   "foreground_app": "none"}}, separators=(",", ":"))


def prompt(u, order):
    if order == "pilot":
        return f"You answer with a single label.\nState: {state(u)}\nQuestion: {QUESTION}\n{OPTIONS}Answer:"
    return f"You answer with a single label.\nQuestion: {QUESTION}\n{OPTIONS}State: {state(u)}\nAnswer:"


def ask(port, p, cache):
    body = {"prompt": p, "n_predict": 1, "n_probs": 64, "temperature": 0, "cache_prompt": cache}
    req = urllib.request.Request(f"http://127.0.0.1:{port}/completion", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    t = time.monotonic()
    out = json.loads(urllib.request.urlopen(req, timeout=300).read())
    wall = (time.monotonic() - t) * 1000
    top = out["completion_probabilities"][0]["top_logprobs"]
    mass = {}
    for e in top:
        k = e["token"].strip()
        if k in LABELS:
            mass[k] = mass.get(k, 0.0) + math.exp(e["logprob"])
    return wall, out["timings"], mass


def main():
    port, utts, path = sys.argv[1], sys.argv[2], sys.argv[3]
    rows = [json.loads(l) for l in open(utts)]
    fresh = len(sys.argv) > 4
    picked = [r for i, r in enumerate(rows) if i % 13 == (6 if fresh else 0)][:39]
    res = []
    for order in ("pilot", "reorder"):
        for cache in ((True,) if fresh else (False, True)):
            for r in picked:
                wall, tm, mass = ask(port, prompt(r["text"], order), cache)
                tot = sum(mass.values())
                pred = INTENTS[LABELS.index(max(mass, key=mass.get))] if mass else None
                res.append({"order": order, "cache": cache, "intent": r["intent"], "pred": pred,
                            "wall_ms": wall, "prompt_n": tm["prompt_n"], "prompt_ms": tm["prompt_ms"],
                            "predicted_ms": tm["predicted_ms"], "label_mass": tot})
    json.dump(res, open(path, "w"))


if __name__ == "__main__":
    main()
