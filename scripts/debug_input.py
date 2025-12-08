#!/usr/bin/env python3
import struct
import sys
import os
import time

# Identify device
DEVICE_NAME_KEYWORD = "ZitaoTech HACKBerryPiQ20 Mouse"
INPUT_DIR = "/dev/input"

def find_device():
    with open("/proc/bus/input/devices", "r") as f:
        lines = f.readlines()
    
    current_name = ""
    for line in lines:
        if line.startswith("N: Name="):
            current_name = line.split('"')[1]
        if line.startswith("H: Handlers=") and DEVICE_NAME_KEYWORD in current_name:
            handlers = line.split("=")[1].strip().split()
            for h in handlers:
                if h.startswith("event"):
                    return os.path.join(INPUT_DIR, h)
    return None

def main():
    device_path = find_device()
    if not device_path:
        print(f"Error: Could not find device matching '{DEVICE_NAME_KEYWORD}'")
        sys.exit(1)
        
    print(f"Found Trackball at: {device_path}")
    print("Reading events... (Press Ctrl+C to stop)")
    print("Please: 1. Click, 2. Move Ball, 3. Hold Alt + Scroll")
    print("-" * 40)
    
    # Event constants
    EV_KEY = 0x01
    EV_REL = 0x02
    REL_X = 0x00
    REL_Y = 0x01
    BTN_LEFT = 0x110
    BTN_RIGHT = 0x111
    BTN_MIDDLE = 0x112
    
    try:
        with open(device_path, "rb") as f:
            while True:
                data = f.read(24) # 16 (time) + 2 (type) + 2 (code) + 4 (val) = 24 bytes
                if len(data) < 24:
                    continue
                    
                # Unpack: ll (long long sec, long long usec), H (ushort type), H (ushort code), i (int val)
                tv_sec, tv_usec, ev_type, ev_code, ev_value = struct.unpack('llHHi', data)
                
                if ev_type == EV_REL:
                    if ev_code == REL_X:
                        print(f"REL_X: {ev_value}")
                    elif ev_code == REL_Y:
                        print(f"REL_Y: {ev_value}")
                elif ev_type == EV_KEY:
                    state = "Pressed" if ev_value else "Released"
                    key_name = f"Key {ev_code}"
                    if ev_code == BTN_LEFT: key_name = "BTN_LEFT"
                    elif ev_code == BTN_RIGHT: key_name = "BTN_RIGHT"
                    elif ev_code == BTN_MIDDLE: key_name = "BTN_MIDDLE"
                    print(f"{key_name}: {state}")
                    
    except PermissionError:
        print("Error: Permission denied. Please run with sudo.")
    except KeyboardInterrupt:
        print("\nExiting.")

if __name__ == "__main__":
    main()
