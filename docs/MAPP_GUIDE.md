# MApp Framework Guide

## Overview

The **MApp** (Marathon App) framework provides a lifecycle-managed container for all Marathon applications. It offers Android/iOS-style app lifecycle management, state tracking, navigation support, and seamless integration with the Marathon OS Shell.

---

## Table of Contents

1. [Architecture](#architecture)
2. [Getting Started](#getting-started)
3. [Lifecycle Management](#lifecycle-management)
4. [State Properties](#state-properties)
5. [Navigation](#navigation)
6. [Signals](#signals)
7. [Best Practices](#best-practices)
8. [Debugging](#debugging)
9. [Examples](#examples)

---

## Architecture

The MApp framework consists of three core components:

1. **MApp.qml** (`marathon-ui/Containers/MApp.qml`)
   - Base QML component that all Marathon apps extend
   - Provides lifecycle hooks and state management
   - Handles auto-registration with AppLifecycleManager

2. **MarathonAppLoader** (`shell/src/marathonapploader.cpp`)
   - C++ service for loading app QML components
   - Manages async loading and component caching
   - Configures import paths automatically

3. **AppLifecycleManager** (`shell/qml/services/AppLifecycleManager.qml`)
   - Singleton service coordinating app lifecycle
   - Tracks foreground/background state
   - Routes system events to apps

---

## Getting Started

### Basic App Structure

```qml
import QtQuick
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Theme

MApp {
    id: myApp
    appId: "myapp"              // Required: unique identifier
    appName: "My App"            // Required: display name
    appIcon: "assets/icon.svg"   // Optional: defaults to manifest icon
    
    // Optional: Enable lifecycle debug logging
    debugLifecycle: false
    
    content: Rectangle {
        anchors.fill: parent
        color: MColors.background
        
        // Your app UI here
    }
}
```

### Required Properties

| Property | Type | Description |
|----------|------|-------------|
| `appId` | `string` | Unique app identifier (matches manifest.json) |
| `appName` | `string` | Display name shown in UI |
| `appIcon` | `string` | Path to app icon (relative to app directory) |

---

## Lifecycle Management

### Lifecycle States

Apps transition through the following states:

```
Created → Launched → Started → Resumed
                        ↓           ↑
                     Paused    ←   │
                        ↓           │
                   Minimized  →  Restored
                        ↓
                    Stopped
                        ↓
                   Terminated
```

### Lifecycle Signals

| Signal | When Fired | Use Case |
|--------|------------|----------|
| `appCreated()` | App instance created | Initialize data structures |
| `appLaunched()` | App starts for first time | Load saved state |
| `appStarted()` | App becomes visible | Start animations |
| `appResumed()` | App returns to foreground | Resume timers, refresh data |
| `appPaused()` | App goes to background | Pause timers, save state |
| `appStopped()` | App becomes invisible | Stop animations |
| `appMinimized()` | User minimizes app | Save current state |
| `appRestored()` | App restored from minimized | Restore UI state |
| `appWillTerminate()` | App about to close | Final cleanup |
| `appClosed()` | App fully closed | Release resources |
| `appBecameVisible()` | Visibility changed to true | - |
| `appBecameHidden()` | Visibility changed to false | - |
| `lowMemoryWarning()` | System low on memory | Free cached data |

### Example: Lifecycle Hooks

```qml
MApp {
    id: myApp
    appId: "myapp"
    
    property var userData: []
    property int refreshTimer: 0
    
    // Load initial data
    onAppLaunched: {
        Logger.info("MyApp", "App launched - loading data")
        userData = loadUserData()
    }
    
    // Start background tasks
    onAppResumed: {
        Logger.info("MyApp", "App resumed - starting timer")
        refreshTimer = setInterval(refreshData, 30000)
    }
    
    // Stop background tasks
    onAppPaused: {
        Logger.info("MyApp", "App paused - stopping timer")
        if (refreshTimer) {
            clearInterval(refreshTimer)
            refreshTimer = 0
        }
        saveUserData(userData)
    }
    
    // Final cleanup
    onAppWillTerminate: {
        Logger.info("MyApp", "App terminating - final save")
        saveUserData(userData)
    }
    
    // Handle low memory
    onLowMemoryWarning: {
        Logger.warn("MyApp", "Low memory - clearing cache")
        clearImageCache()
    }
    
    content: Rectangle {
        // UI here
    }
}
```

---

## State Properties

### Boolean State Flags

| Property | Description |
|----------|-------------|
| `isActive` | App is currently active |
| `isPaused` | App is paused |
| `isMinimized` | App is minimized |
| `isVisible` | App is visible on screen |
| `isForeground` | App is in foreground |
| `isPreviewMode` | App is in task switcher preview |

### Reading State

```qml
MApp {
    id: myApp
    
    Timer {
        interval: 1000
        running: myApp.isActive && myApp.isForeground
        repeat: true
        onTriggered: {
            // Only update when app is active and in foreground
            updateData()
        }
    }
}
```

---

## Navigation

### Stack-Based Navigation

For apps with multiple pages, use `StackView` and update `navigationDepth`:

```qml
MApp {
    id: myApp
    appId: "myapp"
    
    content: Rectangle {
        anchors.fill: parent
        
        StackView {
            id: navigationStack
            anchors.fill: parent
            initialItem: homePage
            
            // Update navigationDepth when stack changes
            onDepthChanged: {
                myApp.navigationDepth = depth - 1
            }
            
            Component.onCompleted: {
                myApp.navigationDepth = depth - 1
            }
        }
    }
    
    // Handle back gesture
    Connections {
        target: myApp
        function onBackPressed() {
            if (navigationStack.depth > 1) {
                navigationStack.pop()
            }
        }
    }
}
```

### Navigation Properties

| Property | Type | Description |
|----------|------|-------------|
| `navigationDepth` | `int` | Number of pages in navigation stack (0 = root) |
| `canNavigateBack` | `bool` | Auto-computed: `navigationDepth > 0` |
| `canNavigateForward` | `bool` | Can navigate forward (for browser-style apps) |

### Navigation Signals

| Signal | When Fired | Default Behavior |
|--------|------------|------------------|
| `backPressed()` | User swipes back or presses back button | Pop navigation stack if `canNavigateBack` is true, otherwise minimize app |
| `forwardPressed()` | User navigates forward | Only fired if `canNavigateForward` is true |
| `minimizeRequested()` | App should minimize | Sent to AppLifecycleManager |
| `closed()` | App should close | Sent to AppLifecycleManager |

---

## Signals

### System Signals

Apps can listen for system-level signals:

```qml
MApp {
    id: myApp
    
    Connections {
        target: myApp
        
        function onBackPressed() {
            // Handle back navigation
        }
        
        function onMinimizeRequested() {
            // Custom minimize behavior (optional)
        }
    }
}
```

---

## Best Practices

###  DO

1. **Always set `appId`, `appName`**
   ```qml
   MApp {
       appId: "myapp"
       appName: "My App"
   }
   ```

2. **Update `navigationDepth` in `StackView.onDepthChanged`**
   ```qml
   StackView {
       onDepthChanged: {
           myApp.navigationDepth = depth - 1
       }
   }
   ```

3. **Use `Connections` for signal handling**
   ```qml
   Connections {
       target: myApp
       function onBackPressed() { /* ... */ }
   }
   ```

4. **Save state on `appPaused()`**
   ```qml
   onAppPaused: {
       saveAppState()
   }
   ```

5. **Clean up resources on `appWillTerminate()`**
   ```qml
   onAppWillTerminate: {
       database.close()
       networkManager.disconnect()
   }
   ```

###  DON'T

1. **Don't use manual connection management**
   ```qml
   //  Bad
   property var backConnection: null
   Component.onCompleted: {
       backConnection = myApp.backPressed.connect(...)
   }
   ```

2. **Don't forget to update `navigationDepth`**
   ```qml
   //  Bad - back gesture won't work
   StackView {
       // Missing onDepthChanged
   }
   ```

3. **Don't perform heavy operations in lifecycle signals**
   ```qml
   //  Bad - blocks UI
   onAppResumed: {
       loadEntireDatabase()  // Use async loading instead
   }
   ```

4. **Don't override `appIcon` unless necessary**
   ```qml
   //  Bad - icon from manifest is automatically injected
   MApp {
       appIcon: "assets/icon.svg"  // Usually redundant
   }
   ```

---

## Debugging

### Enable Debug Logging

Set `debugLifecycle: true` to see lifecycle events in console:

```qml
MApp {
    id: myApp
    appId: "myapp"
    debugLifecycle: true  // Enable debug logging
}
```

**Output**:
```
[MApp Lifecycle] myapp start()
[MApp Lifecycle] myapp resume()
[MApp Lifecycle] myapp pause()
[MApp Lifecycle] myapp minimize()
```

### Common Issues

#### Issue: Back gesture doesn't work

**Solution**: Ensure `navigationDepth` is updated:

```qml
StackView {
    id: navigationStack
    onDepthChanged: {
        myApp.navigationDepth = depth - 1
    }
}
```

#### Issue: App state not persisting

**Solution**: Save state in `onAppPaused`:

```qml
onAppPaused: {
    SettingsManagerCpp.set("myapp/state", JSON.stringify(myState))
}
```

#### Issue: Icon not showing in task switcher

**Solution**: Ensure `appIcon` matches `manifest.json`:

```json
// manifest.json
{
  "icon": "assets/icon.svg"
}
```

```qml
// MyApp.qml
MApp {
    appIcon: "assets/icon.svg"  // Must match manifest
}
```

---

## Examples

### Single-Page App

```qml
import QtQuick
import MarathonUI.Containers
import MarathonUI.Theme
import MarathonUI.Core

MApp {
    id: calculatorApp
    appId: "calculator"
    appName: "Calculator"
    
    property string display: "0"
    
    content: Rectangle {
        anchors.fill: parent
        color: MColors.background
        
        Column {
            anchors.centerIn: parent
            spacing: MSpacing.md
            
            MLabel {
                text: calculatorApp.display
                variant: "primary"
                font.pixelSize: 48
            }
            
            // Calculator buttons...
        }
    }
}
```

### Multi-Page App with Navigation

```qml
import QtQuick
import QtQuick.Controls
import MarathonUI.Containers
import MarathonUI.Theme
import MarathonUI.Navigation

MApp {
    id: notesApp
    appId: "notes"
    appName: "Notes"
    
    property var notes: []
    
    onAppLaunched: {
        notes = loadNotes()
    }
    
    onAppPaused: {
        saveNotes(notes)
    }
    
    content: Rectangle {
        anchors.fill: parent
        color: MColors.background
        
        StackView {
            id: navigationStack
            anchors.fill: parent
            initialItem: notesListPage
            
            onDepthChanged: {
                notesApp.navigationDepth = depth - 1
            }
        }
    }
    
    Connections {
        target: notesApp
        function onBackPressed() {
            if (navigationStack.depth > 1) {
                navigationStack.pop()
            }
        }
    }
    
    Component {
        id: notesListPage
        // Notes list UI
    }
}
```

### Tab-Based App

```qml
import QtQuick
import QtQuick.Layouts
import MarathonUI.Containers
import MarathonUI.Theme
import MarathonUI.Navigation

MApp {
    id: phoneApp
    appId: "phone"
    appName: "Phone"
    
    content: Rectangle {
        anchors.fill: parent
        color: MColors.background
        
        Column {
            anchors.fill: parent
            spacing: 0
            
            property int currentTab: 0
            
            StackLayout {
                width: parent.width
                height: parent.height - tabBar.height
                currentIndex: parent.currentTab
                
                // Dialer tab
                Item { /* Dialer UI */ }
                
                // History tab
                Item { /* History UI */ }
                
                // Contacts tab
                Item { /* Contacts UI */ }
            }
            
            MTabBar {
                id: tabBar
                width: parent.width
                activeTab: parent.currentTab
                
                tabs: [
                    { label: "Dial", icon: "phone" },
                    { label: "History", icon: "clock" },
                    { label: "Contacts", icon: "users" }
                ]
                
                onTabSelected: (index) => {
                    parent.currentTab = index
                }
            }
        }
    }
}
```

---

## API Reference

### Properties

```qml
property string appId                    // Unique app identifier
property string appName                  // Display name
property string appIcon                  // Icon path
property bool isPreviewMode              // Task switcher preview
property bool debugLifecycle             // Enable debug logging
property bool isActive                   // App is active
property bool isPaused                   // App is paused
property bool isMinimized                // App is minimized
property bool isVisible                  // App is visible
property bool isForeground               // App is foreground
property int navigationDepth             // Stack depth
property bool canNavigateBack            // Can navigate back
property bool canNavigateForward         // Can navigate forward
property Component content               // App content
```

### Functions

```qml
function start()                         // Start app
function stop()                          // Stop app
function pause()                         // Pause app
function resume()                        // Resume app
function minimize()                      // Minimize app
function restore()                       // Restore app
function close()                         // Close app
function handleBack()                    // Handle back gesture
function handleForward()                 // Handle forward gesture
function handleLowMemory()               // Handle low memory
```

### Signals

```qml
signal closed()                          // App closed
signal minimizeRequested()               // Minimize requested
signal backPressed()                     // Back gesture
signal forwardPressed()                  // Forward gesture
signal appCreated()                      // App created
signal appLaunched()                     // App launched
signal appStarted()                      // App started
signal appResumed()                      // App resumed
signal appPaused()                       // App paused
signal appStopped()                      // App stopped
signal appMinimized()                    // App minimized
signal appRestored()                     // App restored
signal appWillTerminate()                // About to terminate
signal appClosed()                       // Fully closed
signal appBecameVisible()                // Became visible
signal appBecameHidden()                 // Became hidden
signal lowMemoryWarning()                // Low memory warning
```

---

## Further Reading

- [Marathon UI Component Guide](./MARATHON_UI_GUIDE.md)
- [App Development Tutorial](./APP_DEVELOPMENT.md)
- [Shell Architecture](./SHELL_ARCHITECTURE.md)

---

**Version**: 1.0  
**Last Updated**: November 6, 2025

