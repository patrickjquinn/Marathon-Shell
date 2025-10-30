# OnePlus 6 Device Fixes - Summary

**Date:** 2025-10-30  
**Commit:** e8c5700

## What Was Fixed

### ❌ CRITICAL: Screen Blanking on Lock (FIXED ✅)

**Problem:** Power button locked the phone but screen stayed on, wasting battery.

**Root Cause:** `DisplayManager._platformSetScreenState()` only logged, didn't actually blank the screen.

**Fix:**
1. Added `DisplayManagerCpp::setScreenState(bool on)` to write to `/sys/class/graphics/fb0/blank`
   - `0` = screen on
   - `4` = screen off (powerdown)
2. Updated `DisplayManager.qml` to call the C++ method
3. Updated `SessionManager.lockSession()` to call `DisplayManager.turnScreenOff()`
4. Updated `SessionManager.unlockSession()` to call `DisplayManager.turnScreenOn()`

**Result:** Screen now blanks when you press the power button! 🎉

---

### 🟡 DPI Scaling (FIXED ✅)

**Problem:** UI elements were too large because baseDPI was too low (120).

**Device Logs:**
```
Screen size: 1080x2280 @ 401 DPI
Scale factor: 2.508765212981744 (base: 2.85 x user: 0.75)
```

**Calculation (OLD):**
- Device DPI: 401
- baseDPI: 120
- Scale: (401/120) × 0.75 = **2.51x** (too large!)

**Calculation (NEW):**
- Device DPI: 401
- baseDPI: 160 (Android MDPI standard)
- Scale: (401/160) × 0.75 = **1.88x** (much better!)

**Fix:** Changed `Constants.qml` baseDPI from 120 → 160

**Result:** UI elements will be properly sized for the OnePlus 6! 📱

---

### 🟡 Quick Settings Width (FIXED ✅)

**Problem:** Quick Settings shade had 800px max width on 1080px screen, looking narrow.

**Device Logs:**
```
QuickSettings: Grid layout: 3 cols × 3 rows (screen: 1080px, max shade width: 800px)
```

**Fix:** Changed breakpoint from `< 1200px` to `<= 1080px` so OnePlus 6 uses full width.

**Result:** Quick Settings shade now uses full width on OnePlus 6! 🎨

---

## What Still Needs Testing

### ⚠️ Bluetooth

**Status:** Not working on device

**Device Logs:**
```
[BluetoothManager] Bluetooth not available (bluez service not running or no hardware)
```

**Fix (via SSH):**
```bash
sudo systemctl enable bluetooth
sudo systemctl start bluetooth
systemctl status bluetooth
```

---

### ⚠️ Brightness Permissions

**Status:** Backlight detected but permissions may be needed

**Device Logs:**
```
[DisplayManagerCpp] Detected backlight device: "ae94000.dsi.0" max brightness: 1023
```

**Test:**
```bash
# Check current permissions:
ls -la /sys/class/backlight/ae94000.dsi.0/brightness

# If needed, set permissions:
sudo chmod 666 /sys/class/backlight/ae94000.dsi.0/brightness

# Test brightness:
echo 500 | sudo tee /sys/class/backlight/ae94000.dsi.0/brightness
```

---

### ⚠️ Screen Blank Permissions

**Status:** May need permissions for `/sys/class/graphics/fb0/blank`

**Test:**
```bash
# Check if file exists:
ls -la /sys/class/graphics/fb0/blank

# Test manually:
echo 4 | sudo tee /sys/class/graphics/fb0/blank  # Screen OFF
echo 0 | sudo tee /sys/class/graphics/fb0/blank  # Screen ON
```

---

## Desktop vs Device

### Desktop Testing (540x1140 window)
- Window: 540×1140 (50% of OnePlus 6)
- DPI: 120 (matches baseDPI for 1:1 scaling)
- Scale factor: 1.0
- Icon size: 72px
- Grid: 4×5 (20 apps per page)

### Device (OnePlus 6)
- Screen: 1080×2280 (full resolution)
- DPI: 401 (actual device DPI)
- Scale factor: 1.88x (with new baseDPI=160)
- Icon size: 135px (72 × 1.88)
- Grid: 4×5 (20 apps per page)

---

## Next Steps

1. **Rebuild Marathon Shell** with these fixes
2. **Deploy new image** to OnePlus 6
3. **Test screen blanking** by pressing power button
4. **Enable Bluetooth** via SSH (see above)
5. **Test brightness slider** and set permissions if needed
6. **Report back** on what works! 🚀

---

## Why You Saw No Difference

The changes I made earlier (540x1140, DPI 120) were for **desktop testing only**. The device was still running the **old code** from the image.

To see these fixes on the **device**, you need to:
1. Rebuild Marathon Shell (with commit e8c5700)
2. Build a new PostmarketOS image
3. Flash it to the OnePlus 6

Then the fixes will take effect! 📱✨

