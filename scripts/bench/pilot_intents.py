#!/usr/bin/env python3
"""Synthetic Pilot utterances over the 13 intents of Shipwright pilot.md 5.1.

Template-generated, not real or Jev-labelled data. Writes JSON lines
{"text", "intent", "template"} to stdout; the template id lets the
classifier be tested on phrasings it never saw.
"""
import itertools
import json
import random

R = random.Random(16)

SLOTS = {
    "time": ["7", "6:30", "half seven", "8 am", "quarter past six", "noon", "5:45", "9 tonight"],
    "dur": ["ten minutes", "5 minutes", "half an hour", "90 seconds", "an hour", "twenty minutes", "3 minutes"],
    "task": ["call the dentist", "take the bins out", "buy milk", "stretch", "pay the electric bill",
             "water the plants", "pick up <CONTACT_1>", "send the report"],
    "who": ["<CONTACT_1>", "<CONTACT_2>", "mum", "Dave", "the office", "<PHONE_1>"],
    "msg": ["I'm running late", "see you at 8", "can you grab bread", "on my way", "call me when you're free"],
    "event": ["lunch with <CONTACT_1>", "a dentist appointment", "team standup", "football practice", "dinner at Mario's"],
    "day": ["tomorrow", "on Friday", "next Tuesday", "on the 14th", "this afternoon"],
    "song": ["some jazz", "the next track", "my running playlist", "Taylor Swift", "the radio"],
    "dev": ["wifi", "bluetooth", "mobile data", "flight mode", "aeroplane mode"],
    "place": ["the airport", "home", "the nearest petrol station", "Galway", "work", "the train station"],
    "thing": ["this plant", "this sign", "the label on this bottle", "this bug", "this receipt"],
    "topic": ["the history of the Roman empire", "how vaccines work", "a dinner recipe with chickpeas",
              "what to do in Cork this weekend", "the difference between a crocodile and an alligator"],
}

T = {
    "alarm": ["set an alarm for {time}", "wake me up at {time}", "alarm at {time} please",
              "can you get me up at {time} tomorrow", "I need an alarm for {time}", "put an alarm on for {time}"],
    "timer": ["set a timer for {dur}", "timer {dur}", "start a {dur} countdown",
              "count down {dur} for the pasta", "let me know when {dur} is up", "{dur} timer please"],
    "reminder": ["remind me to {task} {day}", "remind me at {time} to {task}", "don't let me forget to {task}",
                 "can you remind me to {task}", "nudge me to {task} in {dur}", "set a reminder to {task}"],
    "call": ["call {who}", "ring {who}", "phone {who} please", "give {who} a call",
             "dial {who}", "can you call {who} for me"],
    "message": ["text {who} {msg}", "send {who} a message saying {msg}", "tell {who} {msg}",
                "message {who} that {msg}", "reply to {who} {msg}", "sms {who}: {msg}"],
    "calendar_add": ["add {event} {day}", "put {event} in my calendar {day}", "schedule {event} {day} at {time}",
                     "create an event: {event} {day}", "book {event} for {day}", "pencil in {event} {day}"],
    "calendar_query": ["what's on my calendar {day}", "am I free {day}", "what do I have {day}",
                       "when is {event}", "do I have anything {day} at {time}", "what's my next meeting"],
    "media": ["play {song}", "pause the music", "skip this song", "put on {song}",
              "stop the music", "resume playing {song}"],
    "device_toggle": ["turn on {dev}", "switch off {dev}", "disable {dev}", "enable {dev} please",
                      "can you turn {dev} off", "put {dev} on"],
    "navigation": ["navigate to {place}", "directions to {place}", "how do I get to {place}",
                   "take me to {place}", "how long to drive to {place}", "start a route to {place}"],
    "camera_vision": ["what is {thing}", "look at {thing} and tell me what it is", "can you read {thing}",
                      "identify {thing}", "what does {thing} say", "take a picture of {thing} and explain it"],
    "open_ended": ["tell me about {topic}", "explain {topic}", "give me ideas for {topic}",
                   "write me a short poem about {song}", "help me plan {topic}", "what do you know about {topic}"],
    "cancel": ["cancel that", "never mind", "cancel the {dur} timer", "stop the alarm",
               "delete the reminder to {task}", "forget it, cancel"],
}

PREFIX = ["", "", "", "hey pilot ", "please ", "could you ", "um ", "ok so "]


def fill(tpl):
    out = tpl
    for k, vals in SLOTS.items():
        while "{" + k + "}" in out:
            out = out.replace("{" + k + "}", R.choice(vals), 1)
    return out


def main(per_intent=39):
    rows = []
    for intent, tpls in T.items():
        seen = set()
        for i in itertools.count():
            if len(seen) >= per_intent or i > 5000:
                break
            t = i % len(tpls)
            s = (R.choice(PREFIX) + fill(tpls[t])).strip()
            if s not in seen:
                seen.add(s)
                rows.append({"text": s, "intent": intent, "template": f"{intent}/{t}"})
    for r in rows:
        print(json.dumps(r))


if __name__ == "__main__":
    main()
