# Marathon UI Library Migration Guide

**Target**: Replace the old Marathon Shell UI library with the new polished Marathon UI Library (v2.0)

**Source**: `/Users/patrick.quinn/Developer/personal/marathon-ui-library/MarathonUI/`  
**Destination**: `/Users/patrick.quinn/Developer/personal/Marathon-Shell/shell/qml/MarathonUI/`

---

## 📋 Migration Overview

This migration will:
1. **DELETE** the old `Marathon-Shell/shell/qml/MarathonUI/` directory
2. **COPY** the new `marathon-ui-library/MarathonUI/` directory into the shell
3. **UPDATE** `shell/CMakeLists.txt` to register all new components
4. **FIX** all app imports and component usage (50 files across 13 apps)
5. **UPDATE** shell components that use MarathonUI
6. **TEST** all apps and shell functionality

---

## 🗂️ Component Comparison

### What's NEW in Marathon UI v2.0

**Core Module:**
- ✅ `Icon.qml` (was scattered in old code)
- ✅ `MBreakpoints.qml` (responsive design singleton)
- ✅ `MResponsive.qml` (responsive container)
- ✅ `MGrid.qml` (responsive grid layout)
- ✅ `MContainer.qml` (constrained responsive container)

**Controls Module:**
- ✅ `MCheckbox.qml` (NEW - needed for forms)
- ✅ `MRadioButton.qml` (existed but improved)
- ✅ `MRadioGroup.qml` (NEW - radio button grouping)
- ✅ `MDropdown.qml` (NEW - proper dropdown vs old MDropDown)
- ✅ `MComboBox.qml` (NEW - editable combo box)

**Containers Module:**
- ✅ `MFormCard.qml` (NEW - forms container)
- ✅ `MFormField.qml` (NEW - form field wrapper)
- ✅ `MListTile.qml` (NEW - standardized list items)
- ✅ `MPanel.qml` (NEW - collapsible panels)
- ✅ `MPullToRefresh.qml` (NEW - pull-to-refresh)
- ✅ `MSwipeDelegate.qml` (NEW - swipeable list items)
- ✅ `MSettingsListItem.qml` (NEW - settings-specific list item)

**Navigation Module:**
- ✅ `MTabBar.qml` (NEW - tab navigation)
- ✅ `MSwipeView.qml` (NEW - swipeable pages)
- ✅ `MPageIndicator.qml` (NEW - page dots)

**Effects Module:**
- ✅ `MHaptics.qml` (NEW - haptic feedback singleton)
- ✅ `MRipple.qml` (improved ripple effect)

**Lists Module:**
- ✅ `MDivider.qml` (NEW - separators)

### What's REMOVED/CHANGED

**Old components to DELETE:**
- ❌ `MarathonUI/Core/MDropDown.qml` → Use `MDropdown.qml` (lowercase 'd')
- ❌ `MarathonUI/Core/MRadioButton.qml` → Moved to `Controls/MRadioButton.qml`
- ❌ `MarathonUI/Lists/MSectionHeader.qml` → Moved to `Containers/MSectionHeader.qml`
- ❌ `MarathonUI/Navigation/MTab Control.qml` (had space in name, malformed)
- ❌ `MarathonUI/Effects/MInset.qml` (unused, removed for performance)
- ❌ `MarathonUI/Effects/MOutset.qml` (unused, removed for performance)

---

## 🚀 Step-by-Step Migration

### Step 1: Backup Current State

```bash
cd /Users/patrick.quinn/Developer/personal/Marathon-Shell

# Create backup of current UI library
cp -r shell/qml/MarathonUI shell/qml/MarathonUI.backup

# Create backup of CMakeLists.txt
cp shell/CMakeLists.txt shell/CMakeLists.txt.backup
```

### Step 2: Delete Old UI Library

```bash
cd /Users/patrick.quinn/Developer/personal/Marathon-Shell

# Remove the old UI library completely
rm -rf shell/qml/MarathonUI
```

### Step 3: Copy New UI Library

```bash
# Copy the entire new MarathonUI directory
cp -r /Users/patrick.quinn/Developer/personal/marathon-ui-library/MarathonUI \
      /Users/patrick.quinn/Developer/personal/Marathon-Shell/shell/qml/
```

### Step 4: Update Shell CMakeLists.txt

**File**: `/Users/patrick.quinn/Developer/personal/Marathon-Shell/shell/CMakeLists.txt`

**Section A**: Update `QML_FILES` list (starting at line ~101)

Remove these old entries:
```cmake
qml/MarathonUI/Core/MDropDown.qml
qml/MarathonUI/Core/MRadioButton.qml
```

Add these new entries (after line 130):
```cmake
# NEW Core components
qml/MarathonUI/Core/Icon.qml
qml/MarathonUI/Core/MBreakpoints.qml
qml/MarathonUI/Core/MResponsive.qml
qml/MarathonUI/Core/MGrid.qml
qml/MarathonUI/Core/MContainer.qml
```

**Section B**: Update singleton registration (starting at line ~230)

Add to `SINGLETON_FILES`:
```cmake
qml/MarathonUI/Core/MBreakpoints.qml
qml/MarathonUI/Effects/MHaptics.qml
```

**Section C**: Update `marathon-ui-theme` module (line ~290)

Add to `QML_FILES`:
```cmake
qml/MarathonUI/Theme/MMotion.qml  # If not already there
```

**Section D**: Update `marathon-ui-core` module (line ~317)

Replace with:
```cmake
qt6_add_qml_module(marathon-ui-core
    URI MarathonUI.Core
    VERSION 1.0
    QML_FILES
        qml/MarathonUI/Core/MButton.qml
        qml/MarathonUI/Core/MIconButton.qml
        qml/MarathonUI/Core/MTextInput.qml
        qml/MarathonUI/Core/MTextArea.qml
        qml/MarathonUI/Core/MLabel.qml
        qml/MarathonUI/Core/MDateTimePicker.qml
        qml/MarathonUI/Core/MImageButton.qml
        qml/MarathonUI/Core/Icon.qml
        qml/MarathonUI/Core/MBreakpoints.qml
        qml/MarathonUI/Core/MResponsive.qml
        qml/MarathonUI/Core/MGrid.qml
        qml/MarathonUI/Core/MContainer.qml
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/shell/qml/MarathonUI/Core
)
```

**Section E**: Update `marathon-ui-controls` module (line ~334)

Replace with:
```cmake
qt6_add_qml_module(marathon-ui-controls
    URI MarathonUI.Controls
    VERSION 1.0
    QML_FILES
        qml/MarathonUI/Controls/MSlider.qml
        qml/MarathonUI/Controls/MToggle.qml
        qml/MarathonUI/Controls/MCheckbox.qml
        qml/MarathonUI/Controls/MRadioButton.qml
        qml/MarathonUI/Controls/MRadioGroup.qml
        qml/MarathonUI/Controls/MDropdown.qml
        qml/MarathonUI/Controls/MComboBox.qml
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/shell/qml/MarathonUI/Controls
)
```

**Section F**: Update `marathon-ui-lists` module (line ~344)

Replace with:
```cmake
qt6_add_qml_module(marathon-ui-lists
    URI MarathonUI.Lists
    VERSION 1.0
    QML_FILES
        qml/MarathonUI/Lists/MDivider.qml
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/shell/qml/MarathonUI/Lists
)
```

**Section G**: Update `marathon-ui-navigation` module (line ~354)

Replace with:
```cmake
qt6_add_qml_module(marathon-ui-navigation
    URI MarathonUI.Navigation
    VERSION 1.0
    QML_FILES
        qml/MarathonUI/Navigation/MTopBar.qml
        qml/MarathonUI/Navigation/MBottomBar.qml
        qml/MarathonUI/Navigation/MActionBar.qml
        qml/MarathonUI/Navigation/MNavigationPane.qml
        qml/MarathonUI/Navigation/MTabBar.qml
        qml/MarathonUI/Navigation/MSwipeView.qml
        qml/MarathonUI/Navigation/MPageIndicator.qml
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/shell/qml/MarathonUI/Navigation
)
```

**Section H**: Update `marathon-ui-containers` module (line ~303)

Replace with:
```cmake
qt6_add_qml_module(marathon-ui-containers
    URI MarathonUI.Containers
    VERSION 1.0
    QML_FILES
        qml/MarathonUI/Containers/MCard.qml
        qml/MarathonUI/Containers/MPage.qml
        qml/MarathonUI/Containers/MSection.qml
        qml/MarathonUI/Containers/MListItem.qml
        qml/MarathonUI/Containers/MApp.qml
        qml/MarathonUI/Containers/MLayer.qml
        qml/MarathonUI/Containers/MScrollView.qml
        qml/MarathonUI/Containers/MSectionHeader.qml
        qml/MarathonUI/Containers/MSwipeDelegate.qml
        qml/MarathonUI/Containers/MPullToRefresh.qml
        qml/MarathonUI/Containers/MFormCard.qml
        qml/MarathonUI/Containers/MFormField.qml
        qml/MarathonUI/Containers/MListTile.qml
        qml/MarathonUI/Containers/MPanel.qml
        qml/MarathonUI/Containers/MSettingsListItem.qml
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/shell/qml/MarathonUI/Containers
)
```

**Section I**: Update `marathon-ui-effects` module (line ~388)

Replace with:
```cmake
qt6_add_qml_module(marathon-ui-effects
    URI MarathonUI.Effects
    VERSION 1.0
    QML_FILES
        qml/MarathonUI/Effects/MRipple.qml
        qml/MarathonUI/Effects/MHaptics.qml
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/shell/qml/MarathonUI/Effects
)
```

**Section J**: Remove the old `MScrollView` addition (line ~399-403)

Delete this block:
```cmake
# Add MarathonUI.Containers MScrollView
qt6_target_qml_sources(marathon-ui-containers
    QML_FILES
        qml/MarathonUI/Containers/MScrollView.qml
)
```
*(MScrollView is now in the main module definition)*

---

### Step 5: Update Shell Components

**Files that import MarathonUI and need review:**

1. **`shell/qml/components/MarathonToggle.qml`**
   - Change: `import "../MarathonUI/Controls"` → `import MarathonUI.Controls`

2. **`shell/qml/components/MarathonQuickSettings.qml`**
   - Change: `import "../MarathonUI/Theme"` → `import MarathonUI.Theme`
   - Change: `import "../MarathonUI/Controls"` → `import MarathonUI.Controls`

3. **`shell/qml/components/*.qml`** (20 files)
   - Review all imports to use proper module paths
   - Replace `import "../MarathonUI/..."` with `import MarathonUI...`

4. **`shell/qml/components/Icon.qml`**
   - **DECISION NEEDED**: The new library has `MarathonUI/Core/Icon.qml`
   - Either:
     - A) Use `MarathonUI.Core.Icon` everywhere (RECOMMENDED)
     - B) Keep `components/Icon.qml` as an alias that imports `MarathonUI.Core.Icon`

---

### Step 6: Update All Apps

**All 13 apps need updates.** Here's the systematic approach:

#### Apps Using MarathonUI (50 files total):

**Settings App** (8 files):
- `apps/settings/SettingsApp.qml`
- `apps/settings/pages/*.qml`
- `apps/settings/components/*.qml`

**Phone App** (6 files):
- `apps/phone/PhoneApp.qml`
- `apps/phone/pages/*.qml`

**Browser App** (8 files):
- `apps/browser/BrowserApp.qml`
- `apps/browser/pages/*.qml`
- `apps/browser/components/*.qml`

**Messages App** (4 files):
- `apps/messages/MessagesApp.qml`
- `apps/messages/pages/*.qml`

**Notes App** (4 files):
- `apps/notes/NotesApp.qml`
- `apps/notes/pages/*.qml`
- `apps/notes/components/NoteItem.qml`

**Clock App** (5 files):
- `apps/clock/ClockApp.qml`
- `apps/clock/pages/*.qml`
- `apps/clock/components/AlarmItem.qml`

**Music App** (1 file):
- `apps/music/MusicApp.qml`

**Gallery App** (2 files):
- `apps/gallery/GalleryApp.qml`
- `apps/gallery/pages/PhotoViewerPage.qml`

**Calendar App** (3 files):
- `apps/calendar/CalendarApp.qml`
- `apps/calendar/pages/*.qml`

**Camera App** (1 file):
- `apps/camera/CameraApp.qml`

**Calculator App** (1 file):
- `apps/calculator/CalculatorApp.qml`

**Maps App** (1 file):
- `apps/maps/MapsApp.qml`

**Terminal App** (2 files):
- `apps/terminal/TerminalApp.qml`
- `apps/terminal/components/TerminalTab.qml`

#### Common Import Fixes Needed:

**BEFORE:**
```qml
import MarathonUI.Core
```

**AFTER (if using old MDropDown):**
```qml
import MarathonUI.Core
import MarathonUI.Controls  // For MDropdown (new)
```

**Component Name Changes:**
- `MDropDown` → `MDropdown` (Controls module)
- `MSectionHeader` → `MSectionHeader` (Containers module, not Lists)

---

### Step 7: Fix Component Usage

#### A. Icon Component

**OLD (shell's custom Icon):**
```qml
import "../components"
Icon {
    name: "wifi"
    size: 24
    color: Colors.textPrimary
}
```

**NEW (MarathonUI Icon):**
```qml
import MarathonUI.Core
Icon {
    name: "wifi"
    size: 24
    color: MColors.textPrimary
}
```

#### B. MDropDown → MDropdown

**OLD:**
```qml
import MarathonUI.Core
MDropDown {
    model: ["Option 1", "Option 2"]
}
```

**NEW:**
```qml
import MarathonUI.Controls
MDropdown {
    model: ["Option 1", "Option 2"]
}
```

#### C. MSectionHeader Location

**OLD:**
```qml
import MarathonUI.Lists
MSectionHeader {
    text: "Settings"
}
```

**NEW:**
```qml
import MarathonUI.Containers
MSectionHeader {
    text: "Settings"
}
```

#### D. MRadioButton Location

**OLD:**
```qml
import MarathonUI.Core
MRadioButton {
    text: "Option 1"
}
```

**NEW:**
```qml
import MarathonUI.Controls
MRadioButton {
    text: "Option 1"
    group: myRadioGroup
}
```

#### E. Haptics

**OLD (may not exist):**
```qml
// No consistent haptics
```

**NEW:**
```qml
import MarathonUI.Effects
MButton {
    text: "Tap Me"
    onClicked: MHaptics.lightImpact()
}
```

---

### Step 8: Update qmldir Files

Each module needs a proper `qmldir` file. The new library has them, but verify they're copied correctly.

**Example**: `shell/qml/MarathonUI/Core/qmldir`
```
module MarathonUI.Core
singleton MBreakpoints 1.0 MBreakpoints.qml
Icon 1.0 Icon.qml
MButton 1.0 MButton.qml
MContainer 1.0 MContainer.qml
MDateTimePicker 1.0 MDateTimePicker.qml
MGrid 1.0 MGrid.qml
MIconButton 1.0 MIconButton.qml
MImageButton 1.0 MImageButton.qml
MLabel 1.0 MLabel.qml
MResponsive 1.0 MResponsive.qml
MTextArea 1.0 MTextArea.qml
MTextInput 1.0 MTextInput.qml
```

---

### Step 9: Build and Test

```bash
cd /Users/patrick.quinn/Developer/personal/Marathon-Shell

# Clean build
rm -rf build
rm -rf build-apps

# Configure and build shell
mkdir build
cd build
cmake ..
cmake --build . -j$(sysctl -n hw.ncpu)

# Test the shell
./shell/marathon-shell-bin
```

#### Testing Checklist:

- [ ] Shell launches without QML errors
- [ ] Lock screen displays correctly
- [ ] App grid displays correctly
- [ ] Quick settings panel works
- [ ] Task switcher works
- [ ] Status bar displays correctly
- [ ] All 13 apps launch without errors
- [ ] Settings app navigates properly
- [ ] Phone app displays contacts/dialer
- [ ] Messages app displays conversations
- [ ] Browser app renders pages
- [ ] Notes app can create/edit notes
- [ ] Clock app alarms work
- [ ] Gallery app displays photos
- [ ] Camera app captures photos
- [ ] Calculator app calculates
- [ ] Calendar app displays events
- [ ] Maps app displays map
- [ ] Music app plays music
- [ ] Terminal app accepts input
- [ ] Navigation gestures work (back, home, task switch)
- [ ] Keyboard appears and works
- [ ] Notifications display correctly
- [ ] System HUD (volume, brightness) works
- [ ] Power menu works
- [ ] Rotation works
- [ ] Haptic feedback works (if device supports)

---

### Step 10: Cleanup

Once everything works:

```bash
cd /Users/patrick.quinn/Developer/personal/Marathon-Shell

# Remove backup
rm -rf shell/qml/MarathonUI.backup
rm shell/CMakeLists.txt.backup

# Clean up any .bak files in apps
find apps -name "*.qml.bak" -delete

# Commit the changes
git add .
git commit -m "feat: Migrate to Marathon UI Library v2.0

- Replace old UI library with polished Marathon UI v2.0
- Add new components: MPanel, MFormCard, MCheckbox, MRadioGroup, etc.
- Improve responsive design with MGrid, MContainer, MResponsive
- Add haptic feedback support via MHaptics singleton
- Update all 13 apps to use new component locations
- Update shell components to use proper module imports
- Align theme with BlackBerry 10 HIG (sharper corners, better contrast)
- Remove hover states for mobile-first design
- Fix padding and overflow issues across all panels"
```

---

## 🔧 Common Issues and Fixes

### Issue 1: "Cannot find module MarathonUI.Controls"

**Cause**: Module not registered in CMakeLists.txt or qmldir missing

**Fix**:
```bash
# Ensure qmldir exists
ls shell/qml/MarathonUI/Controls/qmldir

# Rebuild
cd build && cmake --build . -j$(sysctl -n hw.ncpu)
```

### Issue 2: "Type MDropdown unavailable"

**Cause**: Wrong import or typo (MDropDown vs MDropdown)

**Fix**:
```qml
// Change this:
import MarathonUI.Core
MDropDown { }

// To this:
import MarathonUI.Controls
MDropdown { }
```

### Issue 3: "ReferenceError: MHaptics is not defined"

**Cause**: Missing Effects module import

**Fix**:
```qml
import MarathonUI.Effects

// Now MHaptics is available as a singleton
MHaptics.lightImpact()
```

### Issue 4: "Property 'hovered' not found"

**Cause**: Old code trying to use hover states (removed in v2.0 for mobile)

**Fix**:
```qml
// Remove all references to 'hovered' property
// MCard, MListItem, etc. now only respond to 'pressed'
```

### Issue 5: "Text flowing off right edge"

**Cause**: Old hardcoded widths or missing responsive constraints

**Fix**:
```qml
// Ensure proper width constraint
Column {
    width: parent.width
    leftPadding: MSpacing.lg
    rightPadding: MSpacing.lg
    
    MLabel {
        width: parent.width - parent.leftPadding - parent.rightPadding
        text: "This text will wrap properly"
        wrapMode: Text.WordWrap
    }
}
```

### Issue 6: "Icon not found: compass.svg"

**Cause**: Icon name changed or not available in Lucide icon set

**Fix**:
```qml
// Check available icons in: shell/resources/images/icons/lucide/
// Use alternative: "map" instead of "compass"
Icon {
    name: "map"  // Instead of "compass"
}
```

---

## 📊 Migration Status Tracking

Create a checklist file to track progress:

**File**: `Marathon-Shell/MIGRATION_CHECKLIST.md`

```markdown
# Migration Checklist

## Phase 1: Preparation
- [ ] Backup current UI library
- [ ] Backup CMakeLists.txt
- [ ] Document custom components to preserve

## Phase 2: Copy Files
- [ ] Delete old MarathonUI directory
- [ ] Copy new MarathonUI directory
- [ ] Verify all qmldir files copied

## Phase 3: Update Build System
- [ ] Update shell/CMakeLists.txt QML_FILES
- [ ] Update singleton registrations
- [ ] Update all 8 QML module definitions
- [ ] Remove old component references

## Phase 4: Update Shell Components (20 files)
- [ ] MarathonToggle.qml
- [ ] MarathonQuickSettings.qml
- [ ] MarathonStatusBar.qml
- [ ] MarathonNavBar.qml
- [ ] MarathonLockScreen.qml
- [ ] MarathonMessagingHub.qml
- [ ] MarathonHub.qml
- [ ] MarathonTaskSwitcher.qml
- [ ] MarathonBottomBar.qml
- [ ] MarathonListItem.qml
- [ ] MarathonPinScreen.qml
- [ ] MarathonOOBE.qml
- [ ] MarathonSearch.qml
- [ ] NotificationToast.qml
- [ ] PowerMenu.qml
- [ ] QuickSettingsTile.qml
- [ ] MediaPlaybackManager.qml
- [ ] WiFiPasswordDialog.qml
- [ ] WaylandShellSurfaceItem.qml
- [ ] NativeAppWindow.qml

## Phase 5: Update Apps (13 apps, 50 files)
- [ ] Settings (8 files)
- [ ] Phone (6 files)
- [ ] Browser (8 files)
- [ ] Messages (4 files)
- [ ] Notes (4 files)
- [ ] Clock (5 files)
- [ ] Music (1 file)
- [ ] Gallery (2 files)
- [ ] Calendar (3 files)
- [ ] Camera (1 file)
- [ ] Calculator (1 file)
- [ ] Maps (1 file)
- [ ] Terminal (2 files)

## Phase 6: Testing
- [ ] Shell launches
- [ ] All apps launch
- [ ] Navigation works
- [ ] Forms work
- [ ] Settings pages work
- [ ] Visual consistency
- [ ] Performance acceptable
- [ ] No console errors
- [ ] Gestures work
- [ ] Keyboard works

## Phase 7: Cleanup
- [ ] Remove backup files
- [ ] Remove .bak files
- [ ] Update documentation
- [ ] Commit changes
```

---

## 🎯 Key Benefits After Migration

1. **Better Mobile UX**: Removed hover states, optimized for touch
2. **Responsive Design**: MGrid, MContainer, MBreakpoints for all screen sizes
3. **Consistent Forms**: MFormCard, MFormField for standardized input
4. **Better Lists**: MListTile, MSwipeDelegate, MSettingsListItem
5. **Haptic Feedback**: MHaptics singleton for tactile feedback
6. **Cleaner Code**: Proper module organization, no naming inconsistencies
7. **BB10 Polish**: Sharper corners, better contrast, depth/layering
8. **Performance**: Removed expensive effects, optimized animations
9. **Accessibility**: All components have proper roles and descriptions
10. **No Overflow**: All components properly constrained and responsive

---

## 📞 Need Help?

If you encounter issues during migration:

1. Check the "Common Issues and Fixes" section above
2. Review QML console errors carefully
3. Verify CMakeLists.txt module definitions match qmldir files
4. Test components in isolation using the showcase app
5. Compare old vs new component props/APIs in source files

---

**Good luck with the migration! 🚀**

