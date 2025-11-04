# Marathon Shell - Technical Debt Audit Report
## Design System Duplication & Technical Debt Analysis

**Date:** 2024
**Scope:** Full codebase audit for design system duplication, discrepancies, and technical debt

---

## 🚨 CRITICAL ISSUES FOUND

### 1. **DUPLICATE DESIGN SYSTEM DEFINITIONS**

#### A. Color Systems (3 separate implementations!)
- ✅ **ACTIVE**: `shell/qml/MarathonUI/Theme/MColors.qml` (90 lines, 68 color properties)
- ❌ **LEGACY**: `shell/qml/theme/Colors.qml` (30 lines, 22 color properties + 4 radius properties)
- ❌ **BACKUP**: `shell/qml/MarathonUI.backup/Theme/MColors.qml` (should be deleted)

**Problem:**
- Old `theme/Colors.qml` is STILL REGISTERED in `shell/qml/qmldir` line 18
- 125 files still reference `Colors.` instead of `MColors.`
- Two different color palettes with conflicting values:
  - Legacy: `accent: "#14B8A6"` vs New: `marathonTeal: "#00bfa5"`
  - Legacy: `textSecondary: "#999999"` vs New: `textSecondary: "#6a6a6a"`
  - Legacy: `surface: "#1A1A1A"` vs New: `surface: "#0d0d0e"`

**Impact:** HIGH - Causes visual inconsistencies across the shell

---

#### B. Typography Systems
- ✅ **ACTIVE**: `shell/qml/MarathonUI/Theme/MTypography.qml` (scaled, uses Slate font)
- ❌ **BACKUP**: `shell/qml/MarathonUI.backup/Theme/MTypography.qml` (should be deleted)

**Status:** Mostly migrated, but backup should be removed

---

#### C. Spacing Systems
- ✅ **ACTIVE**: `shell/qml/MarathonUI/Theme/MSpacing.qml` (scaled)
- ❌ **BACKUP**: `shell/qml/MarathonUI.backup/Theme/MSpacing.qml` (should be deleted)

**Status:** Mostly migrated, but backup should be removed

---

#### D. Constants System (Mixed concerns!)
- **File**: `shell/qml/core/Constants.qml` (291 lines)
- **Problem**: Contains BOTH:
  - System constants (screen dimensions, DPI, z-index, gesture thresholds)
  - Design tokens (borderRadius, touchTarget sizes, spacing, font sizes)
  - Animation durations
  - Icon sizes

**Issues:**
- Design tokens should be in MarathonUI theme singletons
- Creates confusion about where to find design values
- Mixes system-level constants with design system tokens

---

### 2. **DUPLICATE UI COMPONENTS**

#### A. Button Components
- ✅ **ACTIVE**: `shell/qml/MarathonUI/Core/MButton.qml` (proper MarathonUI component)
- ❌ **DEPRECATED**: `shell/qml/components/ui/Button.qml` (marked deprecated, still registered in qmldir)
  - Uses hardcoded colors (`#006666`, `#2A2A2A`)
  - Not scaled properly
  - Only 1 file uses it (`shell/qml/components/ui/Button.qml` references itself?)

**Action:** DELETE after migrating last usage

---

#### B. Settings List Item Components
- ✅ **ACTIVE**: `shell/qml/MarathonUI/Containers/MSettingsListItem.qml` (proper MarathonUI component)
- ❌ **DUPLICATE**: `shell/qml/components/ui/SettingsListItem.qml` (179 lines)
  - Still uses `Colors.` instead of `MColors.` in 3 places
  - Registered in `shell/qml/qmldir` line 44
  - Different API/properties than MarathonUI version

**Action:** DELETE after migrating all usages to `MSettingsListItem`

---

#### C. Card Components
- ✅ **ACTIVE**: `shell/qml/MarathonUI/Containers/MCard.qml` (proper MarathonUI component with elevation)
- ❌ **DUPLICATE**: `shell/qml/components/MarathonCard.qml` (40 lines)
  - Simpler implementation
  - Uses `Constants.borderRadiusSharp` instead of `MRadius.md`
  - No elevation system

**Action:** DELETE after migrating all usages to `MCard`

---

#### D. Toggle Components
- ✅ **ACTIVE**: `shell/qml/MarathonUI/Controls/MToggle.qml` (proper MarathonUI component)
- ❌ **LEGACY**: `shell/qml/components/MarathonToggle.qml` (75 lines)
  - Uses hardcoded sizes (28px thumb)
  - Different API (`toggled(bool value)` vs `toggled()`)
  - Still uses some invalid MColors references (fixed but should be replaced)

**Action:** DELETE after migrating all usages to `MToggle`

---

#### E. List Item Components
- ✅ **ACTIVE**: `shell/qml/MarathonUI/Containers/MListItem.qml` (proper MarathonUI component)
- ❌ **DUPLICATE**: `shell/qml/components/MarathonListItem.qml` (122 lines)
  - Still uses `Colors.` instead of `MColors.` in 6 places
  - Different API/properties
  - Registered in `shell/qml/qmldir` (implicitly via Icon)

**Action:** DELETE after migrating all usages to `MListItem`

---

#### F. Section Components
- ✅ **ACTIVE**: `shell/qml/MarathonUI/Containers/MSection.qml` (proper MarathonUI component)
- ❌ **DUPLICATE**: `shell/qml/components/layout/Section.qml` (68 lines)
  - Still uses `Colors.` instead of `MColors.` in 2 places
  - Registered in `shell/qml/qmldir` line 45
  - Different implementation

**Action:** DELETE after migrating all usages to `MSection`

---

#### G. Icon Components
- ✅ **ACTIVE**: `shell/qml/MarathonUI/Core/Icon.qml` (proper MarathonUI component)
- ❌ **DUPLICATE**: `shell/qml/components/Icon.qml` (28 lines)
  - Registered in `shell/qml/qmldir` line 43
  - Uses `Constants.iconSizeMedium` instead of prop
  - Different default color

**Action:** DELETE after migrating all usages to `MarathonUI.Core.Icon`

---

### 3. **BACKUP DIRECTORY (236KB)**

**Location**: `shell/qml/MarathonUI.backup/`
- Entire backup of old UI library
- 40+ files
- Should have been deleted after migration completed

**Action:** DELETE ENTIRE DIRECTORY

---

### 4. **LEGACY THEME DIRECTORY**

**Location**: `shell/qml/theme/` (8KB)
- `Colors.qml` - Still registered in qmldir, still used by 125 files
- `Theme.qml` - Contains only 2 properties (peekThreshold, commitThreshold)

**Action:** 
- Migrate remaining `Colors.` references to `MColors.`
- Move `Theme.qml` properties to `Constants.qml` or appropriate location
- DELETE `theme/` directory
- Remove from `shell/qml/qmldir`

---

### 5. **DEPRECATED UI COMPONENTS FOLDER**

**Location**: `shell/qml/components/ui/` (10 files)
- `Button.qml` - DEPRECATED (marked)
- `SettingsListItem.qml` - DUPLICATE
- `Modal.qml` - Should use `MarathonUI.Modals.MModal`
- `ConfirmDialog.qml` - Should use `MarathonUI.Modals.MConfirmDialog`
- `Input.qml` - Should use `MarathonUI.Core.MTextInput`
- `TextInputModal.qml` - Custom, but should use MarathonUI components
- `ListPickerModal.qml` - Custom, but should use MarathonUI components
- `StorageDetailsModal.qml` - Custom, but should use MarathonUI components
- `PageIndicator.qml` - Should use `MarathonUI.Navigation.MPageIndicator`

**Action:** Migrate all usages to MarathonUI equivalents, then DELETE entire folder

---

## 📊 STATISTICS

### Design System Usage:
- **Files using `Colors.`**: 125 files
- **Files using `MColors.`**: 108 files
- **Overlap**: Many files use BOTH (migrated partially)

### Component Duplication:
- **Duplicate Button**: 1 deprecated
- **Duplicate Card**: 1 duplicate
- **Duplicate Toggle**: 1 legacy
- **Duplicate List Items**: 2 duplicates
- **Duplicate Icon**: 1 duplicate
- **Duplicate Section**: 1 duplicate

### Files to Delete:
1. `shell/qml/MarathonUI.backup/` (entire directory - 236KB)
2. `shell/qml/theme/` (entire directory - 8KB)
3. `shell/qml/components/ui/` (entire directory - 10 files)
4. `shell/qml/components/MarathonCard.qml`
5. `shell/qml/components/MarathonToggle.qml`
6. `shell/qml/components/MarathonListItem.qml`
7. `shell/qml/components/layout/Section.qml`
8. `shell/qml/components/Icon.qml`

---

## 🔧 RECOMMENDED ACTIONS

### Phase 1: Remove Backups (IMMEDIATE - NO RISK)
1. Delete `shell/qml/MarathonUI.backup/` directory
2. Delete `shell/src/*.old` files (3 C++ files)
3. Delete `shell/CMakeLists.txt.backup` if exists

### Phase 2: Migrate Legacy Theme System
1. Find all remaining `Colors.` references (125 files)
2. Replace with `MColors.` equivalents
3. Remove `Colors` singleton from `shell/qml/qmldir`
4. Move `Theme.qml` properties to `Constants.qml`
5. Delete `shell/qml/theme/` directory

### Phase 3: Migrate Duplicate Components
1. Audit usages of each duplicate component
2. Replace with MarathonUI equivalents
3. Remove from `shell/qml/qmldir` registrations
4. Delete duplicate files

### Phase 4: Clean Up Constants.qml
1. Extract design tokens to appropriate MarathonUI theme singletons
2. Keep only system-level constants in `Constants.qml`
3. Document what belongs where

---

## 🎯 SPECIFIC DELETIONS RECOMMENDED

### High Priority (No Migration Needed):
- `shell/qml/MarathonUI.backup/` (entire directory)
- `shell/src/telephonyservice.cpp.old`
- `shell/src/smsservice.cpp.old`
- `shell/src/audiomanagercpp.cpp.old`
- `shell/CMakeLists.txt.backup` (if exists)

### Medium Priority (After Migration):
- `shell/qml/theme/Colors.qml` (after all `Colors.` → `MColors.` migration)
- `shell/qml/theme/Theme.qml` (move properties, then delete)
- `shell/qml/components/ui/Button.qml` (deprecated, 1 usage?)
- `shell/qml/components/ui/SettingsListItem.qml` (after migration to MSettingsListItem)
- `shell/qml/components/MarathonCard.qml` (after migration to MCard)
- `shell/qml/components/MarathonToggle.qml` (after migration to MToggle)
- `shell/qml/components/MarathonListItem.qml` (after migration to MListItem)
- `shell/qml/components/layout/Section.qml` (after migration to MSection)
- `shell/qml/components/Icon.qml` (after migration to MarathonUI.Core.Icon)

### Low Priority (Custom Components):
- `shell/qml/components/ui/Modal.qml` - May be custom wrapper, audit usage
- `shell/qml/components/ui/ConfirmDialog.qml` - May be custom wrapper, audit usage
- `shell/qml/components/ui/TextInputModal.qml` - Custom modal, but should use MarathonUI components internally
- `shell/qml/components/ui/ListPickerModal.qml` - Custom modal, but should use MarathonUI components internally
- `shell/qml/components/ui/StorageDetailsModal.qml` - Custom modal, but should use MarathonUI components internally
- `shell/qml/components/ui/PageIndicator.qml` - Should use MarathonUI.Navigation.MPageIndicator
- `shell/qml/components/ui/Input.qml` - Should use MarathonUI.Core.MTextInput

---

## 📝 QMLDIR CLEANUP REQUIRED

**File**: `shell/qml/qmldir`

**Remove these lines:**
- Line 17: `singleton Theme 1.0 theme/Theme.qml`
- Line 18: `singleton Colors 1.0 theme/Colors.qml`
- Line 43: `Icon 1.0 components/Icon.qml`
- Line 44: `SettingsListItem 1.0 components/ui/SettingsListItem.qml`
- Line 45: `Section 1.0 components/layout/Section.qml`

**Note**: These are legacy registrations that should be removed after migration

---

## ⚠️ RISK ASSESSMENT

### Low Risk (Safe to Delete Now):
- `MarathonUI.backup/` directory
- `.old` C++ files
- `CMakeLists.txt.backup`

### Medium Risk (Requires Migration First):
- `theme/Colors.qml` (125 files still reference)
- `components/ui/Button.qml` (check actual usage)
- `components/MarathonCard.qml` (check actual usage)
- `components/MarathonToggle.qml` (check actual usage)
- `components/MarathonListItem.qml` (check actual usage)
- `components/layout/Section.qml` (check actual usage)
- `components/Icon.qml` (check actual usage)

### High Risk (Requires Careful Migration):
- `components/ui/SettingsListItem.qml` (still registered, may be imported)
- `theme/Theme.qml` (properties need to be moved first)

---

## 🎯 SUMMARY

**Total Technical Debt Identified:**
- 3 duplicate color system definitions
- 8 duplicate component implementations
- 1 backup directory (236KB)
- 1 legacy theme directory (8KB)
- 125 files still using legacy `Colors.` system
- Multiple singleton registrations for deprecated components

**Estimated Cleanup:**
- Immediate deletions: ~250KB
- Files requiring migration: ~15 files
- Files requiring audit: ~125 files

**Recommendation:** Start with Phase 1 (backups), then systematically work through Phase 2-4.

