# Quick Settings & Settings Analysis

## Executive Summary
After comprehensive analysis of Marathon's Settings app and Quick Settings system, I've identified gaps in functionality and opportunities for improvement. This document outlines current state, missing features, and implementation plan.

---

## Current State

### Settings Pages Available
1. **WiFi** - Network connections, saved networks
2. **Bluetooth** - Device pairing and management
3. **Cellular** - Mobile network settings, data toggle
4. **Display** - Brightness, rotation lock, auto-brightness, screen timeout, status bar clock position, UI scale, wallpaper
5. **Sound** - Volume controls, ringtones, alarms, per-app volume (PipeWire)
6. **Notifications** - DND mode, lock screen notifications, notification sound
7. **Storage** - Disk usage
8. **About** - Device info, OS version
9. **App Manager** - App installation/management
10. **Hidden Apps** - Filter apps from launcher
11. **Default Apps** - Set default handlers
12. **App Sort** - App grid layout and sorting

### Current Quick Settings Tiles (12 tiles)
| Tile ID | Type | Label | Backend |
|---------|------|-------|---------|
| `settings` | Link | Settings | N/A (launches app) |
| `lock` | Link | Lock device | SessionStore.lock() |
| `rotation` | Toggle | Rotation lock | DisplayManager |
| `wifi` | Toggle | Wi-Fi/Ethernet | NetworkManager |
| `bluetooth` | Toggle | Bluetooth | NetworkManager |
| `flight` | Toggle | Flight mode | NetworkManager |
| `cellular` | Toggle | Mobile network | ModemManagerCpp |
| `notifications` | Toggle | DND/Silent | AudioManager |
| `torch` | Toggle | Flashlight | FlashlightManager |
| `alarm` | Link | Alarm | Clock app |
| `battery` | Toggle | Battery saving | PowerManager |
| `monitor` | Info | Device monitor | SystemStatusStore |

### Available C++ Managers
- **NetworkManagerCpp** - WiFi, Bluetooth, Ethernet, Airplane Mode, Hotspot (?)
- **PowerManagerCpp** - Battery, power profiles, suspend/shutdown
- **DisplayManagerCpp** - Brightness, rotation lock, auto-brightness, screen timeout
- **AudioManagerCpp** - Volume, DND, per-app volume
- **ModemManagerCpp** - Cellular modem, mobile data
- **LocationManager** - GPS/Location services ✅
- **HapticManager** - Vibration feedback ✅
- **SensorManagerCpp** - Device sensors
- **RotationManager** - Screen rotation
- **BluetoothManager** - Bluetooth stack
- **SettingsManager** - Persistent settings storage

---

## Gaps & Missing Functionality

### 1. Settings Available but NO Quick Tile
| Feature | Settings Page | Manager | Priority |
|---------|---------------|---------|----------|
| **Auto-Brightness** | Display page (toggle) | DisplayManager.autoBrightnessEnabled | ✅ HIGH |
| **Location/GPS** | Not in settings | LocationManager.enabled | ✅ HIGH |
| **Hotspot/Tethering** | Not in settings | NetworkManager (?) | ✅ MEDIUM |

### 2. Missing from Both Settings AND Quick Tiles
| Feature | Description | Implementation | Priority |
|---------|-------------|----------------|----------|
| **Night Light** | Blue light filter | DisplayManager + shader | ✅ HIGH |
| **Vibration Toggle** | System-wide vibration | HapticManager | ✅ MEDIUM |
| **Screenshot** | Quick capture | Wayland capture API | ✅ MEDIUM |
| **Screen Recording** | Video capture | Complex - future | 🔴 LOW |
| **Focus Mode** | App filtering | Complex - future | 🔴 LOW |
| **Dark Mode** | Theme toggle | Already exists? | ⚠️ CHECK |

### 3. Tile Customization
**Currently:** All 12 tiles always visible (if available)
**Proposed:** User can:
- Enable/disable tiles
- Reorder tiles (drag & drop)
- Reset to defaults

---

## Implementation Plan

### Phase 1: Add Missing Toggles (Existing Managers)
**Goal:** Expose existing functionality as Quick Settings tiles

#### 1.1 Auto-Brightness Tile
- **Backend:** `DisplayManager.autoBrightnessEnabled` (already exists)
- **Frontend:** Add to `allTiles` in MarathonQuickSettings.qml
- **SystemControlStore:** Add `toggleAutoBrightness()`
- **Icon:** `sun-moon` or `zap`

#### 1.2 Location/GPS Tile
- **Backend:** `LocationManager.enabled` (already exists)
- **Frontend:** Add to `allTiles`
- **SystemControlStore:** Add `isLocationOn` + `toggleLocation()`
- **Icon:** `map-pin` or `navigation`
- **Deep Link:** Settings > Location (new page needed)

#### 1.3 Hotspot/Tethering Tile
- **Backend:** Check `NetworkManagerCpp` for hotspot support
- **Frontend:** Add to `allTiles`
- **SystemControlStore:** Add `isHotspotOn` + `toggleHotspot()`
- **Icon:** `wifi-tethering` or `share-2`
- **Deep Link:** Settings > Hotspot (new page needed)

#### 1.4 Vibration Tile
- **Backend:** `HapticManager` (exists, check for enable/disable)
- **Frontend:** Add to `allTiles`
- **SystemControlStore:** Add `isVibrationOn` + `toggleVibration()`
- **Icon:** `vibrate`
- **Deep Link:** Settings > Sound > Vibration

---

### Phase 2: Add New Features
**Goal:** Implement missing system features

#### 2.1 Night Light (Blue Light Filter)
**Backend (C++):**
- Add `DisplayManagerCpp::nightLightEnabled` property
- Add `DisplayManagerCpp::nightLightTemperature` (2700K-6500K)
- Add `DisplayManagerCpp::nightLightSchedule` (sunset, time-based, manual)
- Implement using:
  - **Option A:** Wayland color correction protocol (if available)
  - **Option B:** Qt GraphicsEffect on compositor
  - **Option C:** Shader on QML layer

**Frontend (QML):**
- Add tile to Quick Settings
- Add Settings > Display > Night Light page
- Schedule integration (sunset time from location)

**Settings UI:**
- Toggle: Enable/Disable
- Slider: Color temperature (warm ↔ cool)
- Schedule: Off, Sunset to Sunrise, Custom times

#### 2.2 Screenshot Tool
**Backend (C++):**
- Add `MarathonSystemService::captureScreen()`
- Use Wayland compositor screenshot API
- Save to `~/Pictures/Screenshots/` or XDG Pictures
- Generate notification with preview

**Frontend (QML):**
- Add action tile to Quick Settings
- Haptic feedback on capture
- Toast notification with thumbnail
- Keyboard shortcut (Print Screen)

---

### Phase 3: Tile Customization System
**Goal:** Let users customize their Quick Settings

#### 3.1 Backend (SettingsManager)
**Properties:**
```cpp
// settingsmanager.h
Q_PROPERTY(QStringList enabledQuickSettingsTiles READ enabledQuickSettingsTiles WRITE setEnabledQuickSettingsTiles NOTIFY enabledQuickSettingsTilesChanged)
Q_PROPERTY(QStringList quickSettingsTileOrder READ quickSettingsTileOrder WRITE setQuickSettingsTileOrder NOTIFY quickSettingsTileOrderChanged)
```

**Default Configuration:**
```json
{
  "quickSettings": {
    "enabledTiles": ["wifi", "bluetooth", "flight", "cellular", "rotation", "torch", "notifications", "battery", "autobrightness", "location", "settings", "lock"],
    "tileOrder": ["wifi", "bluetooth", "flight", "cellular", "rotation", "torch", "notifications", "battery", "autobrightness", "location", "settings", "lock"]
  }
}
```

#### 3.2 Frontend (MarathonQuickSettings.qml)
**Update tile filtering:**
```qml
property var visibleTiles: {
    var enabled = SettingsManagerCpp.enabledQuickSettingsTiles
    var order = SettingsManagerCpp.quickSettingsTileOrder
    var result = []
    
    // First, add tiles in custom order
    for (var i = 0; i < order.length; i++) {
        var tileId = order[i]
        if (enabled.indexOf(tileId) !== -1) {
            var tile = allTiles.find(t => t.id === tileId)
            if (tile && tile.available) {
                result.push(tile)
            }
        }
    }
    
    // Then add any new tiles not in order list
    for (var j = 0; j < allTiles.length; j++) {
        if (order.indexOf(allTiles[j].id) === -1 && 
            enabled.indexOf(allTiles[j].id) !== -1 && 
            allTiles[j].available) {
            result.push(allTiles[j])
        }
    }
    
    return result
}
```

#### 3.3 Settings Page (QuickSettingsCustomizationPage.qml)
**UI Components:**
- Section 1: **Enabled Tiles** (drag to reorder)
  - Visual tiles with drag handles
  - Toggle to disable (moves to "Available" section)
  
- Section 2: **Available Tiles**
  - Disabled tiles
  - Tap to enable (adds to end of enabled list)
  
- Action Button: **Reset to Defaults**

**Interaction:**
- Drag & drop to reorder (use `DragHandler` + `Drag.source`)
- Tap tile to toggle enabled/disabled
- Changes save immediately (no "Apply" button needed)

---

## Tile Priority Matrix

### Must Have (Phase 1)
1. ✅ Auto-Brightness
2. ✅ Location/GPS
3. ✅ Tile Customization (enable/disable)

### Should Have (Phase 2)
4. ✅ Night Light
5. ✅ Screenshot
6. ✅ Hotspot/Tethering
7. ✅ Vibration toggle
8. ✅ Tile Reordering (drag & drop)

### Could Have (Future)
9. 🔴 Screen Recording
10. 🔴 Focus Mode
11. 🔴 NFC toggle
12. 🔴 Mobile Data toggle (separate from Cellular modem)

---

## Technical Notes

### Tile Data Structure
```qml
{
    id: "autobrightness",              // Unique identifier
    icon: "sun-moon",                  // Lucide icon name
    label: "Auto-brightness",          // Display name
    active: DisplayManager.autoBrightnessEnabled,  // Current state
    available: true,                   // Hardware/software availability
    subtitle: "",                      // Optional secondary text
    trigger: updateTrigger             // Force model refresh
}
```

### Tile Types
1. **Toggle** - On/off state (WiFi, Bluetooth, Rotation, etc.)
2. **Link** - Navigation (Settings, Lock, Alarm)
3. **Action** - One-time action (Screenshot)
4. **Info** - Display only (Monitor)

### Visual Distinction (Current Design)
- **Toggle tiles:** Split design (icon in square box + label in rectangle)
  - OFF: Gray elevated surface
  - ON: Teal icon box + teal border + teal bottom bar
- **Link/Action tiles:** Solid card (icon + label side-by-side)

---

## Files to Modify

### C++ Backend
1. `shell/src/displaymanagercpp.h/cpp` - Add Night Light
2. `shell/src/networkmanagercpp.h/cpp` - Check/add Hotspot
3. `shell/src/hapticmanager.h/cpp` - Add system enable/disable
4. `shell/src/settingsmanager.h/cpp` - Add tile customization
5. `shell/src/dbus/marathonsystemservice.h/cpp` - Add screenshot

### QML Frontend
6. `shell/qml/stores/SystemControlStore.qml` - Add new toggle functions
7. `shell/qml/components/MarathonQuickSettings.qml` - Add new tiles + filtering
8. `apps/settings/pages/DisplayPage.qml` - Add Night Light section
9. `apps/settings/pages/SettingsMainPage.qml` - Add link to QS customization
10. `apps/settings/pages/QuickSettingsPage.qml` - **NEW** Tile customization UI
11. `apps/settings/pages/LocationPage.qml` - **NEW** Location settings
12. `apps/settings/pages/HotspotPage.qml` - **NEW** Hotspot settings

---

## Next Steps
1. Review this analysis with user
2. Get approval for phases and priorities
3. Begin implementation starting with Phase 1
4. Build and test incrementally after each tile addition
5. User testing and feedback after Phase 2
6. Iterate on customization UX in Phase 3

