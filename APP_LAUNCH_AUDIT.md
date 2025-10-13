# App Launch Flow Audit

## Overview
This document audits all app launching logic in Marathon Shell to ensure consistency and correctness.

---

## Entry Points

### 1. **App Grid** (`MarathonAppGrid.qml`)
**Location**: Line 178-182
```qml
onClicked: {
    Logger.info("AppGrid", "App launched: " + modelData.name)
    appLaunched(modelData)  // Signal to parent
    HapticService.medium()
}
```
**Flow**:
1. Emits `appLaunched(modelData)` signal directly to parent
2. Signal caught by `MarathonPageView` → propagated to `MarathonShell`
3. Shell handles the actual app opening logic

**Status**: ✅ **CORRECT** - Clean signal-based architecture

---

### 2. **Bottom Bar** (`MarathonBottomBar.qml` → `MarathonShell.qml`)
**Location**: `MarathonShell.qml` Line 177-186
```qml
onAppLaunched: (app) => {
    Logger.info("Shell", "Bottom bar launched: " + app.name)
    
    if (app.id === "settings") {
        UIStore.openSettings()
    } else {
        UIStore.openApp(app.id, app.name, app.icon)
        appWindow.show(app.id, app.name, app.icon)
    }
}
```
**Flow**:
1. Bottom bar emits `appLaunched` signal with app object
2. Shell checks if it's settings or regular app
3. For regular apps: Sets UIStore state AND shows app window

**Status**: ✅ **CORRECT** (recently fixed)

---

### 3. **App Grid via PageView** (`MarathonPageView.qml` → `MarathonShell.qml`)
**Location**: `MarathonShell.qml` Line 137-146
```qml
onAppLaunched: (app) => {
    Logger.info("Shell", "App launched: " + app.name)
    
    if (app.id === "settings") {
        UIStore.openSettings()
    } else {
        UIStore.openApp(app.id, app.name, app.icon)
        appWindow.show(app.id, app.name, app.icon)
    }
}
```
**Flow**: Identical to bottom bar flow

**Status**: ✅ **CORRECT** - Consistent with bottom bar

---

### 4. **Task Switcher Restore** (`MarathonTaskSwitcher.qml`)
**Location**: Line 150-163
```qml
onClicked: {
    if (modelData.appId === "settings") {
        UIStore.openSettings()
    } else {
        UIStore.restoreApp(modelData.appId, modelData.title, modelData.icon)
        appWindow.show(modelData.appId, modelData.title, modelData.icon)
    }
    closed()
}
```
**Flow**:
1. Checks if settings or regular app
2. For regular apps: Calls `UIStore.restoreApp()` AND `appWindow.show()`
3. Emits `closed()` to navigate away from task switcher

**Status**: ✅ **CORRECT**

---

## State Management

### UIStore (`UIStore.qml`)
**Responsibilities**:
- Tracks which app/overlay is currently open
- Stores current app metadata (id, name, icon)
- Provides open/close/minimize/restore functions

**Key Functions**:
- `openApp(appId, appName, appIcon)` - Sets app as open and stores metadata
- `closeApp()` - Closes app and clears metadata
- `minimizeApp()` - Hides app but keeps metadata (for restore)
- `restoreApp(appId, appName, appIcon)` - Restores minimized app
- `openSettings()` / `closeSettings()` / `minimizeSettings()`

**Status**: ✅ **CORRECT** - Clear separation of concerns

---

### AppStore (`AppStore.qml`)
**Responsibilities**:
- Maintains catalog of all available apps
- Provides helper functions to query app metadata

**Key Functions**:
- `getApp(appId)` - Returns app object by ID
- `getAppName(appId)` - Returns app name by ID
- `getAppIcon(appId)` - Returns app icon path by ID
- `isInternalApp(appId)` - Checks if app is internal (template) or external (native)

**Status**: ✅ **CORRECT** - Clean, focused responsibility (app catalog only)

---

### TaskManagerStore (`TaskManagerStore.qml`)
**Responsibilities**:
- Manages active tasks/frames for task switcher
- Creates task cards with metadata
- Tracks task count

**Key Functions**:
- `launchTask(appId, appName, appIcon)` - Creates task for active frames
- `closeTask(taskId)` - Removes task from grid
- `switchToTask(taskId)` - Activates a task

**Status**: ✅ **CORRECT** - Properly manages task grid

---

## App Minimization Flow

### Gesture → Task Creation
**Location**: `MarathonShell.qml` Line 240-252
```qml
onStartPageTransition: {
    if ((UIStore.appWindowOpen || UIStore.settingsOpen) && pageView.currentIndex !== 1) {
        // Add task BEFORE page transition so grid isn't empty
        if (UIStore.settingsOpen) {
            TaskManagerStore.launchTask("settings", "Settings", "qrc:/images/settings.svg")
        } else if (UIStore.appWindowOpen) {
            TaskManagerStore.launchTask(appWindow.appId, appWindow.appName, appWindow.appIcon)
        }
        
        pageView.currentIndex = 1
        Router.goToFrames()
    }
}

onMinimizeApp: {
    shell.isTransitioningToActiveFrames = true
    snapIntoGridAnimation.start()
}
```

**Flow**:
1. User swipes up from nav bar while app is open
2. When `gestureProgress > 0.15`, triggers `onStartPageTransition`
3. Creates task in `TaskManagerStore` with current app info
4. Switches to active frames page (index 1)
5. When gesture completes (`diffY > 60`), triggers `onMinimizeApp`
6. Sets transition flag and starts fade-out animation
7. After 250ms, calls `UIStore.minimizeApp()` or `UIStore.minimizeSettings()`

**Status**: ✅ **CORRECT** - Properly coordinated

---

## Issues & Recommendations

### ✅ **COMPLETED: AppStore Consolidation**
**Previous Problem**: Two stores tracking similar data
- `AppStore.runningApps` vs `TaskManagerStore.runningTasks`
- `AppStore.launchApp()` called but didn't open the app window
- Redundant state management

**Solution Implemented**: 
- ✅ Removed `AppStore.launchApp()` call from AppGrid
- ✅ Removed `runningApps` tracking from AppStore
- ✅ AppStore now only manages app catalog (single source of truth for app metadata)
- ✅ TaskManagerStore exclusively manages running tasks/active frames
- ✅ UIStore exclusively manages current open app visibility state

**New Architecture**:
```
AppStore (Catalog)
├── apps[] - All available apps with metadata
└── Helper functions (getApp, getAppName, getAppIcon, isInternalApp)

TaskManagerStore (Running Tasks)
├── runningTasks[] - Active tasks in task switcher
├── launchTask() - Add task to active frames
└── closeTask() - Remove task from active frames

UIStore (Current Visibility State)
├── appWindowOpen - Is an app currently visible?
├── currentAppId/Name/Icon - Which app is visible?
├── openApp() - Show app window
└── minimizeApp() - Hide app window (keeps in TaskManager)
```

---

### 2. **Inconsistent App Metadata**
**Problem**: App icon paths are inconsistent
- Some use `qrc:/images/settings.svg`
- Template app maps icon names to lucide icons
- Icon loading errors in console

**Status**: ⚠️ **PARTIALLY ADDRESSED** - Icon mapping added to TemplateApp
**Recommendation**: Consider creating centralized icon mapping service

---

## Conclusion

**Overall Status**: ✅ **CLEAN & CORRECT**

The app launch flow is now properly consolidated with clear separation of concerns:
1. ✅ **AppStore** - App catalog only (metadata lookup)
2. ✅ **TaskManagerStore** - Running tasks management (active frames grid)
3. ✅ **UIStore** - Current app visibility state
4. ✅ **Removed redundant tracking** - No duplication between stores
5. ✅ **Clean signal flow** - AppGrid → PageView → Shell → UIStore + AppWindow

The minimization gesture flow is properly coordinated and works correctly.

