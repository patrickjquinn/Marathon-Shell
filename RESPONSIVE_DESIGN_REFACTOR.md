# Responsive Design System Refactor

## Overview

Convert Marathon Shell from hardcoded pixel values to a fully responsive design system that adapts to any screen size.

## Current State

- **286 hardcoded pixel values** across **50 files**
- No responsive sizing
- Designed for 720x1280 (iPhone SE/BB10 screen)
- Will break on tablets, desktops, larger phones

## Target State

- **0 hardcoded pixels** (except Constants.qml base calculations)
- Fully responsive across 480p → 4K
- Scales intelligently based on screen size
- Performance optimized (no layout thrashing)

## Implementation Strategy

###  1. Create Responsive Unit System

**File:** `shell/qml/core/Constants.qml`

- Add screen dimension properties
- Create `unit` system (1 unit = 1% of screen height)
- Add scale factors for small/large screens
- Convert all constants to relative units

### 2. Update All Components (50 files)

Replace hardcoded values with Constants properties:

- `width: 300` → `width: Constants.cardWidth`
- `height: 100` → `height: Constants.bottomBarHeight`
- `spacing: 20` → `spacing: Constants.spacingLarge`
- `radius: 12` → `radius: Constants.borderRadiusMedium`

### 3. Initialize Screen Size in Shell

**File:** `shell/qml/MarathonShell.qml`

```qml
Component.onCompleted: {
    Constants.updateScreenSize(shell.width, shell.height, Screen.pixelDensity * 25.4)
    UIStore.shellRef = shell
}
```

### 4. Handle Window Resize

Add connections for desktop/tablet resize events.

## Files to Update (All 50)

### Core
- `shell/qml/core/Constants.qml` ✓ (create system)
- `shell/qml/MarathonShell.qml` (initialize)

### Components (26 files)
- MarathonAppGrid.qml
- MarathonBottomBar.qml
- MarathonHub.qml
- MarathonLockScreen.qml
- MarathonNavBar.qml
- MarathonPeek.qml
- MarathonPinScreen.qml
- MarathonQuickSettings.qml
- MarathonSearch.qml
- MarathonStatusBar.qml
- MarathonTaskSwitcher.qml
- MarathonToggle.qml
- MarathonMessagingHub.qml
- MarathonListItem.qml
- QuickSettingsTile.qml
- Icon.qml
- SystemHUD.qml
- ConnectionToast.qml
- NotificationToast.qml
- MediaPlaybackManager.qml
- ClipboardManager.qml
- ShareSheet.qml
- AppContextMenu.qml
- ScreenshotPreview.qml
- BackGestureIndicator.qml
- MarathonAppWindow.qml

### UI Library (15 files)
- MarathonUI/Containers/MPage.qml
- MarathonUI/Containers/MListItem.qml
- MarathonUI/Lists/MListItem.qml
- MarathonUI/Controls/MSlider.qml
- MarathonUI/Controls/MToggle.qml
- components/ui/PageIndicator.qml
- components/ui/SettingsListItem.qml
- components/ui/Input.qml
- components/ui/Button.qml
- components/ui/ListPickerModal.qml
- components/ui/TextInputModal.qml
- components/ui/StorageDetailsModal.qml
- components/layout/Section.qml
- components/navigation/InertiaNavBar.qml
- theme/Layout.qml

### Settings App (9 files)
- apps/settings/SettingsApp.qml
- apps/settings/pages/SettingsMainPage.qml
- apps/settings/pages/WiFiPage.qml
- apps/settings/pages/BluetoothPage.qml
- apps/settings/pages/DisplayPage.qml
- apps/settings/pages/SoundPage.qml
- apps/settings/pages/StoragePage.qml
- apps/settings/pages/AboutPage.qml
- apps/settings/components/SettingsPageTemplate.qml

## Responsive Constants Structure

```qml
// Base dimensions (set by shell)
property real screenWidth: 720
property real screenHeight: 1280
property real dpi: 320

// Unit system
readonly property real unit: screenHeight / 100  // 1% of height

// Scale factors
readonly property bool isSmallScreen: screenHeight < 800
readonly property bool isLargeScreen: screenHeight > 1600
readonly property real scaleFactor: isSmallScreen ? 0.85 : (isLargeScreen ? 1.15 : 1.0)

// All sizes expressed in units
readonly property real statusBarHeight: unit * 3.4 * scaleFactor
readonly property real bottomBarHeight: unit * 7.8 * scaleFactor
readonly property real appIconSize: unit * 5.6 * scaleFactor
// ... etc
```

## Performance Considerations

1. **Cached calculations** - All Constants are readonly, calculated once
2. **No binding loops** - Properties don't reference each other cyclically
3. **Integer rounding** - Use `Math.round()` for pixel-perfect rendering
4. **Minimum sizes** - Use `Math.max()` for borders/thin lines (min 1px)

## Testing Matrix

| Screen Size | Resolution | DPI | Status |
|-------------|------------|-----|--------|
| BB10 / iPhone SE | 720x1280 | 320 | ✓ Current |
| iPhone 13 | 1170x2532 | 460 | ⏳ To test |
| iPad | 1536x2048 | 264 | ⏳ To test |
| Desktop HD | 1920x1080 | 96 | ⏳ To test |
| Desktop 4K | 3840x2160 | 192 | ⏳ To test |

## Implementation Order

1. ✅ Create responsive Constants.qml
2. ⏳ Update MarathonShell.qml to initialize
3. ⏳ Update critical UI (StatusBar, NavBar, BottomBar)
4. ⏳ Update containers (TaskSwitcher, AppGrid, Hub)
5. ⏳ Update UI library components
6. ⏳ Update Settings app
7. ⏳ Test on multiple screen sizes
8. ⏳ Polish and fine-tune scale factors

## Time Estimate

- Constants.qml refactor: 30 min
- Shell initialization: 15 min
- 50 files @ ~5 min each: 4-5 hours
- Testing & polish: 1 hour

**Total: 5-6 hours** of focused work

## Success Criteria

- ✅ No hardcoded pixels (except in Constants calculations)
- ✅ Scales beautifully from 480p to 4K
- ✅ No performance regression
- ✅ All gestures work at any size
- ✅ Text remains readable at all sizes
- ✅ Touch targets remain accessible (min 44px)

