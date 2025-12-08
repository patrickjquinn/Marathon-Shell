#!/usr/bin/env python3
"""Monitor ALL Q20 keyboard devices for key events"""
import struct
import select
import sys

# Event types
EV_KEY = 0x01
EV_REL = 0x02
EV_ABS = 0x03

# Key event values
KEY_RELEASE = 0
KEY_PRESS = 1

devices = [
    ("/dev/input/event0", "Keyboard"),
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

print("\n" + "="*50)
print("Press Back button, BB key, Call, Hangup...")
print("="*50 + "\n")

try:
    while True:
        readable, _, _ = select.select(list(fds.keys()), [], [], 0.1)
        for fileno in readable:
            fd, name, path = fds[fileno]
            data = fd.read(24)  # input_event struct size
            if len(data) == 24:
                # Parse input_event: time (16 bytes), type (2), code (2), value (4)
                tv_sec, tv_usec, ev_type, code, value = struct.unpack('llHHi', data)
                
                if ev_type == EV_KEY and value in (KEY_PRESS, KEY_RELEASE):
                    action = "PRESSED" if value == KEY_PRESS else "RELEASED"
                    print(f"[{name}] KEY code={code} (0x{code:04x}) {action}")
                    
except KeyboardInterrupt:
    print("\nDone!")
finally:
    for fileno, (fd, _, _) in fds.items():
        fd.close()
