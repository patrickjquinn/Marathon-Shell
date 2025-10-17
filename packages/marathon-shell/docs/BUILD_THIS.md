# Marathon OS - macOS VSCode Quick Start Guide
**BlackBerry 10-Inspired Mobile UI on Qt 6.9+ QML**

*Last updated: October 2025 | Validated for macOS 14+ (Sonoma/Sequoia)*

---

## Overview

This guide gets you building Marathon OS's UI layer in under 30 minutes. We're focusing on **QML prototyping first**, with backend integration coming later. By the end, you'll have a live-reloading BB10-style interface running in a desktop window.

**What you'll build:**
- ✅ Gesture-driven launcher
- ✅ Active Frames multitasking UI
- ✅ BB10 design system (colors, typography, design units)
- ✅ Live preview with hot-reload

---

## Prerequisites

### System Requirements

```bash
# Verify macOS version (14.0+ required)
sw_vers

# Output should show: ProductVersion: 14.x.x or 15.x.x
```

**Minimum specs:**
- macOS 14.0 Sonoma or newer
- 8GB RAM (16GB recommended)
- 15GB free disk space
- Xcode Command Line Tools

---

## Step 1: Install Development Tools

### 1.1 Install Xcode Command Line Tools

```bash
# Install Xcode CLI tools
xcode-select --install

# If already installed, verify path
xcode-select -p
# Expected: /Applications/Xcode.app/Contents/Developer

# If you have multiple Xcode versions, set the active one
sudo xcode-select --switch /Applications/Xcode.app

# Verify installation
clang --version
# Should show: Apple clang version 15.x or newer
```

### 1.2 Install Homebrew

```bash
# Install Homebrew (if not already installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# For Apple Silicon Macs, add to PATH
if [[ $(uname -m) == "arm64" ]]; then
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Verify
brew --version
```

### 1.3 Install Build Tools

```bash
# Install CMake and Ninja
brew install cmake ninja

# Verify versions
cmake --version     # Should be 3.21+
ninja --version     # Any recent version
```

---

## Step 2: Install Qt 6.9+

### 2.1 Download Qt Online Installer

**Option A: Using Browser**
1. Visit https://www.qt.io/download-qt-installer
2. Download "Qt Online Installer for macOS"
3. Open the downloaded `.dmg` file

**Option B: Using Command Line**

```bash
cd ~/Downloads

# Download Qt Online Installer
curl -L -o qt-installer.dmg \
  "https://download.qt.io/official_releases/online_installers/qt-unified-macOS-x64-online.dmg"

# Mount and open
hdiutil attach qt-installer.dmg
open /Volumes/qt-unified-macOS*/qt-unified-*.app
```

### 2.2 Install Qt Components

**In the Qt Installer:**

1. **Create/Login** to Qt Account (free for open source)

2. **Select Installation Type:** 
   - Choose "Custom installation"

3. **Select Components** (Qt 6.9.3 or 6.10.0):
   ```
   ☑ Qt 6.9.3 (or 6.10.0)
     ☑ macOS
     ☑ Qt Quick 3D
     ☑ Qt 5 Compatibility Module
     ☑ Additional Libraries
       ☑ Qt Quick Controls
       ☑ Qt Multimedia
       ☑ Qt Wayland Compositor
   
   ☑ Developer and Designer Tools
     ☑ CMake 3.27.x
     ☑ Ninja 1.11.x
   ```

4. **Installation Path:** Accept default `~/Qt`

5. **Install** (takes 10-15 minutes)

### 2.3 Configure Environment

Add to `~/.zshrc` (or `~/.bash_profile` if using bash):

```bash
# Open your shell config
nano ~/.zshrc

# Add these lines (adjust version if needed)
export QT_VERSION="6.9.3"
export QT_ROOT="$HOME/Qt/$QT_VERSION/macos"
export PATH="$QT_ROOT/bin:$PATH"
export CMAKE_PREFIX_PATH="$QT_ROOT:$CMAKE_PREFIX_PATH"
export QML_IMPORT_PATH="$QT_ROOT/qml"
export QML2_IMPORT_PATH="$QT_ROOT/qml"

# Save: Ctrl+O, Enter, Ctrl+X

# Apply changes
source ~/.zshrc
```

### 2.4 Verify Qt Installation

```bash
# Test Qt tools
qmake --version
# Expected: QMake version 3.x, Using Qt version 6.9.3

which qml
# Expected: /Users/yourname/Qt/6.9.3/macos/bin/qml

qml --version
# Expected: QML Runtime version 6.9.3
```

**Troubleshooting:**
```bash
# If commands not found, check installation path
ls -la ~/Qt/*/macos/bin/qmake

# Manually set QT_ROOT to correct version
export QT_ROOT="$HOME/Qt/6.10.0/macos"  # Adjust version
```

---

## Step 3: Install and Configure VSCode

### 3.1 Install VSCode

```bash
# Install via Homebrew
brew install --cask visual-studio-code

# Or download from: https://code.visualstudio.com
```

### 3.2 Install Essential Extensions

```bash
# Install all required extensions at once
code --install-extension ms-vscode.cpptools-extension-pack
code --install-extension ms-vscode.cmake-tools
code --install-extension twxs.cmake
code --install-extension qt.qt-official

# Optional but recommended
code --install-extension eamodio.gitlens
```

**Verify extensions:**
```bash
code --list-extensions | grep -E "(qt|cmake|cpp)"
```

### 3.3 Create Project Directory

```bash
# Create project structure
mkdir -p ~/Projects/marathon-os
cd ~/Projects/marathon-os

# Initialize git
git init

# Create .gitignore
cat > .gitignore << 'EOF'
build/
.vscode/
*.user
*.autosave
.DS_Store
.qtc_clangd/
*.qmlc
*.jsc
EOF

# Create directory structure
mkdir -p shell/{qml/{components,theme},src,resources}
```

---

## Step 4: Project Configuration

### 4.1 VSCode Settings

Create `.vscode/settings.json`:

```bash
mkdir -p .vscode
cat > .vscode/settings.json << 'EOF'
{
  "cmake.configureOnOpen": true,
  "cmake.buildDirectory": "${workspaceFolder}/build",
  "cmake.generator": "Ninja",
  "cmake.configureSettings": {
    "CMAKE_BUILD_TYPE": "Debug",
    "CMAKE_EXPORT_COMPILE_COMMANDS": "ON"
  },
  "C_Cpp.default.configurationProvider": "ms-vscode.cmake-tools",
  "files.associations": {
    "*.qml": "qml",
    "*.qrc": "xml",
    "CMakeLists.txt": "cmake"
  },
  "[qml]": {
    "editor.tabSize": 4,
    "editor.insertSpaces": true,
    "editor.formatOnSave": false
  },
  "qt-official.qmlls.enabled": true,
  "search.exclude": {
    "**/build": true,
    "**/.qtc_clangd": true
  }
}
EOF
```

### 4.2 VSCode Tasks

Create `.vscode/tasks.json`:

```bash
cat > .vscode/tasks.json << 'EOF'
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Configure",
      "type": "shell",
      "command": "cmake",
      "args": [
        "-B", "build",
        "-G", "Ninja",
        "-DCMAKE_BUILD_TYPE=Debug"
      ],
      "group": "build",
      "problemMatcher": []
    },
    {
      "label": "Build",
      "type": "shell",
      "command": "cmake",
      "args": ["--build", "build", "--parallel"],
      "group": {
        "kind": "build",
        "isDefault": true
      },
      "dependsOn": ["Configure"],
      "problemMatcher": ["$gcc"]
    },
    {
      "label": "Run",
      "type": "shell",
      "command": "${workspaceFolder}/build/shell/marathon-shell",
      "dependsOn": ["Build"],
      "group": "test",
      "problemMatcher": []
    },
    {
      "label": "QML Preview",
      "type": "shell",
      "command": "qml",
      "args": ["${file}"],
      "group": "test",
      "problemMatcher": []
    },
    {
      "label": "Clean",
      "type": "shell",
      "command": "rm",
      "args": ["-rf", "build"],
      "group": "build"
    }
  ]
}
EOF
```

### 4.3 Launch Configuration

Create `.vscode/launch.json`:

```bash
cat > .vscode/launch.json << 'EOF'
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Debug Marathon Shell",
      "type": "cppdbg",
      "request": "launch",
      "program": "${workspaceFolder}/build/shell/marathon-shell",
      "args": [],
      "stopAtEntry": false,
      "cwd": "${workspaceFolder}",
      "environment": [
        {
          "name": "QML_IMPORT_PATH",
          "value": "${env:QT_ROOT}/qml"
        }
      ],
      "externalConsole": false,
      "MIMode": "lldb",
      "preLaunchTask": "Build"
    }
  ]
}
EOF
```

---

## Step 5: Create Minimal Project

### 5.1 Root CMakeLists.txt

```bash
cat > CMakeLists.txt << 'EOF'
cmake_minimum_required(VERSION 3.21)

project(MarathonOS VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS
    Core
    Gui
    Qml
    Quick
    QuickControls2
)

add_subdirectory(shell)

message(STATUS "=== Marathon OS ===")
message(STATUS "Qt version: ${Qt6_VERSION}")
message(STATUS "Build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "==================")
EOF
```

### 5.2 Shell CMakeLists.txt

```bash
cat > shell/CMakeLists.txt << 'EOF'
project(marathon-shell)

set(SOURCES
    main.cpp
)

set(QML_FILES
    qml/Main.qml
    qml/Shell.qml
    qml/Launcher.qml
    qml/ActiveFrames.qml
    qml/StatusBar.qml
    qml/components/GestureArea.qml
    qml/components/AppIcon.qml
    qml/theme/Theme.qml
    qml/theme/Colors.qml
    qml/theme/Typography.qml
    qml/theme/qmldir
)

qt6_add_executable(marathon-shell ${SOURCES})

qt6_add_qml_module(marathon-shell
    URI MarathonOS.Shell
    VERSION 1.0
    QML_FILES ${QML_FILES}
)

target_link_libraries(marathon-shell PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
)

if(APPLE)
    set_target_properties(marathon-shell PROPERTIES
        MACOSX_BUNDLE FALSE
    )
endif()
EOF
```

### 5.3 Main Entry Point

```bash
cat > shell/main.cpp << 'EOF'
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQuickStyle>
#include <QDebug>

int main(int argc, char *argv[])
{
    QGuiApplication::setApplicationName("Marathon Shell");
    QGuiApplication::setOrganizationName("Marathon OS");
    QGuiApplication::setAttribute(Qt::AA_EnableHighDpiScaling);
    
    QGuiApplication app(argc, argv);
    QQuickStyle::setStyle("");  // No Qt Quick Controls style
    
    QQmlApplicationEngine engine;
    
    const QUrl url(QStringLiteral("qrc:/qt/qml/MarathonOS/Shell/qml/Main.qml"));
    
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
        &app, [url](QObject *obj, const QUrl &objUrl) {
            if (!obj && url == objUrl) {
                qCritical() << "Failed to load QML";
                QCoreApplication::exit(-1);
            }
        }, Qt::QueuedConnection);
    
    engine.load(url);
    
    if (engine.rootObjects().isEmpty()) {
        qCritical() << "No root QML objects";
        return -1;
    }
    
    qDebug() << "Marathon OS Shell started";
    return app.exec();
}
EOF
```

---

## Step 6: Create QML Components

### 6.1 Theme System

```bash
# Create qmldir
cat > shell/qml/theme/qmldir << 'EOF'
module MarathonOS.Theme
singleton Theme 1.0 Theme.qml
singleton Colors 1.0 Colors.qml
singleton Typography 1.0 Typography.qml
EOF

# Theme.qml
cat > shell/qml/theme/Theme.qml << 'EOF'
pragma Singleton
import QtQuick

QtObject {
    readonly property real designUnitScale: 9
    function du(value) { return value * designUnitScale }
    
    // Spacing
    readonly property real paddingSmall: du(1)
    readonly property real paddingMedium: du(2)
    readonly property real paddingLarge: du(3)
    
    // Dimensions
    readonly property real statusBarHeight: du(7)
    readonly property real iconSize: du(12)
    
    // Animation
    readonly property int durationFast: 150
    readonly property int durationMedium: 250
    readonly property int easingStandard: Easing.OutCubic
    
    // Gesture
    readonly property real peekThreshold: du(11)
    readonly property real commitThreshold: du(22)
}
EOF

# Colors.qml
cat > shell/qml/theme/Colors.qml << 'EOF'
pragma Singleton
import QtQuick

QtObject {
    readonly property color background: "#000000"
    readonly property color surface: "#0a0a0a"
    readonly property color accent: "#00a9e0"
    readonly property color text: "#ffffff"
    readonly property color textSecondary: "#b8b8b8"
}
EOF

# Typography.qml
cat > shell/qml/theme/Typography.qml << 'EOF'
pragma Singleton
import QtQuick

QtObject {
    readonly property string fontFamily: Qt.platform.os === "osx" ? 
        ".AppleSystemUIFont" : "Roboto"
    readonly property int sizeLarge: 24
    readonly property int sizeBody: 16
    readonly property int sizeSmall: 14
    readonly property int weightBold: Font.Bold
}
EOF
```

### 6.2 Main Window

```bash
cat > shell/qml/Main.qml << 'EOF'
import QtQuick
import QtQuick.Window

Window {
    id: window
    width: 720
    height: 1280
    visible: true
    title: "Marathon OS"
    color: "#000000"
    
    Shell {
        anchors.fill: parent
    }
    
    // Keyboard shortcuts
    Item {
        focus: true
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_R && event.modifiers & Qt.ControlModifier) {
                console.log("Reload requested")
            }
        }
    }
}
EOF
```

### 6.3 Shell Container

```bash
cat > shell/qml/Shell.qml << 'EOF'
import QtQuick
import "./components"
import "./theme"

Item {
    id: shell
    
    // Status Bar
    StatusBar {
        id: statusBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        z: 100
    }
    
    // Launcher
    Launcher {
        id: launcher
        anchors.fill: parent
        anchors.topMargin: statusBar.height
        z: 10
    }
    
    // Active Frames (hidden for now)
    ActiveFrames {
        id: activeFrames
        anchors.top: statusBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 400
        z: 50
        opacity: 0
        visible: false
    }
    
    // Gesture handler
    GestureArea {
        anchors.fill: parent
        z: 200
        
        onPeekStarted: {
            console.log("👆 Peek!")
            activeFrames.visible = true
        }
        
        onPeekProgress: (progress) => {
            activeFrames.opacity = progress
        }
        
        onPeekReleased: (committed) => {
            if (!committed) {
                activeFrames.visible = false
                activeFrames.opacity = 0
            }
        }
    }
}
EOF
```

### 6.4 Status Bar

```bash
cat > shell/qml/StatusBar.qml << 'EOF'
import QtQuick
import "./theme"

Rectangle {
    height: Theme.statusBarHeight
    color: Colors.background
    
    Row {
        anchors.fill: parent
        anchors.leftMargin: Theme.paddingMedium
        anchors.rightMargin: Theme.paddingMedium
        spacing: Theme.paddingSmall
        
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatTime(new Date(), "hh:mm")
            color: Colors.text
            font.pixelSize: Typography.sizeSmall
            font.weight: Typography.weightBold
        }
        
        Item { Layout.fillWidth: true; height: 1 }
        
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "📶 🔋 85%"
            color: Colors.text
            font.pixelSize: Typography.sizeSmall
        }
    }
}
EOF
```

### 6.5 Launcher

```bash
cat > shell/qml/Launcher.qml << 'EOF'
import QtQuick
import "./components"
import "./theme"

Rectangle {
    gradient: Gradient {
        GradientStop { position: 0.0; color: Colors.background }
        GradientStop { position: 1.0; color: Colors.surface }
    }
    
    GridView {
        anchors.fill: parent
        anchors.margins: Theme.paddingLarge
        cellWidth: width / 4
        cellHeight: cellWidth
        
        model: ListModel {
            ListElement { name: "Phone"; icon: "📞" }
            ListElement { name: "Messages"; icon: "💬" }
            ListElement { name: "Email"; icon: "📧" }
            ListElement { name: "Browser"; icon: "🌐" }
            ListElement { name: "Camera"; icon: "📷" }
            ListElement { name: "Photos"; icon: "🖼️" }
            ListElement { name: "Music"; icon: "🎵" }
            ListElement { name: "Settings"; icon: "⚙️" }
        }
        
        delegate: AppIcon {
            width: GridView.view.cellWidth - 8
            height: GridView.view.cellHeight - 8
            appName: model.name
            appIcon: model.icon
        }
    }
}
EOF
```

### 6.6 App Icon Component

```bash
cat > shell/qml/components/AppIcon.qml << 'EOF'
import QtQuick
import "../theme"

Item {
    id: root
    property string appName: ""
    property string appIcon: ""
    
    Rectangle {
        anchors.fill: parent
        anchors.margins: 4
        color: Colors.surface
        radius: 12
        
        Column {
            anchors.centerIn: parent
            spacing: 8
            
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: appIcon
                font.pixelSize: 48
            }
            
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: appName
                color: Colors.text
                font.pixelSize: Typography.sizeSmall
            }
        }
        
        MouseArea {
            anchors.fill: parent
            onClicked: console.log("Launch:", appName)
        }
        
        // Touch feedback
        scale: touchArea.pressed ? 0.95 : 1.0
        Behavior on scale {
            NumberAnimation {
                duration: Theme.durationFast
                easing.type: Theme.easingStandard
            }
        }
        
        MouseArea {
            id: touchArea
            anchors.fill: parent
        }
    }
}
EOF
```

### 6.7 Gesture Handler

```bash
cat > shell/qml/components/GestureArea.qml << 'EOF'
import QtQuick
import "../theme"

MouseArea {
    id: gestureArea
    
    signal peekStarted()
    signal peekProgress(real progress)
    signal peekReleased(bool committed)
    
    property real startY: 0
    property bool isPeeking: false
    
    preventStealing: false
    propagateComposedEvents: true
    
    onPressed: (mouse) => {
        startY = mouse.y
        if (mouse.y > height - Theme.peekThreshold) {
            isPeeking = true
            peekStarted()
            mouse.accepted = true
        } else {
            mouse.accepted = false
        }
    }
    
    onPositionChanged: (mouse) => {
        if (isPeeking) {
            var dragY = startY - mouse.y
            var progress = Math.max(0, Math.min(1, 
                dragY / Theme.commitThreshold))
            peekProgress(progress)
            mouse.accepted = true
        }
    }
    
    onReleased: (mouse) => {
        if (isPeeking) {
            var dragY = startY - mouse.y
            var committed = dragY > Theme.commitThreshold
            peekReleased(committed)
            isPeeking = false
            mouse.accepted = true
        }
    }
}
EOF
```

### 6.8 Active Frames Placeholder

```bash
cat > shell/qml/ActiveFrames.qml << 'EOF'
import QtQuick
import "./theme"

Rectangle {
    color: Colors.background
    
    Text {
        anchors.centerIn: parent
        text: "Active Frames\n(Coming Soon)"
        color: Colors.text
        font.pixelSize: Typography.sizeLarge
        horizontalAlignment: Text.AlignHCenter
    }
}
EOF
```

---

## Step 7: Build and Run

### 7.1 Open in VSCode

```bash
# Open project in VSCode
code ~/Projects/marathon-os
```

### 7.2 Configure and Build

**Option A: Using VSCode Tasks**

1. Press `⌘ + Shift + B` (Build)
2. Select "Build" from the task list
3. Wait for compilation to complete

**Option B: Using Terminal**

```bash
cd ~/Projects/marathon-os

# Configure
cmake -B build -G Ninja

# Build
cmake --build build --parallel

# Run
./build/shell/marathon-shell
```

### 7.3 Expected Output

You should see:
- A 720x1280 window with black background
- Status bar at top showing time and battery
- App grid launcher with 8 icons
- Console message: "Marathon OS Shell started"

**Test gestures:**
- Swipe up from bottom edge → Should trigger peek

---

## Step 8: Development Workflow

### 8.1 Live Preview Individual QML Files

```bash
# Test a single component
qml shell/qml/components/AppIcon.qml

# Preview launcher
qml shell/qml/Launcher.qml
```

### 8.2 Quick Iteration

**Recommended workflow:**

1. **Edit QML** → Save file
2. **Rebuild** → `⌘ + Shift + B`
3. **Run** → `⌘ + Shift + D` or Task: "Run"

### 8.3 Hot Reload Workaround

Since Qt doesn't have built-in hot reload, use this script:

```bash
cat > watch-and-build.sh << 'EOF'
#!/bin/bash
echo "👁️  Watching for QML changes..."
fswatch -o shell/qml/**/*.qml | while read; do
    echo "🔄 Rebuilding..."
    cmake --build build --parallel && ./build/shell/marathon-shell
done
EOF

chmod +x watch-and-build.sh

# Install fswatch
brew install fswatch

# Run watcher
./watch-and-build.sh
```

---

## Troubleshooting

### Issue: "Qt not found"

```bash
# Check Qt installation
ls ~/Qt/*/macos/bin/qmake

# Set correct Qt path in CMakeLists.txt
export QT_ROOT="$HOME/Qt/6.9.3/macos"
export CMAKE_PREFIX_PATH="$QT_ROOT"

# Reconfigure
rm -rf build
cmake -B build -G Ninja
```

### Issue: "QML module not found"

```bash
# Verify QML import path
echo $QML_IMPORT_PATH

# Should show: /Users/yourname/Qt/6.9.3/macos/qml

# Set if missing
export QML_IMPORT_PATH="$QT_ROOT/qml"
export QML2_IMPORT_PATH="$QT_ROOT/qml"
```

### Issue: Build errors

```bash
# Clean rebuild
rm -rf build
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug
cmake --build build --parallel -- -v
```

### Issue: Window doesn't appear

```bash
# Check console for errors
./build/shell/marathon-shell

# Enable Qt debug logging
QT_LOGGING_RULES="*.debug=true" ./build/shell/marathon-shell
```

### Issue: Gestures not working

Add debug output to `GestureArea.qml`:

```qml
onPressed: (mouse) => {
    console.log("Press at:", mouse.x, mouse.y)
    // ... rest of code
}
```

---

## Next Steps

### Phase 1: Perfect the UI (Current Focus)

1. **Enhance Launcher:**
   - Add page indicators
   - Implement smooth scrolling
   - Add app search

2. **Build Active Frames:**
   - Design frame layout
   - Add close buttons
   - Implement tap-to-switch

3. **Refine Gestures:**
   - Add velocity detection
   - Implement arc gestures (Hub/Previous)
   - Fine-tune thresholds

4. **Add Hub:**
   - Notification list
   - Slide-in animation
   - Filter controls

### Phase 2: Add Interactivity

5. **State Management:**
   - Track current view
   - App switching logic
   - Animation transitions

6. **Mock Apps:**
   - Create sample app views
   - Test multitasking
   - Validate gesture flows

### Phase 3: Backend Integration (Later)

7. **Wayland Compositor**
8. **Process Management**
9. **System Integration**

---

## Quick Reference

### Keyboard Shortcuts

- `⌘ + Shift + B` - Build project
- `⌘ + Shift + D` - Debug
- `F5` - Start debugging
- `Shift + F5` - Stop debugging

### Useful Commands

```bash
# Build
cmake --build build

# Run
./build/shell/marathon-shell

# Clean
rm -rf build

# Preview QML
qml shell/qml/Main.qml

# Check Qt version
qmake --version
```

### File Structure

```
marathon-os/
├── CMakeLists.txt
├── shell/
│   ├── CMakeLists.txt
│   ├── main.cpp
│   └── qml/
│       ├── Main.qml
│       ├── Shell.qml
│       ├── Launcher.qml
│       ├── ActiveFrames.qml
│       ├── StatusBar.qml
│       ├── components/
│       │   ├── GestureArea.qml
│       │   └── AppIcon.qml
│       └── theme/
│           ├── qmldir
│           ├── Theme.qml
│           ├── Colors.qml
│           └── Typography.qml
└── build/          (generated)
```

---

## Resources

- **Qt Documentation:** https://doc.qt.io/qt-6/
- **QML Reference:** https://doc.qt.io/qt-6/qtqml-index.html
- **Qt Quick:** https://doc.qt.io/qt-6/qtquick-index.html
- **BlackBerry 10 UI Guidelines:** https://developer.blackberry.com/devzone/files/design/bb10/

---

**🎉 You're now ready to build Marathon OS!**

Start with: `code ~/Projects/marathon-os` then press `⌘ + Shift + B` to build.

The BB10 dream lives on! 📱✨