#!/usr/bin/env python3
"""Monitor ALL Q20 input devices including mouse for scroll events"""
import struct
import select
import sys

# Event types
EV_SYN = 0x00
EV_KEY = 0x01
EV_REL = 0x02
EV_ABS = 0x03

# Relative axis codes
REL_X = 0x00
REL_Y = 0x01
REL_WHEEL = 0x08
REL_HWHEEL = 0x06
REL_WHEEL_HI_RES = 0x0b
REL_HWHEEL_HI_RES = 0x0c

KEY_RELEASE = 0
KEY_PRESS = 1

devices = [
    ("/dev/input/event0", "Keyboard"),
    ("/dev/input/event1", "Mouse/Trackpoint"),
    ("/dev/input/event2", "System Control"),
    ("/dev/input/event3", "Consumer Control"),
]

fds = {}
for path, name in devices:
    try:
        fd = open(path, "rb")
        fds[fd.fileno()] = (fd, name, path)
        print(f"Opened {name}: {path}")
    except Exception as e:
        print(f"Cannot open {path}: {e}")

if not fds:
    print("No devices opened!")
    sys.exit(1)

print("\n" + "="*60)
print("FULL CAPTURE: Keys + Mouse + Scroll Events")
print("Press CALL button, enable scroll mode, scroll around...")
print("="*60 + "\n")

try:
    while True:
        readable, _, _ = select.select(list(fds.keys()), [], [], 0.1)
        for fileno in readable:
            fd, name, path = fds[fileno]
            data = fd.read(24)
            if len(data) == 24:
                tv_sec, tv_usec, ev_type, code, value = struct.unpack('llHHi', data)
                
                # Key events
                if ev_type == EV_KEY and value in (KEY_PRESS, KEY_RELEASE):
                    action = "PRESSED" if value == KEY_PRESS else "RELEASED"
                    print(f"[{name}] KEY code={code} (0x{code:04x}) {action}")
                
                # Relative events (mouse/scroll)
                elif ev_type == EV_REL:
                    axis_names = {
                        REL_X: "REL_X",
                        REL_Y: "REL_Y",
                        REL_WHEEL: "SCROLL_WHEEL",
                        REL_HWHEEL: "HSCROLL_WHEEL",
                        REL_WHEEL_HI_RES: "SCROLL_HI_RES",
                        REL_HWHEEL_HI_RES: "HSCROLL_HI_RES",
                    }
                    axis = axis_names.get(code, f"REL_{code}")
                    # Highlight scroll events
                    if code in (REL_WHEEL, REL_HWHEEL, REL_WHEEL_HI_RES, REL_HWHEEL_HI_RES):
                        print(f"[{name}] ★★★ {axis}={value} ★★★")
                    elif abs(value) > 3:  # Only show significant movements
                        print(f"[{name}] {axis}={value}")
                    
except KeyboardInterrupt:
    print("\nDone!")
finally:
    for fileno, (fd, _, _) in fds.items():
        fd.close()
