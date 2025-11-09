# Template App

 **THIS IS A TEMPLATE - DO NOT INSTALL THIS APP** 

This is a starter template for creating new Marathon apps. It demonstrates best practices for MApp lifecycle management, navigation, and UI design.

**Important**: This app is NOT meant to be built or installed. It exists purely as a reference and starting point for new apps.

## Features

-  Proper MApp lifecycle hooks
-  Stack-based navigation with back gesture support
-  State persistence using SettingsManagerCpp
-  Marathon UI components (MActionBar, MCard, MButton, etc.)
-  Smooth page transitions
-  Haptic feedback
-  Logging integration

## Getting Started

1. **Copy this template**:
   ```bash
   cp -r apps/template apps/myapp
   cd apps/myapp
   ```

2. **Update identifiers**:
   - Edit `manifest.json`: Change `id`, `name`, `description`
   - Edit `TemplateApp.qml`: Change `appId`, `appName`
   - Rename `TemplateApp.qml` to `MyAppApp.qml`
   - Update `qmldir`: Change module name to `MyApp`
   - Update `CMakeLists.txt`: Change project name and paths

3. **Add your icon**:
   - Place your icon in `assets/icon.svg`

4. **Build and install**:
   ```bash
   cd ../..
   ./scripts/build-all.sh
   ```

## Structure

```
apps/myapp/
├── manifest.json           # App metadata
├── MyAppApp.qml            # Main app entry point (extends MApp)
├── qmldir                  # QML module definition
├── CMakeLists.txt          # Build configuration
├── README.md               # This file
├── pages/                  # App pages
│   └── MainPage.qml        # Main page
├── components/             # Reusable components
│   └── (your components)
└── assets/                 # Icons, images, etc.
    └── icon.svg
```

## Best Practices

### 1. Lifecycle Management

Always implement these lifecycle hooks:

```qml
onAppLaunched: {
    // Load initial data
}

onAppResumed: {
    // Resume timers, refresh data
}

onAppPaused: {
    // Pause timers, save state
}

onAppWillTerminate: {
    // Final cleanup, save data
}
```

### 2. Navigation

Update `navigationDepth` when using `StackView`:

```qml
StackView {
    id: navigationStack
    
    onDepthChanged: {
        myApp.navigationDepth = depth - 1
    }
}

Connections {
    target: myApp
    function onBackPressed() {
        if (navigationStack.depth > 1) {
            navigationStack.pop()
        }
    }
}
```

### 3. State Persistence

Use `SettingsManagerCpp` for persistent storage:

```qml
function saveAppData() {
    var data = JSON.stringify(appData)
    SettingsManagerCpp.set("myapp/data", data)
}

function loadAppData() {
    var savedData = SettingsManagerCpp.get("myapp/data", "[]")
    appData = JSON.parse(savedData)
}
```

### 4. Haptic Feedback

Use `HapticService` for tactile feedback:

```qml
MButton {
    onClicked: {
        HapticService.medium()  // Or .light() / .heavy()
    }
}
```

### 5. Logging

Use `Logger` for consistent logging:

```qml
Logger.info("MyApp", "User performed action")
Logger.warn("MyApp", "Warning message")
Logger.error("MyApp", "Error message")
```

## Resources

- [MApp Framework Guide](../../docs/MAPP_GUIDE.md)
- [Marathon UI Components](../../marathon-ui/)
- [App Development Tutorial](../../docs/APP_DEVELOPMENT.md)

## License

MIT

