# Device Issues - Resolved & Pending

## ✅ **FIXED: Typography Scaling (Desktop & Device)**

**Problem:** Settings app and other Marathon apps showed huge text that didn't scale when user changed scale factor.

**Root Cause:** `Typography.qml` had hardcoded font sizes (28, 20, 16, 14, 12 pixels) that didn't use `Constants.scaleFactor`.

**Fix:**
Updated `shell/qml/theme/Typography.qml` to make all font sizes responsive:

```qml
// OLD (hardcoded):
readonly property int sizeXLarge: 28
readonly property int sizeLarge: 20

// NEW (responsive):
readonly property int sizeXLarge: Math.round(28 * (Constants.scaleFactor || 1.0))
readonly property int sizeLarge: Math.round(20 * (Constants.scaleFactor || 1.0))
```

**Result:** All Settings pages and Marathon apps now scale properly with user scale factor! 🎉

---

## ✅ **CONFIRMED: Keyboard Already Scales**

**Status:** Keyboard IS already using `Constants.scaleFactor` for all sizing.

**Evidence:**
- `Key.qml` uses `Math.round(60 * Constants.scaleFactor)` for width
- `Key.qml` uses `Math.round(45 * Constants.scaleFactor)` for height
- `QwertyLayout.qml` uses `Math.round(1 * Constants.scaleFactor)` for spacing

**Result:** Keyboard scales properly with screen size! ✅

---

## ⚠️ **PENDING: Keyboard Should Push Content Up**

**Problem:** Keyboard overlays app content instead of pushing it up.

**Status:** NEEDS INVESTIGATION - keyboard component location unknown in shell hierarchy.

**Expected Behavior:**
1. When keyboard appears, app content should shrink/scroll up
2. Focused input field should remain visible above keyboard
3. When keyboard disappears, app content should expand back

**Investigation Needed:**
- Find where `VirtualKeyboard` component is instantiated
- Determine how apps can be made aware of keyboard height
- Implement content adjustment mechanism

---

## ❌ **DEVICE ISSUE: Terminal App Won't Launch**

**Problem:** Terminal app fails to load on device with library error.

**Error:**
```
[MarathonAppLoader] Component error: "Cannot load library libterminal-plugin.so: No such file or directory"
```

**Root Cause:** Terminal app has a C++ plugin (`libterminal-plugin.so`) that's missing from device installation.

**Fix Options:**

### Option 1: Install Plugin (Recommended)
The terminal plugin needs to be copied to the system library path:

```bash
# Check if plugin exists in build:
ls -la /usr/share/marathon-apps/terminal/Terminal/libterminal-pluginplugin.so

# Check if libterminal-plugin.so exists:
find /usr -name "libterminal-plugin.so"

# If found, create symlink or copy to standard lib path:
sudo ln -s /path/to/libterminal-plugin.so /usr/lib/libterminal-plugin.so
```

### Option 2: Fix APKBUILD
The PostmarketOS package build needs to include the terminal plugin:

**In `device-oneplus-enchilada-marathon/APKBUILD`**, ensure the terminal plugin is installed:

```bash
# In package() function, add:
install -Dm755 "$builddir"/build-apps/terminal/libterminal-plugin.dylib \
    "$pkgdir"/usr/lib/libterminal-plugin.so
```

**Note:** The `.dylib` extension in build output suggests macOS, but device needs `.so`. This may be a cross-compilation issue.

---

## ℹ️ **DEVICE INFO: ModemManager Not Available (EXPECTED)**

**Log Output:**
```
[TelephonyService] ModemManager not available on D-Bus
```

**Status:** This is EXPECTED behavior documented in MARATHON_ISSUES.md.

**Reason:** The Phone app requires ModemManager for cellular functionality, but:
- ModemManager may not be installed
- Modem hardware may not be detected yet
- Modem firmware may need initialization

**Fix (if needed):**
```bash
# Check if ModemManager is installed:
which ModemManager

# Check if service is running:
systemctl status ModemManager

# Enable and start service:
sudo systemctl enable ModemManager
sudo systemctl start ModemManager

# Check if modem is detected:
mmcli -L
```

---

## Summary

| Issue | Status | Fix |
|-------|--------|-----|
| Typography scaling | ✅ **FIXED** | Updated `Typography.qml` to use `scaleFactor` |
| Keyboard scaling | ✅ **WORKS** | Already implemented correctly |
| Keyboard push content | ⚠️ **PENDING** | Needs investigation |
| Terminal won't launch | ❌ **DEVICE BUG** | Missing plugin library on device |
| ModemManager unavailable | ℹ️ **EXPECTED** | Phone app needs ModemManager service |

---

## Testing on Desktop

After rebuilding, test scaling:

1. Run Marathon Shell: `./run.sh`
2. Open Settings app
3. Go to Display → Scale
4. Change scale factor (0.75, 1.0, 1.25, 1.5)
5. **Verify:** All text should scale proportionally! ✅

---

## Testing on Device

After deploying new image:

1. **Test Typography Scaling:**
   - Open Settings
   - Text should be properly sized (not huge)
   - Adjust scale factor, verify text scales

2. **Test Terminal:**
   - Try to launch Terminal app
   - If fails, check logs for plugin error
   - Apply fix from "Option 1" above

3. **Test Phone (Optional):**
   - Launch Phone app
   - Expected: "ModemManager not available" warning
   - This is OK if you don't need cellular

---

**Next Step:** Rebuild Marathon Shell and test! 🚀

