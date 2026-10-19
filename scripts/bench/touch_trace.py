#!/usr/bin/env python3
"""Record a touchscreen's raw evdev stream, and replay it through uinput.

Runs on the device as root, stdlib only.

  touch_trace.py record /dev/input/event9 OUT.trace SECONDS
      Passive: reads the node beside the shell (no EVIOCGRAB), writing each
      input_event as it arrives: "sec usec type code value", after a header
      with the device's name and ABS ranges.
  touch_trace.py replay IN.trace [--speed 1.0] [--times OUT.json]
      A uinput device with the recorded ranges and properties sends the same
      events at the recorded spacing (scaled by 1/speed).
"""
import array
import fcntl
import json
import os
import struct
import sys
import time

EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
BTN_TOUCH = 0x14a
EVENT = struct.Struct("<qqHHi")
ABSINFO = struct.Struct("<6i")


def ioc(direction, nr, size, kind=ord("E")):
    return (direction << 30) | (size << 16) | (kind << 8) | nr


def eviocgabs(axis):
    return ioc(2, 0x40 + axis, ABSINFO.size)


def eviocgname(n=256):
    return ioc(2, 0x06, n)


def eviocgbit(ev, n):
    return ioc(2, 0x20 + ev, n)


def eviocgprop(n=8):
    return ioc(2, 0x09, n)


def bits(buf):
    return [i for i in range(len(buf) * 8) if buf[i // 8] >> (i % 8) & 1]


def record(node, out, seconds):
    fd = os.open(node, os.O_RDONLY | os.O_NONBLOCK)
    name = bytearray(256)
    fcntl.ioctl(fd, eviocgname(), name, True)
    absbits = bytearray(8)
    fcntl.ioctl(fd, eviocgbit(EV_ABS, 8), absbits, True)
    keybits = bytearray(96)
    fcntl.ioctl(fd, eviocgbit(EV_KEY, 96), keybits, True)
    props = bytearray(8)
    fcntl.ioctl(fd, eviocgprop(), props, True)
    with open(out, "w") as f:
        f.write("# name %s\n" % name.split(b"\0")[0].decode(errors="replace"))
        f.write("# props %s\n" % " ".join(map(str, bits(props))))
        f.write("# keys %s\n" % " ".join(map(str, bits(keybits))))
        for axis in bits(absbits):
            info = bytearray(ABSINFO.size)
            fcntl.ioctl(fd, eviocgabs(axis), info, True)
            f.write("# abs %d %s\n" % (axis, " ".join(map(str, ABSINFO.unpack(info)))))
        end = time.monotonic() + seconds
        n = 0
        while time.monotonic() < end:
            try:
                data = os.read(fd, EVENT.size * 64)
            except BlockingIOError:
                time.sleep(0.002)
                continue
            for i in range(0, len(data) - EVENT.size + 1, EVENT.size):
                sec, usec, t, c, v = EVENT.unpack_from(data, i)
                f.write("%d %d %d %d %d\n" % (sec, usec, t, c, v))
                n += 1
    os.close(fd)
    print("recorded %d events" % n)


UI_SET_EVBIT, UI_SET_KEYBIT, UI_SET_ABSBIT, UI_SET_PROPBIT = 0x40045564, 0x40045565, 0x40045567, 0x4004556E
UI_DEV_CREATE, UI_DEV_DESTROY = 0x5501, 0x5502


def replay(trace, speed, times=None):
    absinfo, keys, props, events = {}, [], [], []
    for line in open(trace):
        p = line.split()
        if line.startswith("# abs"):
            absinfo[int(p[2])] = [int(x) for x in p[3:9]]
        elif line.startswith("# keys"):
            keys = [int(x) for x in p[2:]]
        elif line.startswith("# props"):
            props = [int(x) for x in p[2:]]
        elif not line.startswith("#") and len(p) == 5:
            events.append([int(x) for x in p])
    fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
    fcntl.ioctl(fd, UI_SET_EVBIT, EV_ABS)
    for k in keys:
        fcntl.ioctl(fd, UI_SET_KEYBIT, k)
    for pr in props:
        fcntl.ioctl(fd, UI_SET_PROPBIT, pr)
    absmax, absmin, fuzz, flat = [0] * 64, [0] * 64, [0] * 64, [0] * 64
    for axis, (value, mn, mx, fz, fl, res) in absinfo.items():
        fcntl.ioctl(fd, UI_SET_ABSBIT, axis)
        absmin[axis], absmax[axis], fuzz[axis], flat[axis] = mn, mx, fz, fl
    dev = b"touch-replay".ljust(80, b"\0") + struct.pack("<HHHHi", 3, 1, 1, 1, 0)
    for arr in (absmax, absmin, fuzz, flat):
        dev += struct.pack("<64i", *arr)
    os.write(fd, dev)
    fcntl.ioctl(fd, UI_DEV_CREATE)
    time.sleep(0.8)
    try:
        if events:
            t0 = events[0][0] + events[0][1] / 1e6
            start = time.monotonic()
            moves, syns = [], -1
            for sec, usec, t, c, v in events:
                due = start + (sec + usec / 1e6 - t0) / speed
                d = due - time.monotonic()
                if d > 0:
                    time.sleep(d)
                os.write(fd, EVENT.pack(0, 0, t, c, v))
                if t == EV_KEY and c == BTN_TOUCH and v == 1:
                    syns = 0
                elif t == EV_KEY and c == BTN_TOUCH and v == 0 and moves:
                    moves[-1]["up_rt"] = time.time()
                elif t == 0 and syns >= 0:
                    syns += 1
                    if syns == 2:
                        moves.append({"move_rt": time.time()})
                        syns = -1
        time.sleep(0.3)
    finally:
        fcntl.ioctl(fd, UI_DEV_DESTROY)
        os.close(fd)
    print("replayed %d events" % len(events))
    if times:
        with open(times, "w") as f:
            json.dump({"round_times": moves}, f)


def main():
    if len(sys.argv) >= 5 and sys.argv[1] == "record":
        record(sys.argv[2], sys.argv[3], float(sys.argv[4]))
    elif len(sys.argv) >= 3 and sys.argv[1] == "replay":
        speed = float(sys.argv[sys.argv.index("--speed") + 1]) if "--speed" in sys.argv else 1.0
        times = sys.argv[sys.argv.index("--times") + 1] if "--times" in sys.argv else None
        replay(sys.argv[2], speed, times)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
