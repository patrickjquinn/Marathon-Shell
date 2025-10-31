# 🔴 CRITICAL FIXES NEEDED FOR MARATHON SHELL

**Date:** 2025-10-31  
**Device:** OnePlus 6 (enchilada)  
**Status:** Deployed but with critical issues

---

## 🚨 **P0 - BLOCKING ISSUES**

### 1. **Screen Blanking Broken (Power Button)**
**Location:** `shell/qml/services/DisplayManager.qml` + `shell/qml/services/SessionManager.qml`

**Problem:**
- Power button press turns screen off ✅
- Second press turns screen on briefly, then immediately off again ❌
- User cannot wake the device

**Root Cause:**
The platform-specific functions in `DisplayManager.qml` are only logging, not actually controlling the screen hardware.

**Fix Required:**
```qml
// DisplayManager.qml - Line ~177
function _platformSetScreenState(on) {
    if (Platform.isLinux && typeof DisplayManagerCpp !== 'undefined') {
        DisplayManagerCpp.setScreenState(on)  // THIS NEEDS TO WORK
    }
}
```

**C++ Side:**
```cpp
// shell/src/displaymanagercpp.cpp
void DisplayManagerCpp::setScreenState(bool on) {
    QFile blankFile("/sys/class/graphics/fb0/blank");
    if (!blankFile.open(QIODevice::WriteOnly | QIODevice::Text)) {
        qWarning() << "Failed to open /sys/class/graphics/fb0/blank";
        return;
    }
    QTextStream out(&blankFile);
    out << (on ? "0" : "4");  // 0=on, 4=off
    blankFile.close();
}
```

**And in SessionManager.qml:**
```qml
// SessionManager.qml - Add to lockSession()
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

### 2. **Terminal App Plugin Library Not Found**
**Location:** `apps/terminal/CMakeLists.txt`

**Problem:**
```
Error loading shared library libterminal-plugin.so: No such file or directory
(needed by /usr/share/marathon-apps/terminal/Terminal/libterminal-pluginplugin.so)
```

**Root Cause:**
The `libterminal-plugin.so` is installed to `/usr/share/marathon-apps/terminal/` but the dynamic linker doesn't search there. The QML plugin can't find its dependency.

**Fix Required:**
Add RPATH to the terminal plugin OR install the library to `/usr/lib/`:

**Option 1 - RPATH (Recommended):**
```cmake
# apps/terminal/CMakeLists.txt
set_target_properties(terminal-plugin PROPERTIES
    INSTALL_RPATH "$ORIGIN/../.."
    BUILD_WITH_INSTALL_RPATH TRUE
)
```

**Option 2 - Install to /usr/lib:**
```cmake
install(TARGETS terminal-plugin
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}  # /usr/lib instead of apps dir
)
```

---

### 3. **ModemManager D-Bus Connection Failed** ⚠️ **NOT OPTIONAL - MUST FIX**
**Location:** `shell/src/telephonyservice.cpp` (or wherever D-Bus is initialized)

**Problem:**
```
[CRITICAL] [MarathonShell] Failed to connect to D-Bus session bus!
[WARNING] [TelephonyService] ModemManager not available on D-Bus
```

**Root Cause:**
When run via greetd auto-login, the shell starts **before** the D-Bus session is fully established. The shell tries to connect immediately and fails.

**THIS IS CRITICAL:** Without D-Bus:
- No telephony (calls/SMS)
- No ModemManager integration
- No system service communication
- Core shell functionality broken

**Fix Required:**
Add retry logic with exponential backoff:

```cpp
// In TelephonyService or wherever D-Bus is initialized
void TelephonyService::connectToDBus() {
    int retries = 0;
    const int maxRetries = 10;
    const int baseDelay = 100; // ms
    
    while (retries < maxRetries) {
        QDBusConnection connection = QDBusConnection::sessionBus();
        if (connection.isConnected()) {
            qInfo() << "Connected to D-Bus session bus";
            // Initialize ModemManager interface
            return;
        }
        
        qWarning() << "D-Bus not available, retry" << retries + 1 << "of" << maxRetries;
        QThread::msleep(baseDelay * (1 << retries)); // Exponential backoff
        retries++;
    }
    
    qCritical() << "Failed to connect to D-Bus after" << maxRetries << "retries";
}
```

**Alternative:** Use `QDBusConnection::connectToBus()` with a connection event handler instead of immediate connection.

---

## ⚠️ **P1 - HIGH PRIORITY**

### 4. **UI Scaling Inconsistency**
**Location:** `shell/qml/core/Constants.qml`

**Problem:**
- Main UI elements scale correctly
- Settings icons, sliders, toggles, lock screen time are all different sizes
- No visual uniformity across the shell

**Root Cause:**
Components are not consistently using `Constants.scaleFactor` or are overriding sizes directly.

**Fix Required:**
Audit ALL QML files for hardcoded sizes. Ensure everything uses:

```qml
// Use scaleFactor everywhere
width: Constants.dp(48)  // NOT: width: 48
fontSize: Constants.dp(16)  // NOT: font.pixelSize: 16

// Check these files specifically:
// - shell/qml/components/MarathonLockScreen.qml (time display)
// - apps/settings/components/* (all settings components)
// - shell/qml/components/AppSwitcher.qml (home screen)
```

**Verify `baseDPI` is correct:**
```qml
// shell/qml/core/Constants.qml
readonly property real baseDPI: 160  // Should be 160 for OnePlus 6
```

---

### 5. **Missing Wallpaper Resources**
**Location:** Shell QRC resources

**Problem:**
```
QML QQuickImage: Cannot open: qrc:/wallpapers/wallpaper.jpg
```

**Root Cause:**
`MarathonLockScreen.qml` and `MarathonShell.qml` reference a wallpaper that doesn't exist in the QRC.

**Fix Required:**
Either:
1. Add the wallpaper to the QRC file
2. Remove the wallpaper references and use a solid color
3. Make wallpaper path configurable via `marathon-config.json`

---

## 📋 **P2 - MEDIUM PRIORITY**

### 6. **RT Scheduling Permissions** ⚠️ **NOT OPTIONAL - REQUIRED FOR MARATHON**
**Location:** `shell/src/rtscheduler.cpp`

**Problem:**
```
[WARNING] [RTScheduler] ⚠ No RT scheduling permissions (CAP_SYS_NICE or limits.conf required)
[WARNING] [RTScheduler]   Error: Function not implemented
```

**Root Cause:**
Either:
1. The kernel is NOT `PREEMPT_RT` (currently it's just `PREEMPT`)
2. The process doesn't have `CAP_SYS_NICE` capability

**THIS IS CRITICAL:** Marathon Shell REQUIRES RT scheduling for:
- Touch input thread priority (< 16ms latency target)
- Compositor render thread priority
- Audio thread priority (glitch-free playback)
- BB10-level responsiveness

**Fix Required:**
1. **Image side:** Deploy `linux-marathon` kernel with `CONFIG_PREEMPT_RT=y` (in progress)
2. **Shell side:** Ensure RT permissions are set via `/etc/security/limits.d/99-realtime.conf`:
   ```
   @realtime  - rtprio  99
   @realtime  - nice   -20
   @realtime  - memlock unlimited
   user       - rtprio  95
   user       - nice   -15
   ```
3. **Shell side:** Don't silently fail - WARN LOUDLY if RT fails:
   ```cpp
   if (!setRealtimePriority()) {
       qCritical() << "RT SCHEDULING FAILED - PERFORMANCE WILL BE DEGRADED!";
       qCritical() << "Marathon Shell requires PREEMPT_RT kernel and CAP_SYS_NICE";
       qCritical() << "Check: uname -a (should show PREEMPT_RT)";
       qCritical() << "Check: /etc/security/limits.d/99-realtime.conf";
   }
   ```

---

### 7. **WiFi Password Dialog Color Error**
**Location:** `apps/settings/components/WiFiPasswordDialog.qml:89`

**Problem:**
```
Unable to assign [undefined] to QColor
```

**Root Cause:**
A color property is being set to `undefined` instead of a valid color value.

**Fix Required:**
Check line 89 and ensure default colors are defined:

```qml
// WiFiPasswordDialog.qml
color: Theme.primaryColor ?? "#000000"  // Provide fallback
```

---

## 🔧 **DEVICE-SPECIFIC CONFIGURATION**

### OnePlus 6 Config
**Location:** `marathon-config.json`

Ensure these values are set for OnePlus 6:

```json
{
  "device": {
    "name": "OnePlus 6",
    "codename": "enchilada",
    "baseDPI": 160,
    "screenWidth": 1080,
    "screenHeight": 2280,
    "pixelDensity": 402
  },
  "display": {
    "scaleFactor": 1.0,
    "enableAutoScale": true
  },
  "hardware": {
    "backlight": "/sys/class/backlight/panel0-backlight/brightness",
    "framebuffer": "/sys/class/graphics/fb0/blank"
  }
}
```

---

## ✅ **TESTING CHECKLIST**

After fixes are applied, test:

- [ ] Power button locks and turns screen off
- [ ] Second power button press wakes device and shows lock screen
- [ ] Terminal app launches without errors
- [ ] ModemManager connects on startup (check journalctl)
- [ ] All UI elements are consistently scaled
- [ ] Settings sliders/toggles are properly sized
- [ ] Lock screen time display matches other text sizes
- [ ] WiFi settings work without color errors
- [ ] No D-Bus connection errors in logs

---

## 📝 **NOTES**

- All of these issues are **shell code bugs**, not PostmarketOS packaging issues
- The PostmarketOS image is correctly configured with all dependencies
- Once these fixes are in the shell, rebuild and redeploy

**When fixes are ready, notify the image maintainer to pull the latest shell and rebuild the image.**

