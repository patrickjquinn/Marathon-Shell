# Marathon App Development Guide

## Overview

Marathon OS apps can be built as **pure QML** (fast iteration) or **hybrid QML + C++** (native performance). The build system supports both approaches seamlessly.

## Architecture

### Current System
```
Marathon Shell (C++ executable with QML runtime)
├── MarathonAppLoader (loads QML modules)
├── MarathonAppRegistry (scans for apps)
└── Apps: QML modules in ~/.local/share/marathon-apps/
    ├── Pure QML apps (just copied)
    └── C++ apps (compiled as Qt plugins)
```

### App Structure
```
apps/myapp/
├── CMakeLists.txt          # Build configuration
├── manifest.json           # App metadata
├── MyApp.qml              # Main entry point
├── qmldir                 # QML module definition
├── assets/                # Icons, images
│   └── icon.svg
├── components/            # Reusable QML components
│   └── MyComponent.qml
├── pages/                 # App screens
│   └── MyPage.qml
└── src/                   # C++ sources (optional)
    ├── myplugin.h
    └── myplugin.cpp
```

## Quick Start

### 1. Pure QML App (Simple)

**Create `apps/myapp/CMakeLists.txt`:**
```cmake
set(APP_NAME myapp)

file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
)

add_marathon_app(${APP_NAME}
    URI "MarathonApp.MyApp"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
)
```

**Create `apps/myapp/manifest.json`:**
```json
{
  "id": "myapp",
  "name": "My App",
  "version": "1.0.0",
  "entryPoint": "MyApp.qml",
  "icon": "assets/icon.svg",
  "author": "Your Name",
  "permissions": ["storage"],
  "minShellVersion": "1.0.0"
}
```

**Create `apps/myapp/MyApp.qml`:**
```qml
import QtQuick
import MarathonOS.Shell
import MarathonUI.Containers

MApp {
    id: myApp
    appId: "myapp"
    appName: "My App"
    
    content: Rectangle {
        anchors.fill: parent
        color: MColors.background
        
        Text {
            anchors.centerIn: parent
            text: "Hello Marathon!"
            font.pixelSize: Constants.fontSizeXLarge
            color: MColors.text
        }
    }
}
```

**Build and install:**
```bash
./scripts/build-apps.sh
```

### 2. Hybrid QML + C++ App (Advanced)

**Create `apps/myapp/CMakeLists.txt`:**
```cmake
set(APP_NAME myapp)

file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
)

set(SOURCES
    src/myplugin.cpp
    src/myengine.cpp
)

add_marathon_app(${APP_NAME}
    HAS_CPP
    URI "MarathonApp.MyApp"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
    SOURCES ${SOURCES}
)

# Link additional Qt modules if needed
target_link_libraries(${APP_NAME}-plugin PRIVATE Qt6::Multimedia)
```

**Create `apps/myapp/src/myplugin.h`:**
```cpp
#pragma once

#include <QObject>
#include <QQmlEngine>

class MyEngine : public QObject {
    Q_OBJECT
    QML_ELEMENT
    
public:
    explicit MyEngine(QObject *parent = nullptr);
    
    Q_INVOKABLE QString doSomethingNative();
    
signals:
    void dataReady(const QString &data);
};
```

**Create `apps/myapp/src/myplugin.cpp`:**
```cpp
#include "myplugin.h"

MyEngine::MyEngine(QObject *parent) : QObject(parent) {}

QString MyEngine::doSomethingNative() {
    // Native C++ logic here
    return "Result from C++!";
}
```

**Use in QML:**
```qml
import MarathonApp.MyApp

MApp {
    id: myApp
    
    MyEngine {
        id: engine
        onDataReady: (data) => {
            console.log("Got data:", data)
        }
    }
    
    content: Rectangle {
        Button {
            text: "Call C++"
            onClicked: {
                var result = engine.doSomethingNative()
                console.log(result)
            }
        }
    }
}
```

## Build System

### Commands

**Build all apps:**
```bash
./scripts/build-apps.sh
```

**Build shell + apps:**
```bash
./scripts/build-all.sh
```

**Build specific app:**
```bash
cd build-apps
make myapp-plugin
cmake --install .
```

**Clean rebuild:**
```bash
rm -rf build-apps
./scripts/build-apps.sh
```

### Build Workflow

1. **Shell Development** (C++ changes):
   ```bash
   cd build && make -j$(sysctl -n hw.ncpu)
   ```

2. **App Development** (QML changes):
   ```bash
   # Quick: Just copy QML files
   cp -r apps/myapp /Users/patrick.quinn/.local/share/marathon-apps/
   
   # Full: Rebuild with CMake
   ./scripts/build-apps.sh
   ```

3. **App Development** (C++ changes):
   ```bash
   cd build-apps
   make myapp-plugin -j$(sysctl -n hw.ncpu)
   cmake --install .
   ```

## Adding Apps to Build System

**Edit `apps/CMakeLists.txt`:**
```cmake
# Add your app to the list
add_subdirectory(myapp)
```

## Marathon UI Components

Apps have access to the full MarathonUI library:

```qml
import MarathonUI.Containers  // MApp, MCard, MPage, MSection
import MarathonUI.Core        // MButton, MTextInput, MIconButton
import MarathonUI.Controls    // MToggle, MSlider
import MarathonUI.Lists       // MListItem, MSectionHeader
import MarathonUI.Navigation  // MTopBar, MBottomBar
import MarathonUI.Feedback    // MActivityIndicator, MBadge
import MarathonUI.Modals      // MModal, MSheet, MConfirmDialog
import MarathonUI.Theme       // MColors, MTypography
```

## Shell Services

Apps can access shell services via singletons:

```qml
// Settings storage
SettingsManagerCpp.get("myapp/data", "default")
SettingsManagerCpp.set("myapp/data", "value")

// Logging
Logger.info("MyApp", "Message")
Logger.error("MyApp", "Error message")

// Haptics
HapticService.light()
HapticService.medium()
HapticService.heavy()

// Network status
NetworkManager.isOnline
NetworkManager.connectionType

// Power management
PowerManager.batteryLevel
PowerManager.isCharging
```

## Best Practices

### When to Use C++

✅ **Use C++ for:**
- Heavy computation (image processing, data parsing)
- System APIs (camera, bluetooth, sensors)
- File I/O and database operations
- Network operations
- Performance-critical code
- Third-party library integration

❌ **Use QML for:**
- UI layout and styling
- Animations and transitions
- Simple data binding
- Navigation and state management
- Prototype/MVP development

### Performance Tips

1. **Lazy Loading**: Use `Loader` for heavy components
2. **List Optimization**: Use `ListView.cacheBuffer` and `reuseItems`
3. **Image Loading**: Use `Image.asynchronous: true`
4. **C++ for Data**: Use C++ models for large datasets
5. **Avoid Bindings**: Use explicit property assignments in loops

### Code Organization

```
apps/myapp/
├── CMakeLists.txt
├── manifest.json
├── MyApp.qml              # Main app (MApp wrapper)
├── components/            # Reusable UI components
│   ├── MyButton.qml
│   └── MyCard.qml
├── pages/                 # Full-screen pages
│   ├── HomePage.qml
│   └── SettingsPage.qml
├── models/                # Data models (QML ListModel or C++)
│   └── MyModel.qml
└── src/                   # C++ backend
    ├── myplugin.h/cpp     # QML plugin
    ├── myengine.h/cpp     # Business logic
    └── mymodel.h/cpp      # Data models
```

## Examples

### Browser App (Complex)
- Tabs management (QML)
- WebEngine integration (Qt)
- Bookmarks/History (QML + storage)
- Downloads (future C++)

### Settings App (System)
- Pure QML UI
- Uses shell C++ backends
- Deep navigation stack

### Clock App (Data)
- QML UI
- Timer/alarm state management
- Future: Native notifications (C++)

### Camera App (Hardware)
- QML viewfinder
- Future: Image processing (C++)
- Future: Camera API (C++)

## Distribution

Apps are installed to:
```
~/.local/share/marathon-apps/
├── myapp/
│   ├── MyApp.qml
│   ├── manifest.json
│   ├── qmldir
│   ├── assets/
│   └── libmyapp-plugin.dylib  (if C++)
```

The Marathon Shell automatically discovers and loads apps from this directory.

## Debugging

**QML Debugging:**
```bash
QML_IMPORT_TRACE=1 ./build/shell/marathon-shell
```

**Check app loading:**
```bash
# Shell logs will show:
[MarathonAppLoader] Loading app: myapp
[MarathonAppLoader] Path: ~/.local/share/marathon-apps/myapp
[MarathonAppLoader] Entry: MyApp.qml
```

**Check for errors:**
- Watch console output for QML errors
- Check file paths in manifest.json
- Verify qmldir module URI matches imports
- Ensure all dependencies are installed

## Migration from Pure QML

If you have an existing QML-only app:

1. Create `CMakeLists.txt` (pure QML version)
2. Run `./scripts/build-apps.sh`
3. Test app still works
4. Add C++ sources if needed
5. Update CMakeLists.txt with `HAS_CPP`
6. Rebuild and test

No code changes required - the build system handles both!

