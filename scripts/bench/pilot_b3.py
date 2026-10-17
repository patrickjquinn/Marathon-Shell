#!/usr/bin/env python3
"""B3: Pilot's system prompt + 6 tool schemas against llama-server.

Stdlib only; runs on the device. The prompt and tools come from PROMPT.json.
remind_flat assumes tools[2] is reminder_create, as in the run in the doc.

usage: pilot_b3.py PROMPT.json PORT OUT.json PHASE
  PHASE: cold|warm|restore|turns|turns_greedy|remind_flat
"""
import json
import sys
import time
import urllib.request

# {"system": str, "tools": [OpenAI tool objects]} transcribed from Shipwright
# (proprietary, so not kept here): system_prompt + capabilities_line with the
# clock frozen, and six system_tools.rs specs with "." in names replaced by "_".
SYSTEM = ""
TOOLS = []


def load(path):
    global SYSTEM
    d = json.load(open(path))
    SYSTEM = d["system"]
    TOOLS[:] = d["tools"]


CTX = "[context: Friday 18:42, location commuting, foreground app none, no memory notes]\n"

TURN0 = "set a timer for ten minutes for the pasta and call it pasta please, I'm about to put it on now"
TURN1 = "wake me up at half six tomorrow morning, I have an early train to catch to Galway"
TURN2 = "remind me to ring <CONTACT_1> about the car insurance tomorrow at ten, before work starts"

TURNS = [
    ("set a timer for ten minutes", "timer_set"), ("timer for 90 seconds", "timer_set"),
    ("start a 25 minute countdown called focus", "timer_set"), ("count down 3 minutes for the eggs", "timer_set"),
    ("half an hour timer please", "timer_set"), ("set a timer for an hour and a half", "timer_set"),
    ("can you time 45 seconds", "timer_set"), ("pizza timer, twelve minutes", "timer_set"),
    ("wake me up at 7", "alarm_set"), ("set an alarm for 6:15", "alarm_set"),
    ("alarm at quarter to eight labelled gym", "alarm_set"), ("I need to be up at 5:30 tomorrow", "alarm_set"),
    ("set an alarm for 9 pm", "alarm_set"), ("alarm for noon", "alarm_set"),
    ("get me up at half seven", "alarm_set"), ("alarm 23:00 for bed", "alarm_set"),
    ("remind me to call the dentist in 20 minutes", "reminder_create"),
    ("remind me to take the bins out at 21:00", "reminder_create"),
    ("remind me tomorrow at 9 to send the report", "reminder_create"),
    ("don't let me forget to buy milk in an hour", "reminder_create"),
    ("remind me to ring <CONTACT_1> at 8 tonight", "reminder_create"),
    ("remind me to stretch in 45 minutes", "reminder_create"),
    ("remind me to water the plants on Sunday at 10", "reminder_create"),
    ("nudge me to pay the electric bill tomorrow at noon", "reminder_create"),
    ("pause the music", "media_control"), ("skip this song", "media_control"),
    ("play", "media_control"), ("go back to the previous track", "media_control"),
    ("stop the music", "media_control"), ("resume playback", "media_control"),
    ("next track please", "media_control"), ("pause", "media_control"),
    ("turn on wifi", "device_toggle"), ("switch bluetooth off", "device_toggle"),
    ("disable mobile data", "device_toggle"), ("put the phone in flight mode", "device_toggle"),
    ("turn wifi off", "device_toggle"), ("enable bluetooth", "device_toggle"),
    ("turn off aeroplane mode", "device_toggle"), ("switch on mobile data", "device_toggle"),
    ("is wifi on", "device_status"), ("is bluetooth on right now", "device_status"),
    ("am I in flight mode", "device_status"), ("is mobile data enabled", "device_status"),
    ("check if wifi is connected", "device_status"), ("is my bluetooth off", "device_status"),
    ("tell me whether flight mode is on", "device_status"), ("is data on", "device_status"),
    ("set a 15 minute timer and pause the music", "timer_set"),
    ("wake me at 6 and turn on wifi", "alarm_set"),
]


def post(port, path, body):
    req = urllib.request.Request(f"http://127.0.0.1:{port}{path}", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    t = time.monotonic()
    with urllib.request.urlopen(req, timeout=900) as r:
        out = json.loads(r.read())
    return out, (time.monotonic() - t) * 1000


GREEDY = False


def chat(port, utt):
    body = {"messages": [{"role": "system", "content": SYSTEM}, {"role": "user", "content": CTX + utt}],
            "tools": TOOLS, "tool_choice": "auto", "temperature": 0.7, "top_p": 0.8,
            "presence_penalty": 1.5, "max_tokens": 100, "cache_prompt": True,
            "chat_template_kwargs": {"enable_thinking": False}}
    if GREEDY:
        body.update(temperature=0, presence_penalty=0)
    out, wall = post(port, "/v1/chat/completions", body)
    msg = out["choices"][0]["message"]
    return {"utt": utt, "wall_ms": wall, "timings": out.get("timings"), "message": msg}


def main():
    load(sys.argv[1])
    port, path, phase = sys.argv[2], sys.argv[3], sys.argv[4]
    res = []
    if phase == "cold":
        res.append(chat(port, TURN0))
    elif phase == "warm":
        res.append(chat(port, TURN1))
    elif phase == "restore":
        res.append(chat(port, TURN2))
    elif phase in ("turns", "turns_greedy"):
        global GREEDY
        GREEDY = phase == "turns_greedy"
        for utt, want in TURNS:
            r = chat(port, utt)
            r["want"] = want
            res.append(r)
            print(want, r["timings"]["prompt_n"], round(r["timings"]["prompt_ms"]),
                  round(r["timings"]["predicted_per_second"], 1), file=sys.stderr, flush=True)
    elif phase == "remind_flat":
        # Same reminder turns with the reminder schema's oneOf dropped, to separate
        # llama.cpp's schema-to-grammar handling from the model.
        flat = json.loads(json.dumps(TOOLS))
        flat[2]["function"]["parameters"].pop("oneOf")
        TOOLS[:] = flat
        for utt, want in TURNS:
            if want == "reminder_create":
                r = chat(port, utt)
                r["want"] = want
                res.append(r)
    json.dump({"phase": phase, "results": res, "tools": TOOLS}, open(path, "w"))


if __name__ == "__main__":
    main()
