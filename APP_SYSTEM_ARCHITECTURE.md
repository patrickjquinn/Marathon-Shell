# Marathon App System Architecture

## Overview
The Marathon App System provides a standardized lifecycle, navigation, and event handling framework for all apps running in Marathon Shell.

---

## Core Components

### 1. **MApp** (`MarathonUI/Containers/MApp.qml`)
Base container that all apps should inherit from.

**Features**:
- Lifecycle management (launch, pause, resume, close)
- Back gesture handling
- Navigation stack support
- State preservation
- Safe area management

**Example**:
```qml
import MarathonUI.Containers

MApp {
    id: myApp
    appId: "my-app"
    appName: "My App"
    appIcon: "qrc:/images/my-app.svg"
    
    // Handle back navigation
    onBackPressed: {
        if (navigationStack.depth > 1) {
            navigationStack.pop()
            return true  // Handled
        }
        return false  // Not handled, close app
    }
    
    // Lifecycle hooks
    onAppLaunched: {
        console.log("App launched!")
    }
    
    onAppPaused: {
        // Save state
    }
    
    onAppResumed: {
        // Restore state
    }
    
    content: Item {
        // Your app UI here
    }
}
```

---

### 2. **AppLifecycleManager** (`services/AppLifecycleManager.qml`)
Singleton that manages all app instances and routes system events.

**Responsibilities**:
- Register/unregister app instances
- Track foreground/background apps
- Route back gestures to active app
- Coordinate app state transitions
- Manage app lifecycle

**API**:
```qml
// Register app (automatic via MApp)
AppLifecycleManager.registerApp(appId, appInstance)

// Handle system back
var handled = AppLifecycleManager.handleSystemBack()

// Minimize foreground app
AppLifecycleManager.minimizeForegroundApp()

// Close app
AppLifecycleManager.closeApp(appId)

// Query state
var isRunning = AppLifecycleManager.isAppRunning(appId)
var foregroundId = AppLifecycleManager.getForegroundAppId()
```

---

## App Lifecycle

### States
1. **Launched** - App is created and initialized
2. **Active** - App is in foreground and receiving input
3. **Paused** - App is in background (another app active)
4. **Minimized** - App is in task switcher
5. **Closed** - App is destroyed

### State Transitions
```
        launch()
           ↓
       [Launched] ──────→ [Active]
           ↑                  ↓
           │              pause()
           │                  ↓
           │              [Paused]
           │                  ↓
           │             minimize()
           │                  ↓
           │            [Minimized]
           │                  ↓
           └───────────── close()
```

### Lifecycle Hooks
Apps can implement these signals to react to state changes:

```qml
MApp {
    onAppLaunched: {
        // Initialize app
        // Load saved state
        // Connect to services
    }
    
    onAppResumed: {
        // Restore UI state
        // Refresh data
        // Resume animations
    }
    
    onAppPaused: {
        // Pause animations
        // Save state
        // Release resources
    }
    
    onAppMinimized: {
        // Save state for task switcher preview
        // Prepare thumbnail
    }
    
    onAppClosed: {
        // Cleanup
        // Disconnect services
        // Save final state
    }
}
```

---

## Navigation & Back Handling

### System Back Gesture Flow
```
User swipes right from nav bar
    ↓
MarathonNavBar.swipeBack()
    ↓
MarathonShell.onSwipeBack()
    ↓
AppLifecycleManager.handleSystemBack()
    ↓
foregroundApp.handleBack()
    ↓
App's onBackPressed handler
    ↓
Return true (handled) or false (close app)
```

### Implementing Back Navigation
```qml
MApp {
    id: myApp
    
    StackView {
        id: navStack
        anchors.fill: parent
        initialItem: mainPage
    }
    
    onBackPressed: {
        if (navStack.depth > 1) {
            navStack.pop()
            return true  // We handled it
        }
        return false  // At root, let system close app
    }
}
```

---

## Integration with Existing Systems

### UIStore
Manages app visibility state (open/closed):
```qml
UIStore.openApp(appId, appName, appIcon)
UIStore.minimizeApp()
UIStore.closeApp()
```

### TaskManagerStore
Manages task cards in task switcher:
```qml
TaskManagerStore.launchTask(appId, appName, appIcon)
TaskManagerStore.closeTask(taskId)
```

### AppLifecycleManager
Manages app instances and lifecycle:
```qml
AppLifecycleManager.registerApp(appId, instance)
AppLifecycleManager.bringToForeground(appId)
AppLifecycleManager.handleSystemBack()
```

**Flow**:
```
App Launch:
  MarathonShell → UIStore.openApp() → AppWindow.show() → MApp created
                → AppLifecycleManager.registerApp()

App Minimize:
  NavBar gesture → MarathonShell → TaskManagerStore.launchTask()
                                 → AppLifecycleManager.minimizeForegroundApp()
                                 → UIStore.minimizeApp()

Back Gesture:
  NavBar gesture → MarathonShell → AppLifecycleManager.handleSystemBack()
                                 → App.handleBack() → StackView.pop()
```

---

## Migration Guide

### Updating Existing Apps

**Before** (Settings App - Hardcoded):
```qml
Rectangle {
    id: settingsApp
    signal closed()
    
    StackView {
        id: navigationStack
        // ...
    }
    
    function navigateBack() {
        if (navigationStack.depth > 1) {
            navigationStack.pop()
            return true
        }
        return false
    }
}
```

**After** (Using MApp):
```qml
import MarathonUI.Containers

MApp {
    id: settingsApp
    appId: "settings"
    appName: "Settings"
    appIcon: "qrc:/images/settings.svg"
    
    onBackPressed: {
        if (navigationStack.depth > 1) {
            navigationStack.pop()
            return true
        }
        return false
    }
    
    content: Item {
        StackView {
            id: navigationStack
            anchors.fill: parent
            // ...
        }
    }
}
```

### Shell Integration

**MarathonShell.qml**:
```qml
onSwipeBack: {
    // Route to app lifecycle manager
    var handled = AppLifecycleManager.handleSystemBack()
    if (!handled) {
        // App didn't handle it, close the app
        if (UIStore.settingsOpen) {
            UIStore.closeSettings()
        } else if (UIStore.appWindowOpen) {
            UIStore.closeApp()
        }
    }
}
```

---

## Best Practices

### 1. Always Use MApp for Apps
✅ **DO**:
```qml
MApp {
    appId: "my-app"
    content: Item { /* UI */ }
}
```

❌ **DON'T**:
```qml
Rectangle {
    id: myApp
    // Direct implementation
}
```

### 2. Implement Back Handling
✅ **DO**:
```qml
onBackPressed: {
    // Check if can go back
    if (canGoBack()) {
        goBack()
        return true
    }
    return false
}
```

❌ **DON'T**:
```qml
// No back handling - app can't navigate back
```

### 3. Save State on Pause
✅ **DO**:
```qml
onAppPaused: {
    saveState()
}

onAppResumed: {
    restoreState()
}
```

### 4. Clean Up on Close
✅ **DO**:
```qml
onAppClosed: {
    disconnectServices()
    clearTimers()
    saveState()
}
```

---

## Testing Checklist

- [ ] App inherits from MApp
- [ ] Back gesture navigates correctly
- [ ] Back gesture at root closes app
- [ ] App can be minimized
- [ ] App can be restored from task switcher
- [ ] State is preserved across minimize/restore
- [ ] App cleans up on close
- [ ] No memory leaks
- [ ] Lifecycle hooks are implemented

---

## Future Enhancements

1. **App Permissions System**: Request/manage permissions via lifecycle
2. **Deep Linking**: Navigate to specific app states
3. **App-to-App Communication**: IPC between Marathon apps
4. **Background Tasks**: Allow apps to run tasks when minimized
5. **State Restoration**: Automatic state save/restore
6. **App Sandboxing**: Isolate app resources and data

---

## Summary

The Marathon App System provides:
- ✅ Standardized app lifecycle
- ✅ Automatic back gesture handling
- ✅ Centralized app state management
- ✅ Easy integration with shell systems
- ✅ Scalable architecture for any number of apps

All apps should inherit from `MApp` and implement `onBackPressed` for proper system integration.

