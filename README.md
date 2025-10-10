# Marathon OS - BlackBerry 10 Experience Shell

A Qt6/QML reimplementation of the BlackBerry 10 user experience, featuring Peek & Flow, Active Frames, and the signature BB10 gestures.

## Features

- 🔓 **Lock Screen** with PIN entry and swipe unlock
- 👁️ **Peek & Flow** - Swipe from left edge to peek at Hub
- 📱 **Active Frames** - Task switcher with running app grid
- ⚙️ **Quick Settings** - Pull down for system controls
- 🎨 **Responsive Design** - Adapts to different screen sizes
- ⚡ **Smooth Animations** - 60 FPS BB10-style transitions

## Prerequisites

### macOS

1. **Qt 6.9+** with the following components:
   - Qt Quick
   - Qt Quick Controls  
   - Qt SVG
   - Qt Multimedia

2. **CMake** 3.16+
3. **Ninja** build system
4. **Xcode Command Line Tools**

### Installation

```bash
# Install Homebrew (if not installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install build tools
brew install cmake ninja

# Install Qt (via official installer)
# Download from: https://www.qt.io/download-qt-installer
# Select Qt 6.9+ with macOS components
```

### Qt Environment Setup

Add to your `~/.zshrc` or `~/.bash_profile`:

```bash
# Qt 6.9+ Environment
export QT_DIR="$HOME/Qt/6.10.0/macos"
export PATH="$QT_DIR/bin:$PATH"
export CMAKE_PREFIX_PATH="$QT_DIR/lib/cmake:$CMAKE_PREFIX_PATH"
export PKG_CONFIG_PATH="$QT_DIR/lib/pkgconfig:$PKG_CONFIG_PATH"
export QML_IMPORT_PATH="$QT_DIR/qml"
export QML2_IMPORT_PATH="$QT_DIR/qml"

# Qml tools
export PATH="$QT_DIR/libexec:$PATH"
```

Then reload:
```bash
source ~/.zshrc
```

## Build Instructions

```bash
# Clone the repository
cd /path/to/Marathon-Shell

# Create build directory
mkdir -p build
cd build

# Configure with CMake
cmake .. -G Ninja \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_PREFIX_PATH="$QT_DIR"

# Build
ninja

# Or use cmake --build
cd ..
cmake --build build
```

## Run Instructions

```bash
# From project root
./build/shell/marathon-shell

# Or with Qt environment
source ~/.zshrc && ./build/shell/marathon-shell
```

## Usage

### Lock Screen
- **Enter PIN:** `147147` (default)
- **Swipe up:** Reveal PIN pad

### Gestures
- **Swipe from left edge:** Peek & Flow - Open Hub
- **Pull down from top:** Quick Settings
- **Swipe up short from bottom:** Active Frames (Task Switcher)
- **ESC key:** Close overlays

### Quick Settings
- Toggle WiFi, Bluetooth, Airplane Mode, Rotation Lock, Flashlight, Alarm
- Adjust Brightness and Volume with sliders
- Click chevron-down icon to close

### Active Frames (Task Switcher)
- View running apps in grid
- Click app to switch
- Click X to close app
- Swipe down to return home

## Project Structure

```
Marathon-Shell/
├── CMakeLists.txt           # Root CMake configuration
├── README.md                # This file
├── docs/                    # Documentation
├── shell/                   # Main shell application
│   ├── CMakeLists.txt       # Shell CMake config
│   ├── main.cpp             # Application entry point
│   ├── resources.qrc        # Qt resources (images, icons)
│   ├── resources/           # Assets
│   │   ├── images/          # App icons
│   │   │   └── icons/       # System icons
│   │   │       └── lucide/  # Lucide icon pack
│   │   └── wallpapers/      # Background images
│   └── qml/                 # QML source files
│       ├── Main.qml         # Application window
│       ├── MarionShell.qml  # Main shell orchestrator
│       ├── components/      # UI components
│       │   ├── Icon.qml
│       │   ├── MarionLockScreen.qml
│       │   ├── MarionAppGrid.qml
│       │   ├── MarionStatusBar.qml
│       │   ├── MarionQuickSettings.qml
│       │   ├── MarionTaskSwitcher.qml
│       │   ├── MarionPeek.qml
│       │   ├── MarionNavBar.qml
│       │   ├── MarionBottomBar.qml
│       │   └── MarionMessagingHub.qml
│       ├── stores/          # State management
│       │   ├── qmldir
│       │   ├── AppStore.qml
│       │   ├── WallpaperStore.qml
│       │   ├── SystemStatusStore.qml
│       │   ├── SystemControlStore.qml
│       │   └── TaskManagerStore.qml
│       └── theme/           # Design system
│           ├── qmldir
│           ├── Theme.qml
│           ├── Colors.qml
│           └── Typography.qml
```

## Development

### Architecture

**State Management:** QML Singletons
- `SystemStatusStore` - Battery, WiFi, time, notifications
- `SystemControlStore` - Settings toggles (WiFi, Bluetooth, etc)
- `TaskManagerStore` - Running apps and task management
- `AppStore` - Application data and launching
- `WallpaperStore` - Wallpaper selection and theme

**Components:** Modular QML components with clear responsibilities
- Each component is self-contained
- Uses stores for shared state
- Emits signals for actions

**Theme System:** Centralized design tokens
- `Colors` - Color palette
- `Typography` - Font styles and sizes
- `Theme` - Spacing, borders, animations

### Adding Icons

1. Download SVG from [Lucide](https://lucide.dev)
2. Place in `shell/resources/images/icons/lucide/`
3. Add to `shell/resources.qrc`:
   ```xml
   <file>resources/images/icons/lucide/new-icon.svg</file>
   ```
4. Rebuild project
5. Use with Icon component:
   ```qml
   Icon {
       name: "new-icon"
       size: 24
       color: Colors.text
   }
   ```

### Debugging

```bash
# Run with Qt logging
QT_LOGGING_RULES="qt.qml.binding=true" ./build/shell/marathon-shell

# Check QML warnings
QML_IMPORT_TRACE=1 ./build/shell/marathon-shell

# Enable all debug output
QT_DEBUG_PLUGINS=1 ./build/shell/marathon-shell
```

## Troubleshooting

### "qmake not found"
```bash
# Ensure Qt is in PATH
echo $QT_DIR
export PATH="$QT_DIR/bin:$PATH"
```

### "QQmlApplicationEngine failed to load component"
- Check QML file paths in `shell/CMakeLists.txt`
- Verify all QML files are listed in `QML_FILES`
- Run `cmake --build build --clean-first`

### Icons not appearing
- Verify icons exist in `shell/resources/images/icons/lucide/`
- Check `shell/resources.qrc` has correct file paths
- Rebuild: `cmake --build build`

### App crashes on launch
- Check Qt version: `qmake --version` (should be 6.9+)
- Verify all Qt modules installed
- Check console output for QML errors

## Contributing

1. Follow Qt/QML best practices
2. Use DRY principles - extract reusable components
3. Test on multiple resolutions
4. Document new features
5. Keep animations at 60 FPS

## License

MIT License - See LICENSE file for details

## Credits

- Inspired by BlackBerry 10 OS
- UI patterns from [marion-shell](https://github.com/example/marion-shell)
- Icons from [Lucide](https://lucide.dev)
- Built with Qt 6.9+

## Roadmap

- [ ] Icon color tinting with MultiEffect
- [ ] Universal Search
- [ ] Balance (Work/Personal profiles)
- [ ] Virtual Keyboard
- [ ] Advanced visual effects (frosted glass, shadows)
- [ ] More stores (Media, Notifications, Keyboard)
- [ ] Responsive layouts
- [ ] Performance optimization

## Contact

For issues, questions, or contributions, please open an issue on the repository.

