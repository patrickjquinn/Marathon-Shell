# Marathon Shell Issues Analysis & Fix Plan

## Executive Summary

**Date:** 2025-10-30  
**Device:** OnePlus 6 (enchilada) - 2280x1080, ~402 PPI  
**Image:** marathon-ACTUALLY-FINAL.img (built with 16GB RAM, auto-login fixed)

### ✅ **GOOD NEWS:**
- Shell boots and runs successfully
- DPI detection is working correctly (using `Screen.pixelDensity * 25.4`)
- Auto-login via greetd is working
- Udev rules exist and are installed by CMake

### ❌ **CRITICAL ISSUE:**
- **Screen does not turn off when lock button is pressed**
  - Root cause: `SessionManager._platformLock()` and `DisplayManager._platformSetScreenState()` only log, don't actually blank screen
  - Fix: Implement `DisplayManagerCpp::setScreenState()` to write to `/sys/class/graphics/fb0/blank`

### ⚠️ **NEEDS TESTING:**
- WiFi (should work - `networkmanager-wifi` added)
- Bluetooth (should work - `bluez` service enabled)
- Brightness (udev rules installed but may need manual trigger)

### 🔧 **TUNING NEEDED:**
- DPI base value too low (120 → should be 160 for better scaling)

---

## Issues Identified

### 1. **DPI/Scaling Issues** ✅ (Already Implemented, But May Need Tuning)
**Problem:** UI elements are inconsistently sized - some too large, some too small.

**Root Cause:** ✅ **DPI IS BEING DETECTED CORRECTLY!**
```qml
// MarathonShell.qml line 51 (Component.onCompleted)
Constants.updateScreenSize(shell.width, shell.height, Screen.pixelDensity * 25.4)
```

**Current Behavior:**
- Base DPI: 120
- OnePlus 6 actual DPI: ~402 PPI (2280x1080, 6.28" diagonal)
- Scale factor: (402/120) * userScaleFactor = 3.35x * 0.75 = **2.51x**
- User has set scale to 75% to compensate

**Why Different Sizes:**
- Lock screen uses `fontSizeGigantic: Math.round(96 * scaleFactor)` = 241px
- Settings uses `fontSizeXXLarge: Math.round(32 * scaleFactor)` = 80px
- All sizes ARE using the same scale factor
- **Issue: Base DPI of 120 is too low for high-DPI phones**

**Recommended Fix:**
Change `baseDPI` in Constants.qml from 120 to 160 (standard Android MDPI):
```qml
readonly property real baseDPI: 160  // Android MDPI baseline
```
This would give: (402/160) * 0.75 = **1.89x** scale (more reasonable)

---

### 2. **Screen Not Turning Off on Lock** ❌ **CRITICAL BUG**
**Problem:** Power button SHORT PRESS locks the phone but screen stays on (doesn't blank or suspend).

**What Actually Happens:**
1. Power button released → `SessionStore.lock()` called (line 1313)
2. `SessionManager.lockSession()` called (SessionManager.qml line 29)
3. Sets `screenLocked = true` and emits signal
4. `_platformLock()` called → **ONLY LOGS, DOES NOTHING!** (line 89-95)

**What SHOULD Happen:**
1. Lock button → Lock session
2. Turn off screen via `/sys/class/graphics/fb0/blank`
3. Optionally suspend to RAM via `PowerManagerCpp.suspend()`

**Root Cause:**
```qml
// SessionManager.qml line 89-95
function _platformLock() {
    if (Platform.hasSystemdLogind) {
        console.log("[SessionManager] D-Bus call to systemd-logind Lock")
        // ⚠️ ONLY LOGS! NO ACTUAL D-BUS CALL OR SCREEN BLANKING!
    }
}
```

**AND:**
```qml
// DisplayManager.qml line 177-181
function _platformSetScreenState(on) {
    if (Platform.isLinux) {
        console.log("[DisplayManager] Screen state via DPMS:", on)
        // ⚠️ ONLY LOGS! DOESN'T ACTUALLY DO ANYTHING!
    }
}
```

**Fix Required:**
1. Add `setScreenState()` to `DisplayManagerCpp` (C++)
2. Call it from `DisplayManager._platformSetScreenState()`
3. Call `DisplayManager.turnScreenOff()` from `SessionManager.lockSession()`

```cpp
// displaymanagercpp.h - ADD THIS METHOD:
Q_INVOKABLE void setScreenState(bool on);

// displaymanagercpp.cpp - ADD THIS IMPLEMENTATION:
void DisplayManagerCpp::setScreenState(bool on) {
    QString blankPath = "/sys/class/graphics/fb0/blank";
    QFile file(blankPath);
    if (file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        QTextStream stream(&file);
        stream << (on ? "0" : "4");  // 0=on, 4=off
        file.close();
        qDebug() << "[DisplayManagerCpp] Screen" << (on ? "ON" : "OFF");
    } else {
        qDebug() << "[DisplayManagerCpp] Failed to set screen state";
    }
}
```

```qml
// DisplayManager.qml line 177 - REPLACE WITH:
function _platformSetScreenState(on) {
    if (Platform.isLinux && typeof DisplayManagerCpp !== 'undefined') {
        DisplayManagerCpp.setScreenState(on)
    }
}
```

```qml
// SessionManager.qml line 29 - ADD turnScreenOff():
function lockSession() {
    console.log("[SessionManager] Locking session...")
    screenLocked = true
    sessionState = "locked"
    sessionLocked()
    DisplayManager.turnScreenOff()  // ADD THIS LINE
    _platformLock()
}
```

---

### 3. **WiFi Not Working** ⚠️ **SHOULD BE FIXED**
**Problem:** WiFi toggle/scan not working.

**Root Cause:** NetworkManager was running BUT `networkmanager-wifi` plugin was missing.

**What We Did:**
- ✅ Added `networkmanager-wifi` to `device-oneplus-enchilada-marathon/APKBUILD`
- ✅ Added `networkmanager-cli` for `nmcli` command
- ✅ Enabled NetworkManager service in post-install

**Status:** Should work in the current image. The user needs to test after reboot.

**Check on Device:**
```bash
systemctl status NetworkManager
nmcli device status
nmcli device wifi list
```

**If Still Not Working:**
```bash
# Check if wifi plugin is loaded:
journalctl -u NetworkManager | grep -i wifi

# Check if wlan0 exists:
ip link show wlan0

# Restart NetworkManager:
sudo systemctl restart NetworkManager
```

---

### 4. **Bluetooth Not Working** ⚠️ **SHOULD BE FIXED**
**Problem:** Bluetooth toggle not working.

**Root Cause:** BlueZ service was not enabled.

**What We Did:**
- ✅ Added `bluez` to `device-oneplus-enchilada-marathon/APKBUILD`
- ✅ Added `systemctl enable bluetooth` to post-install script

**Status:** Should work in the current image. The user needs to test after reboot.

**Check on Device:**
```bash
systemctl status bluetooth
hciconfig  # Check if BT hardware detected
bluetoothctl list  # List BT adapters
```

**If Still Not Working:**
```bash
# Enable and start bluetooth:
sudo systemctl enable bluetooth
sudo systemctl start bluetooth

# Check if hardware is detected:
dmesg | grep -i bluetooth
lsusb | grep -i bluetooth  # If USB BT
```

---

### 5. **Brightness Not Working** ⚠️ **UDEV RULES ISSUE**
**Problem:** Brightness slider does nothing.

**Root Cause:** Udev rules exist in Marathon Shell but may not be installed/loaded.

**What We Found:**
- ✅ `udev/70-marathon-shell.rules` EXISTS in Marathon Shell repo
- ✅ CMakeLists.txt line 119 INSTALLS it to `/usr/lib/udev/rules.d/`
- ✅ APKBUILD runs `cmake --install` which should install udev rules
- ❓ **BUT:** Rules may not be loaded or permissions not applied

**Udev Rule (line 13):**
```
SUBSYSTEM=="backlight", RUN+="/bin/chmod 0666 /sys/class/backlight/%k/brightness"
```

**Check on Device:**
```bash
# Check if backlight device exists:
ls -la /sys/class/backlight/

# Check if udev rule is installed:
ls -la /usr/lib/udev/rules.d/70-marathon-shell.rules
ls -la /etc/udev/rules.d/70-marathon-shell.rules

# Check current permissions:
ls -la /sys/class/backlight/*/brightness

# Check max brightness:
cat /sys/class/backlight/*/max_brightness
```

**Manual Fix:**
```bash
# Set permissions manually:
sudo chmod 666 /sys/class/backlight/*/brightness

# Reload udev rules:
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=backlight

# Test brightness:
echo 500 | sudo tee /sys/class/backlight/*/brightness
```

**Permanent Fix (if udev rule not installed):**
```bash
# Copy udev rule manually:
sudo cp /usr/lib/udev/rules.d/70-marathon-shell.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
sudo udevadm trigger
```

---

## Summary

| Issue | Status | Severity | Fix Type |
|-------|--------|----------|----------|
| DPI/Scaling | ✅ Working (needs tuning) | Medium | Rebuild Shell |
| Screen Off on Lock | ❌ **BROKEN** | **CRITICAL** | Rebuild Shell |
| WiFi | ⚠️ Should work | Medium | Test/Verify |
| Bluetooth | ⚠️ Should work | Low | Test/Verify |
| Brightness | ⚠️ Udev issue | Medium | Manual fix OR Rebuild |

## Priority Fix Order

### **CRITICAL (Rebuild Required):**
1. ❌ **Screen blanking on lock** - Add `DisplayManagerCpp::setScreenState()` method
2. ⚠️ **DPI tuning** - Change `baseDPI` from 120 to 160 in Constants.qml

### **CAN FIX NOW (via SSH):**
3. ⚠️ **Brightness permissions** - `sudo chmod 666 /sys/class/backlight/*/brightness`
4. ⚠️ **Test WiFi** - Should work, verify with `nmcli device wifi list`
5. ⚠️ **Test Bluetooth** - Should work, verify with `systemctl status bluetooth`

---

## Quick Fixes You Can Try NOW (via SSH):

### Fix Brightness:
```bash
# Find backlight device
ls /sys/class/backlight/

# Set permissions (replace 'panel0-backlight' with your device):
sudo chmod 666 /sys/class/backlight/*/brightness
sudo chmod 666 /sys/class/backlight/*/bl_power

# Test brightness:
echo 500 | sudo tee /sys/class/backlight/*/brightness
```

### Enable Bluetooth:
```bash
sudo systemctl enable bluetooth
sudo systemctl start bluetooth
systemctl status bluetooth
```

### Check WiFi:
```bash
nmcli device wifi list
nmcli device status
```

### Fix Screen Blank (manual test):
```bash
# Turn screen off:
echo 4 | sudo tee /sys/class/graphics/fb0/blank

# Turn screen on:
echo 0 | sudo tee /sys/class/graphics/fb0/blank
```

---

## Files That Need Changes in Marathon Shell:

### **CRITICAL FIXES:**
1. **`shell/src/displaymanagercpp.h`** - Add `Q_INVOKABLE void setScreenState(bool on);`
2. **`shell/src/displaymanagercpp.cpp`** - Implement screen blanking via `/sys/class/graphics/fb0/blank`
3. **`shell/qml/services/DisplayManager.qml`** - Call `DisplayManagerCpp.setScreenState()` in `_platformSetScreenState()`
4. **`shell/qml/services/SessionManager.qml`** - Call `DisplayManager.turnScreenOff()` in `lockSession()`

### **TUNING:**
5. **`shell/qml/core/Constants.qml`** - Change `baseDPI: 120` to `baseDPI: 160`

### **VERIFICATION:**
6. **`APKBUILD`** - Verify udev rules are installed (already in CMakeLists.txt line 119)

---

## Testing Commands for Debug Logs:

```bash
# Stop greetd
sudo systemctl stop greetd

# Run Marathon Shell with full debug:
MARATHON_DEBUG=1 \
QT_LOGGING_RULES="*.debug=true" \
QT_QPA_EGLFS_DEBUG=1 \
/usr/bin/marathon-shell-bin -platform eglfs 2>&1 | tee /tmp/marathon-debug.log

# In another SSH session, check the log:
tail -f /tmp/marathon-debug.log | grep -i "dpi\|scale\|brightness\|backlight\|wifi\|bluetooth"
```

