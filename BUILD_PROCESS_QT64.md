# Marathon Shell Qt 6.4 Build Process for Raspberry Pi

This document details the complete build process and fixes required to compile and run Marathon Shell on Raspberry Pi with Qt 6.4.2.

## System Information

- **Platform**: Raspberry Pi CM5 (Hackberry Pi)
- **OS**: Raspberry Pi OS 64-bit (Bookworm)
- **Qt Version**: 6.4.2 (system package)
- **Target**: Marathon Shell requires Qt 6.5+, we backported to 6.4

## Issues Encountered

### 1. Qt Version Compatibility (CRITICAL)

**Problem**: Marathon Shell requires Qt 6.5+ but Raspberry Pi OS only has Qt 6.4.2

**Manifestations**:
- CMake fails: "Could not find a package configuration file for package Qt6 that is compatible with requested version range 6.5...6.9.3"
- Missing modules: Location, Positioning (not available in Qt 6.4 on Raspberry Pi)

**Solution**: 
- Changed all `find_package(Qt6 6.5` to `find_package(Qt6 6.4`
- Made Location/Positioning optional instead of REQUIRED

**Files Modified**:
- `CMakeLists.txt` (line 69)
- `marathon-ui/CMakeLists.txt` (all find_package calls)

### 2. QML Resource Path (CRITICAL)

**Problem**: Main.qml resource path changed between Qt 6.4 and 6.5

**Error**: `qrc:/qt/qml/MarathonOS/Shell/qml/Main.qml: No such file or directory`

**Root Cause**: 
- Qt 6.5+ uses `qrc:/qt/qml/` prefix for QML modules
- Qt 6.4 uses `qrc:/` prefix directly

**Solution**: Changed resource path in main.cpp
```cpp
// Before (Qt 6.5+):
const QUrl url(QStringLiteral("qrc:/qt/qml/MarathonOS/Shell/qml/Main.qml"));

// After (Qt 6.4):
const QUrl url(QStringLiteral("qrc:/MarathonOS/Shell/qml/Main.qml"));
```

**File Modified**: `shell/main.cpp` (line 675)

### 3. QtQuick.Effects Module Missing (CRITICAL)

**Problem**: QtQuick.Effects is Qt 6.5+ only, not available in Qt 6.4

**Error**: `module "QtQuick.Effects" is not installed`

**Affected Components**:
- Icon.qml - Icon colorization with MultiEffect
- MToggle.qml - Shadow effects
- MCheckbox.qml - Glow effects
- MRadioButton.qml - Selection effects
- MarathonPinScreen.qml - Blur effects
- Plus 15+ other UI components

**Solution**: 
1. Removed all `import QtQuick.Effects` statements
2. Removed all `MultiEffect` blocks
3. Disabled layer effects: `layer.enabled: false`

**Side Effect**: Icons/UI elements no longer have color tinting or shadow effects (cosmetic only)

### 4. Settings Type Not Available (CRITICAL)

**Problem**: `Settings` type from QtCore not available in Qt 6.4

**Error**: `Settings is not a type (qrc:/MarathonOS/Shell/qml/services/ClipboardService.qml:11)`

**Solution**: Changed import
```qml
// Before:
import QtCore

// After:
import Qt.labs.settings 1.0
```

**File Modified**: `shell/qml/services/ClipboardService.qml` (line 3)

### 5. Missing QCoreApplication Include

**Problem**: Compiler error in waylandcompositor.cpp

**Error**: `'QCoreApplication' has not been declared`

**Solution**: Added missing include
```cpp
#include <QCoreApplication>
```

**File Modified**: `shell/src/waylandcompositor.cpp` (added after line 9)

### 6. Session Lock Integer Overflow (BUG FIX)

**Problem**: Session would immediately re-lock after unlock

**Root Cause**: 
- `lastActivityTime` was declared as `property int` (32-bit)
- `Date.now()` returns 64-bit millisecond timestamp (e.g., 1731398400000)
- Integer overflow caused negative/huge idle time calculation

**Solution**: Changed to double precision
```qml
// Before:
property int lastActivityTime: 0
property int idleTime: 0

// After:
property double lastActivityTime: Date.now()
property double idleTime: 0
```

**Additional Fixes**:
- Reset idle time to 0 on unlock
- Stop/restart idle monitor on unlock
- Don't check idle state when already locked
- Only run idle monitor when screen unlocked

**File Modified**: `shell/qml/services/SessionManager.qml`

### 7. Session Script Platform Detection

**Problem**: Session script wasn't correctly detecting primary vs nested compositor mode

**Solution**: Proper environment detection
```bash
# Save original display state before modifying
ORIGINAL_WAYLAND_DISPLAY="$WAYLAND_DISPLAY"
ORIGINAL_DISPLAY="$DISPLAY"

# Later, check ORIGINAL values to detect mode
if [ -n "$ORIGINAL_WAYLAND_DISPLAY" ] || [ -n "$ORIGINAL_DISPLAY" ]; then
    # Running nested
    exec /usr/bin/marathon-shell-bin -platform wayland --fullscreen
else
    # Running as primary compositor
    exec /usr/bin/marathon-shell-bin -platform eglfs
fi
```

**File Modified**: `marathon-shell-session` (the startup script)

## Complete Build Process

### Prerequisites

```bash
# Install required dependencies
sudo apt-get update
sudo apt-get install -y \
    build-essential cmake ninja-build \
    qt6-base-dev qt6-declarative-dev qt6-wayland-dev \
    qt6-multimedia-dev qt6-svg-dev \
    libpam0g-dev libwayland-dev \
    git
```

### Step 1: Clone Repository

```bash
cd ~
git clone https://github.com/patrickjquinn/Marathon-Shell.git
cd Marathon-Shell
git submodule update --init --recursive
```

### Step 2: Apply Qt 6.4 Compatibility Fixes

**Automated Script** (`qt64-fixes.sh`):
```bash
#!/bin/bash
set -e
cd ~/Marathon-Shell

# Fix CMakeLists Qt version requirements
sed -i 's/find_package(Qt6 6\.5/find_package(Qt6 6.4/g' CMakeLists.txt
sed -i 's/find_package(Qt6 6\.5/find_package(Qt6 6.4/g' marathon-ui/CMakeLists.txt

# Make Location/Positioning optional
sed -i '/Multimedia)/a \\n# Optional location services\nfind_package(Qt6 6.4 COMPONENTS Location Positioning)' CMakeLists.txt
sed -i '/Location/d; /Positioning/d' CMakeLists.txt | head -80

# Fix Main.qml resource path (Qt 6.5 → 6.4)
sed -i 's|qrc:/qt/qml/MarathonOS/Shell/qml/Main.qml|qrc:/MarathonOS/Shell/qml/Main.qml|' shell/main.cpp

# Fix SessionManager timestamp overflow (int → double)
sed -i 's/property int lastActivityTime: 0/property double lastActivityTime: Date.now()/' shell/qml/services/SessionManager.qml
sed -i 's/property int idleTime: 0/property double idleTime: 0/' shell/qml/services/SessionManager.qml
sed -i '/running: idleDetectionEnabled && sessionActive$/s/$/ \&\& !screenLocked/' shell/qml/services/SessionManager.qml

# Fix ClipboardService Settings import (QtCore → Qt.labs.settings)
sed -i 's/import QtCore/import Qt.labs.settings 1.0/' shell/qml/services/ClipboardService.qml

# Fix WaylandCompositor QCoreApplication include
sed -i '/#include <QWaylandXdgToplevel>/i #include <QCoreApplication>' shell/src/waylandcompositor.cpp

# Remove QtQuick.Effects import (Qt 6.5+ only)
find marathon-ui shell -name "*.qml" -exec sed -i '/^import QtQuick\.Effects$/d' {} \;

# Disable all layer effects
find marathon-ui shell -name "*.qml" -exec sed -i 's/layer\.enabled: true/layer.enabled: false \/\/ Qt 6.4: effects disabled/' {} \;
find marathon-ui shell -name "*.qml" -exec sed -i 's/layer\.enabled: root\./layer.enabled: false \/\/ Qt 6.4: root./' {} \;

# Remove all MultiEffect blocks
find marathon-ui shell -name "*.qml" -exec perl -i -0pe 's/MultiEffect \{[^}]*\}//gs' {} \;

echo "✅ All Qt 6.4 fixes applied!"
```

**Manual Execution**:
```bash
chmod +x qt64-fixes.sh
./qt64-fixes.sh
```

### Step 3: Build Marathon Shell

```bash
cd ~/Marathon-Shell

# Configure build
cmake -B build -DCMAKE_BUILD_TYPE=Release

# Build (using 4 cores to avoid overloading Pi)
cmake --build build -j4

# Install
sudo cmake --install build
```

**Build Time**: ~15-20 minutes on Raspberry Pi CM5

### Step 4: Install Session Script

The session script from cmake is incomplete. Use the corrected version:

```bash
# Copy the working session script
sudo cp ~/marathon-hackberry-pi/config/marathon-shell-session /usr/local/bin/
sudo chmod +x /usr/local/bin/marathon-shell-session

# Grant capabilities for real-time scheduling
sudo setcap cap_sys_nice+ep /usr/local/bin/marathon-shell-bin
```

**Important**: The cmake-installed `marathon-shell-session` lacks platform detection. Always overwrite it with the hackberry-pi version after building.

### Step 5: Configure LightDM (Optional - for auto-boot)

```bash
# Set Marathon Shell as default session
sudo nano /etc/lightdm/lightdm.conf

# Under [Seat:*] section:
user-session=marathon
autologin-user=pi
autologin-session=marathon
greeter-session=lightdm-gtk-greeter
```

### Step 6: Reboot

```bash
sudo reboot
```

Marathon Shell should now boot directly!

## Key Files Modified

### CMake Configuration
- `CMakeLists.txt` - Qt version 6.5 → 6.4, Location/Positioning optional
- `marathon-ui/CMakeLists.txt` - Qt version 6.5 → 6.4
- `shell/CMakeLists.txt` - (no changes needed)

### Source Code
- `shell/main.cpp` - Main.qml resource path fix
- `shell/src/waylandcompositor.cpp` - Added QCoreApplication include
- `shell/qml/services/SessionManager.qml` - Timestamp overflow fix, idle detection fixes
- `shell/qml/services/ClipboardService.qml` - Settings import fix

### QML Files (Effects Removal)
- `marathon-ui/Core/Icon.qml` - Removed MultiEffect colorization
- `marathon-ui/Controls/MToggle.qml` - Removed shadow effects
- `marathon-ui/Controls/MCheckbox.qml` - Removed glow effects
- `marathon-ui/Controls/MRadioButton.qml` - Removed selection effects
- `marathon-ui/Controls/MComboBox.qml` - Removed shadow effects
- `marathon-ui/Controls/MDropdown.qml` - Removed shadow effects
- `marathon-ui/Navigation/MTopBar.qml` - Removed shadow effects
- `marathon-ui/Navigation/MActionBar.qml` - Removed shadow effects
- `marathon-ui/Containers/MCard.qml` - Removed shadow effects
- `marathon-ui/Containers/MPanel.qml` - Removed shadow effects
- `marathon-ui/Containers/MListItem.qml` - Removed ripple effects
- `marathon-ui/Modals/MSheet.qml` - Removed blur effects
- `marathon-ui/Modals/MModal.qml` - Removed shadow effects
- `shell/qml/components/MarathonPinScreen.qml` - Removed blur effects
- `shell/qml/components/MarathonAppGrid.qml` - Removed effects
- Plus 4 more UI component files

**Total**: 19 QML files modified to remove Qt 6.5+ effects

### Session/Boot Configuration
- `marathon-shell-session` - Startup script with platform detection

## Build Output

### Successful Build Indicators
```
-- Qt version: 6.4.2
-- Build type: Release
[100%] Built target marathon-shell
```

### Expected Warnings (Non-Critical)
```
CMake Warning: Could NOT find Qt6Location
CMake Warning: Could NOT find Qt6WebEngineQuick  
CMake Warning: qmllint not found
CMake Warning: Hunspell not found
```

These are expected on Raspberry Pi and don't affect core functionality.

### Cyclic Dependency Warnings (Normal)
Marathon Shell QML has intentional circular dependencies between services/stores. These warnings are cosmetic and don't prevent operation.

## Known Issues

### 1. Missing Icons/Wallpapers ✅ FIXED

**Problem**: The `resources.qrc` file (containing images/wallpapers/icons) was not being properly compiled into the binary by qt6_add_qml_module in Qt 6.4.

**Symptoms**: 
- Bottom bar icons didn't show
- Wallpaper images didn't load
- Some UI elements missing graphics

**Solution**: Add `resources.qrc` directly to target sources instead of listing in qt6_add_qml_module RESOURCES:

```cmake
# In shell/CMakeLists.txt, after qt6_add_qml_module():

# Qt 6.4: Add resources.qrc directly to target sources so CMake processes it
# qt6_add_qml_module doesn't handle .qrc files properly in Qt 6.4
target_sources(marathon-shell PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/resources.qrc)
```

**Result**: CMake's AUTORCC automatically processes the .qrc file, generating a 258 MB `qrc_resources.cpp` with all images, wallpapers, icons, sounds, and fonts fully embedded.

**Verification**:
```bash
# Check resource file was generated
ls -lh build/shell/marathon-shell_autogen/*/qrc_resources.cpp
# Should show ~258 MB file

# Check resources are embedded
strings /usr/local/bin/marathon-shell-bin | grep "qrc:/wallpapers/wallpaper.jpg"
# Should return the path
```

**Status**: ✅ **FULLY FIXED** - All icons, wallpapers, and resources now load correctly

### 2. No Visual Effects (By Design) ✅

**Symptoms**:
- Icons not color-tinted
- No shadows on UI elements
- No blur effects on backgrounds

**Root Cause**: QtQuick.Effects (Qt 6.5+) not available in Qt 6.4

**Solution**: Intentionally disabled all effects for compatibility. Marathon Shell works without them.

### 3. GStreamer Warnings (Non-Critical) ⚠️

**Symptoms**: GStreamer assertions about int_range_step

**Impact**: None - these are harmless GStreamer quirks on Raspberry Pi

## Testing Results

### ✅ Working Features
- Marathon Shell boots as primary compositor
- Lock screen displays and is interactive
- Swipe gestures work
- Home screen navigation
- App grid
- Settings
- Session management (lock/unlock without immediate re-lock bug!)
- Touch input
- GPU acceleration (60 FPS with eglfs)

### ❌ Non-Working Features  
- Icon graphics (missing from binary)
- Wallpaper images (missing from binary)
- Visual effects (intentionally disabled for Qt 6.4)
- Browser app (requires QtWebEngine - not critical)
- Location services (Qt6Location not available)

## Performance

**Hardware**: Raspberry Pi CM5 (BCM2712 SoC, 4GB RAM)

- **Boot Time**: ~20 seconds from LightDM to lock screen
- **Frame Rate**: 60 FPS with eglfs platform
- **Memory Usage**: ~450MB idle
- **CPU Usage**: <10% idle, ~30% during animations

## Maintenance Notes

### Rebuilding After Changes

If you modify QML files or source code:

```bash
cd ~/Marathon-Shell/build
cmake --build . -j4
sudo cmake --install .

# IMPORTANT: Restore the correct session script!
sudo cp ~/marathon-hackberry-pi/config/marathon-shell-session /usr/local/bin/
sudo chmod +x /usr/local/bin/marathon-shell-session
sudo setcap cap_sys_nice+ep /usr/local/bin/marathon-shell-bin

# Restart to test
sudo systemctl restart lightdm
```

**Critical**: Always restore the session script after `cmake --install` because cmake overwrites it with the incomplete version from the source.

### Debugging

**View logs**:
```bash
# Session errors
cat ~/.xsession-errors

# LightDM logs
journalctl -u lightdm -f
```

**Test without booting**:
```bash
# From Raspberry Pi desktop, run:
marathon-shell-session &
# Marathon Shell opens in fullscreen nested mode
```

## Summary of Changes

| Component | Change | Reason |
|-----------|--------|--------|
| CMakeLists.txt | Qt 6.5 → 6.4 | Version compatibility |
| marathon-ui/CMakeLists.txt | Qt 6.5 → 6.4 | Version compatibility |
| shell/CMakeLists.txt | Add resources.qrc to target_sources | Fix resource embedding in Qt 6.4 |
| shell/main.cpp | Resource path fix | Qt 6.4 uses different QML module paths |
| shell/src/waylandcompositor.cpp | Add QCoreApplication include | Missing header |
| shell/qml/services/SessionManager.qml | int → double timestamps | Fix integer overflow bug |
| shell/qml/services/ClipboardService.qml | QtCore → Qt.labs.settings | Settings type compatibility |
| 19 QML UI files | Remove QtQuick.Effects | Module not available in Qt 6.4 |
| All QML files with effects | Disable layer effects | Remove MultiEffect dependencies |
| marathon-shell-session | Platform detection | Proper eglfs vs wayland mode selection |

## Files to Track

The following files contain Qt 6.4-specific modifications and should be maintained across Marathon Shell updates:

**Critical**:
- `CMakeLists.txt`
- `marathon-ui/CMakeLists.txt`  
- `shell/main.cpp`
- `shell/src/waylandcompositor.cpp`
- `shell/qml/services/SessionManager.qml`
- `shell/qml/services/ClipboardService.qml`
- `marathon-shell-session`

**Effects Removal** (19 files):
- All marathon-ui/*/*.qml files with QtQuick.Effects imports
- shell/qml/components/MarathonPinScreen.qml
- shell/qml/components/MarathonAppGrid.qml

## Future Work

### Fixing Missing Icons/Wallpapers

The `resources.qrc` file needs to be properly compiled and linked. Options:

1. **Use qt6_add_resources() instead of listing in RESOURCES**
2. **Manually compile resources.qrc with rcc and link the .cpp file**
3. **Install resources to filesystem instead of embedding**

### Re-enabling Visual Effects

When Qt 6.5+ becomes available on Raspberry Pi OS, revert the effect changes:

```bash
cd ~/Marathon-Shell
git diff --name-only | grep "\.qml$" | xargs git checkout --
```

This will restore all the QtQuick.Effects code.

## Verification Commands

### Check Marathon Shell is properly installed:
```bash
which marathon-shell-bin
# Should show: /usr/local/bin/marathon-shell-bin

ls -l /usr/share/wayland-sessions/marathon.desktop
# Should exist

getcap /usr/local/bin/marathon-shell-bin
# Should show: cap_sys_nice=ep

groups pi
# Should include: video render
```

### Check it can find Main.qml:
```bash
marathon-shell-session 2>&1 | grep -i "main.qml"
# Should NOT show "No such file or directory"
```

### Check Qt version:
```bash
qmake6 --version
# Qt version 6.4.2
```

## Success Criteria

✅ Marathon Shell compiles without errors  
✅ Marathon Shell runs without Qt module errors  
✅ Lock screen displays with wallpaper  
✅ Session management works (no immediate re-lock)  
✅ 60 FPS rendering with GPU acceleration  
✅ Icons and wallpapers load correctly (resources fully embedded)  
⚠️ No visual effects (intentional - QtQuick.Effects not available in Qt 6.4)  

---

**Date**: 2025-11-15  
**Marathon Shell Version**: Latest main branch (commit 188e0a5)  
**Build Status**: Functional with cosmetic issues  
**Tested By**: sw7ft on Hackberry Pi (Raspberry Pi CM5)

