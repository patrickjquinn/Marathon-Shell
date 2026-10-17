#!/usr/bin/env python3
"""B7: Piper time to first audio byte and RTF, one process per sentence
(model load included, as a fresh pilot-tts subprocess would pay it).

usage: pilot_b7.py PIPER_CMD... -- (sentences are built in)
"""
import subprocess
import sys
import time

SENTENCES = [
    "Timer set for ten minutes.",
    "Your next meeting is team standup tomorrow at nine, in the small room on the second floor.",
]


def run(cmd, text):
    t = time.monotonic()
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    p.stdin.write((text + "\n").encode())
    p.stdin.close()
    first = None
    n = 0
    while True:
        b = p.stdout.read1(65536)
        if not b:
            break
        if first is None:
            first = (time.monotonic() - t) * 1000
        n += len(b)
    err = p.stderr.read().decode()
    p.wait()
    total = (time.monotonic() - t) * 1000
    audio = n / 2 / 22050 * 1000
    return first, total, audio, err


def main():
    cmd = sys.argv[1:]
    for s in SENTENCES:
        for i in range(5):
            first, total, audio, err = run(cmd, s)
            rtf = [l for l in err.splitlines() if "Real-time factor" in l or "Loaded voice" in l]
            print(f"len={len(s)} rep={i} ttfb_ms={first:.0f} total_ms={total:.0f} audio_ms={audio:.0f} "
                  f"rtf_wall={total / audio:.3f} | {' | '.join(rtf)}", flush=True)


if __name__ == "__main__":
    main()
