# Marathon Shell

**A modern, gesture-driven mobile shell for Linux** built with Qt6/QML, inspired by BlackBerry 10 and designed for touch-first interaction.

Marathon Shell is a Wayland compositor and application shell that provides a complete mobile OS experience on Linux, with native support for both Marathon apps (built in QML) and standard Linux desktop applications.

## ✨ Features

### Core Shell Experience
- **Gesture Navigation**: Fluid swipe gestures for multitasking
- **Hub Workflow**: Unified messaging center for notifications, calendar events, and communications
- **Peek**: Quick preview of notifications without leaving your app
- **Active Frames**: Live app previews in the task switcher
- **Inertia Navigation**: Physics-based scrolling and page transitions

### Native Linux App Integration 🚀 **NEW**
- **Wayland Compositor**: Embed native Linux apps directly in the shell
- **D-Bus Session**: Full desktop integration with notifications, portals, and services
- **Flatpak & Snap Support**: Automatic detection and permission handling
- **gapplication Support**: Seamless integration with GNOME applications
- **First-Class Citizens**: Linux apps work as naturally as Marathon apps

### Application Framework
- **Marathon Apps**: QML-based apps with optional C++ plugins
- **MarathonUI Design System**: Comprehensive UI component library
- **App Lifecycle Management**: Background/foreground state management
- **Dynamic Loading**: Apps installed to `~/.local/share/marathon-apps/`

### System Services
- **Network Management**: WiFi, cellular (via NetworkManager)
- **Power Management**: Battery status, power profiles (via UPower)
- **Bluetooth**: Device pairing and management (via BlueZ)
- **Telephony**: Calls, SMS (via ModemManager)
- **Display**: Brightness, screen timeout
- **Audio**: Volume, routing
- **Notifications**: System-wide notification service

## 📋 Requirements

### Build Dependencies
```bash
# Fedora/RHEL
sudo dnf install cmake ninja-build gcc-c++ \
    qt6-qtbase-devel \
    qt6-qtdeclarative-devel \
    qt6-qtwayland-devel \
    qt6-qtmultimedia-devel \
    qt6-qtsvg-devel \
    dbus-daemon

# Ubuntu/Debian
sudo apt install cmake ninja-build g++ \
    qt6-base-dev \
    qt6-declarative-dev \
    qt6-wayland-dev \
    qt6-multimedia-dev \
    qt6-svg-dev \
    dbus-daemon
```

### Runtime Requirements
- **Qt 6.5+** (tested with 6.9.2)
- **Wayland** compositor support
- **D-Bus** session bus
- **NetworkManager** (optional - for WiFi/cellular)
- **UPower** (optional - for battery status)
- **BlueZ** (optional - for Bluetooth)
- **ModemManager** (optional - for telephony)

### Optional Dependencies
- `qt6-qtwebengine-devel` - Real browser (otherwise uses mockup UI)
- `qt6-qtvirtualkeyboard-devel` - Virtual keyboard support

## 🔨 Building

### Quick Start
```bash
# Build everything (shell + apps)
./scripts/build-all.sh

# Or build individually:
./scripts/build-shell.sh    # Shell only
./scripts/build-apps.sh      # Apps only
```

### Development Build
```bash
# Incremental build (fast)
./run.sh

# Clean rebuild
CLEAN=1 ./run.sh
```

### Platform-Specific Notes

**Linux (Primary Target)**:
- Fully supported with Wayland compositor
- Native app embedding works out of the box

**macOS (Development Only)**:
- Shell runs without Wayland compositor
- Native app embedding not available
- UI development and testing only

## 🚀 Running

### Start Marathon Shell
```bash
# From build directory
./build/shell/marathon-shell

# Or use the run script
./run.sh

# With debug logging
MARATHON_DEBUG=1 ./run.sh
```

### First Launch
1. Shell will scan for apps in:
   - `~/.local/share/marathon-apps/` (Marathon apps)
   - `/usr/share/applications/` (System apps)
   - `/var/lib/flatpak/exports/share/applications/` (Flatpak apps)
   - `~/.local/share/flatpak/exports/share/applications/` (User Flatpak)

2. Default apps installed:
   - Browser, Calculator, Calendar, Camera
   - Clock, Gallery, Maps, Messages
   - Music, Notes, Phone, Settings, Terminal

### Gesture Guide
- **Swipe Up from Bottom**: Open app grid
- **Swipe Down from Top**: Quick settings
- **Swipe Right from Left**: Hub
- **Swipe Up (short)**: Peek at notifications
- **Swipe Left/Right**: Navigate between Hub/Switcher/App Grid
- **Long Press App**: Task switcher

## 📁 Project Structure

```
Marathon-Shell/
├── shell/                      # Main shell executable
│   ├── main.cpp               # Entry point, app scanning, D-Bus setup
│   ├── CMakeLists.txt         # Build configuration
│   ├── qml/                   # QML UI files
│   │   ├── Main.qml           # Application root
│   │   ├── MarathonShell.qml  # Main shell orchestration
│   │   ├── MarathonUI/        # Design system components
│   │   ├── components/        # Shell UI components
│   │   ├── stores/            # Global state management
│   │   ├── services/          # System service integrations
│   │   └── apps/              # Built-in app templates
│   └── src/                   # C++ backend
│       ├── waylandcompositor.cpp      # Wayland compositor
│       ├── waylandcompositor_dbus.cpp # D-Bus session management
│       ├── desktopfileparser.cpp      # .desktop file parser
│       ├── appmodel.cpp               # App registry
│       ├── networkmanagercpp.cpp      # NetworkManager integration
│       ├── powermanagercpp.cpp        # UPower integration
│       └── ...                        # Other services
├── apps/                       # Bundled Marathon apps
│   ├── browser/               # Web browser
│   ├── calculator/            # Calculator
│   ├── calendar/              # Calendar
│   ├── settings/              # System settings
│   ├── terminal/              # Terminal (with C++ plugin)
│   └── ...                    # Other apps
├── scripts/                    # Build and utility scripts
│   ├── build-all.sh           # Build shell + apps
│   ├── build-apps.sh          # Build apps only
│   └── validate-qml.sh        # QML linting
├── docs/                       # Documentation
│   ├── APP_DEVELOPMENT.md     # Creating Marathon apps
│   ├── UI_DESIGN_SYSTEM.md    # MarathonUI components
│   └── ...                    # Architecture docs
└── run.sh                      # Quick run script
```

## 🎨 MarathonUI Design System

Marathon includes a comprehensive design system with:

- **Theme**: Colors, typography, spacing, radius, elevation, motion
- **Core**: Buttons, text inputs, labels, dropdowns, pickers
- **Controls**: Toggles, sliders, radio buttons
- **Containers**: Cards, pages, sections, layers, scroll views
- **Lists**: Section headers, dividers, list items
- **Navigation**: Top bar, bottom bar, action bar, navigation panes
- **Feedback**: Badges, progress bars, activity indicators
- **Modals**: Dialogs, sheets, overlays
- **Effects**: Inset, outset, ripple effects

All components are themeable and responsive.

## 🔧 Development

### Creating a Marathon App

1. Create app directory in `apps/`:
   ```bash
   mkdir -p apps/myapp/assets
   ```

2. Create `manifest.json`:
   ```json
   {
     "id": "myapp",
     "name": "My App",
     "version": "1.0.0",
     "author": "Your Name",
     "description": "My awesome app",
     "icon": "assets/icon.svg",
     "entryPoint": "MyApp.qml",
     "permissions": []
   }
   ```

3. Create `MyApp.qml`:
   ```qml
   import QtQuick
   import MarathonUI.Containers 1.0
   import MarathonUI.Core 1.0

   MApp {
       appId: "myapp"
       appName: "My App"
       appIcon: "assets/icon.svg"

       MPage {
           title: "My App"
           MLabel { text: "Hello Marathon!" }
       }
   }
   ```

4. Build and install:
   ```bash
   ./scripts/build-apps.sh
   ```

See `docs/APP_DEVELOPMENT.md` for full details.

### Debugging

```bash
# Full debug output
MARATHON_DEBUG=1 ./run.sh

# Specific Qt logging
export QT_LOGGING_RULES="marathon.*.debug=true"

# GDB debugging
gdb --args ./build/shell/marathon-shell

# Valgrind memory check
valgrind --leak-check=full ./build/shell/marathon-shell
```

## 🐧 Native App Integration Details

### How It Works

1. **App Discovery**: Desktop files scanned from:
   - `/usr/share/applications/`
   - `/var/lib/flatpak/exports/share/applications/`
   - `~/.local/share/applications/`

2. **Launch Process**:
   - Marathon creates isolated environment (Wayland + D-Bus)
   - App connects to `marathon-wayland-0` compositor
   - D-Bus session provides desktop integration
   - Wayland surface embedded in `NativeAppWindow`

3. **Flatpak/Snap Handling**:
   - Automatically adds `--socket=wayland` and `--env` flags for Flatpak
   - Detects Snap apps and logs interface requirements
   - Converts `gapplication launch` commands to direct binary execution

4. **D-Bus Integration**:
   - Marathon launches `dbus-daemon --session` on startup
   - Apps can use notifications, portals, and GSettings
   - MPRIS media controls functional
   - Single-instance detection works correctly

### Supported App Types

✅ **Fully Supported**:
- Native Wayland apps (GTK4, Qt6)
- Flatpak apps with Wayland support
- GNOME apps (with gapplication conversion)
- Electron apps (with Wayland flags)

⚠️ **Partially Supported**:
- Snap apps (requires manual interface connection)
- X11 apps via XWayland (not yet implemented)

❌ **Not Supported**:
- Systemd user services
- D-Bus system bus services
- Root/privileged applications

## 🚧 Known Issues

### Build Warnings (Benign)
- `Qt6WebEngineQuick not found` - Browser uses mockup UI (expected)
- `Qt6VirtualKeyboard not found` - Keyboard support disabled (expected)
- `QTP0001/QTP0004 policy warnings` - QML module organization (harmless)

### Runtime
- Some Qt logging spam in debug mode (can be filtered with `QT_LOGGING_RULES`)
- EGL display warning on some systems (benign, hardware acceleration fallback)
- NetworkManager/UPower warnings if services not running (expected on desktop)

### Native Apps
- Apps requiring system D-Bus may not work (weather, location services)
- Some Flatpak apps need additional permissions configured
- Snap apps require `snap connect APP:wayland :wayland`

## 📖 Documentation

- **[App Development](docs/APP_DEVELOPMENT.md)** - Creating Marathon apps
- **[UI Design System](docs/UI_DESIGN_SYSTEM.md)** - MarathonUI component guide
- **[Build System](docs/BUILD_THIS.md)** - Build configuration details
- **[Development Workflow](docs/DEVELOPMENT_WORKFLOW.md)** - Contributing guide

## 🤝 Contributing

1. **Edit source files** in `apps/` or `shell/`
2. **Never edit** files in `~/.local/share/marathon-apps/` (they're build outputs)
3. **Run `./scripts/build-all.sh`** to rebuild
4. **Test thoroughly** before committing
5. **Follow the coding style** (see existing code)

## 📄 License

[Add your license here]

## 🙏 Acknowledgments

- Inspired by **BlackBerry 10 OS** gesture navigation and Hub workflow
- Built with **Qt6/QML** framework
- Uses **Wayland** compositor protocol
- Integrates with **freedesktop.org** standards

---

**Marathon Shell** - A modern mobile Linux shell for the touch-first era.

