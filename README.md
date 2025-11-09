<div align="center">
  <img src="github-media/marathon.png" alt="Marathon Shell Logo" width="200"/>
  
  # Marathon Shell
  
  **A modern, gesture-driven mobile shell for Linux** built with Qt6/QML, inspired by BlackBerry 10 and designed for touch-first interaction.
  
  [**📹 Watch Demo Video**](github-media/Screencast%20From%202025-11-09%2004-01-02.mp4)
  
  _Click above to see Marathon Shell in action: Gesture navigation, Quick Settings, and App Grid_
  
  <!-- For embedded video playback in README:
       1. Go to any GitHub Issue in this repo
       2. Drag-drop the video file from github-media/ into the comment box
       3. GitHub will upload and give you a user-images.githubusercontent.com URL
       4. Replace this link with: <video src="that-url" controls></video>
  -->
</div>

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

### Initial Setup

```bash
# Clone the repository with submodules
git clone --recursive https://github.com/patrickjquinn/Marathon-Shell.git
cd Marathon-Shell

# If you already cloned without --recursive, initialize submodules:
git submodule update --init --recursive
```

**Note:** The project uses the [AsyncFuture](https://github.com/vpicaver/asyncfuture) library as a Git submodule (`third-party/asyncfuture/`). This provides Promise-like async programming with QFuture.

### Quick Start
```bash
# Build everything (shell + apps + UI library)
./scripts/build-all.sh

# Or build individually:
cd build && cmake --build .     # Shell only (after initial build-all.sh)
./scripts/build-apps.sh         # Apps only
```

**Note:** There is no separate `build-shell.sh` - use `build-all.sh` for initial builds, then incremental builds via `run.sh`.

### Development Build
```bash
# Incremental build (fast) - automatically rebuilds everything
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
│   │   ├── components/        # Shell UI components
│   │   ├── stores/            # Global state management (UIStore, SystemControlStore, etc.)
│   │   ├── services/          # System service integrations
│   │   ├── core/              # Core utilities (Logger, Constants)
│   │   └── utils/             # Utility functions (Async wrapper)
│   ├── src/                   # C++ backend
│   │   ├── waylandcompositor*.{cpp,h}     # Wayland compositor + D-Bus
│   │   ├── desktopfileparser.{cpp,h}      # .desktop file parser
│   │   ├── appmodel.{cpp,h}               # App registry
│   │   ├── networkmanagercpp.{cpp,h}      # NetworkManager integration
│   │   ├── powermanagercpp.{cpp,h}        # UPower integration
│   │   ├── marathonapp*.{cpp,h}           # App packaging/verification/installation
│   │   └── ...                            # Other service managers
│   └── resources/             # Embedded assets
│       ├── images/            # Icons (Lucide icon set)
│       ├── fonts/             # Slate font family
│       └── sounds/            # System sounds (BB10-inspired)
├── marathon-ui/                # MarathonUI Design System (monorepo)
│   ├── Theme/                 # Colors, typography, spacing
│   ├── Core/                  # Buttons, labels, inputs, icons
│   ├── Controls/              # Toggles, sliders, radio buttons
│   ├── Containers/            # Pages, cards, sections, scroll views
│   ├── Lists/                 # List items, dividers
│   ├── Navigation/            # Top bar, bottom bar, action bar
│   ├── Feedback/              # Badges, progress bars
│   ├── Modals/                # Dialogs, sheets, overlays
│   └── Effects/               # Ripple, inset/outset effects
├── marathon-core/              # Shared C++ library (monorepo)
│   └── src/                   # App management infrastructure
│       ├── marathonapppackager.{cpp,h}    # .marathon package creation
│       ├── marathonappverifier.{cpp,h}    # GPG signature verification
│       ├── marathonappinstaller.{cpp,h}   # App installation logic
│       ├── marathonappregistry.{cpp,h}    # App catalog
│       └── marathonappscanner.{cpp,h}     # App discovery
├── apps/                       # Bundled Marathon apps
│   ├── browser/               # Web browser
│   ├── calculator/            # Calculator
│   ├── calendar/              # Calendar & events
│   ├── settings/              # System settings
│   ├── store/                 # App Store (uses marathon-core)
│   ├── terminal/              # Terminal emulator
│   └── ...                    # Phone, Messages, Clock, Maps, etc.
├── tools/                      # Developer tools
│   └── marathon-dev/          # CLI tool for app development
│       └── main.cpp           # package, sign, verify, install, init commands
├── third-party/                # External dependencies
│   └── asyncfuture/           # Git submodule: Promise-like QFuture API
├── scripts/                    # Build and utility scripts
│   ├── build-all.sh           # Build UI lib + shell + apps
│   ├── build-apps.sh          # Build apps only
│   ├── validate-qml.sh        # QML linting
│   ├── configure-rt-linux.sh  # Real-time scheduling setup
│   └── ...                    # Other utilities
├── docs/                       # Documentation
│   ├── APP_DEVELOPMENT.md     # Creating Marathon apps
│   ├── UI_DESIGN_SYSTEM.md    # MarathonUI components
│   ├── DEVELOPER_GUIDE.md     # marathon-dev CLI usage
│   ├── CODE_SIGNING_GUIDE.md  # GPG signing for apps
│   └── ...                    # More architecture docs
├── systemd/                    # Service files
│   └── marathon-shell.service # Systemd unit for Marathon
├── udev/                       # Hardware access rules
│   └── 70-marathon-shell.rules
├── polkit/                     # Privilege elevation policies
│   └── org.marathonos.shell.policy
├── CMakeLists.txt              # Root build configuration
├── marathon-config.json        # Build-time configuration system
├── .gitmodules                 # Git submodule definitions
└── run.sh                      # Quick development run script
```

## 📦 Marathon App Ecosystem

Marathon has a complete app distribution system with packaging, code signing, and an integrated App Store.

### `.marathon` Package Format
- **ZIP-based** archive containing app files
- **manifest.json**: App metadata (id, name, version, permissions)
- **SIGNATURE.txt**: GPG detached signature (optional but recommended)
- **Structured layout**: QML files, assets, optional C++ plugins

### Code Signing with GPG
```bash
# Generate GPG key for signing
gpg --full-generate-key

# Sign your app
marathon-dev sign apps/myapp

# Verify signature
marathon-dev verify myapp.marathon
```

Apps can be signed with GPG for authenticity. The shell verifies signatures during installation and displays trust status. See `docs/CODE_SIGNING_GUIDE.md`.

### App Store Integration
Marathon includes a built-in **App Store** app that:
- **Browses** available Marathon apps
- **Installs/uninstalls** apps with one tap
- **Shows** app details, permissions, and trust status
- **Updates** apps when new versions are available

The App Store uses the `marathon-core` library (same as `marathon-dev`) ensuring consistent behavior between CLI and GUI.

### Runtime Permissions
Apps can request permissions in `manifest.json`:
```json
{
  "permissions": [
    "network",
    "location",
    "camera",
    "microphone",
    "contacts",
    "calendar",
    "storage"
  ]
}
```

The shell enforces permissions via a **D-Bus Permission Portal** (`org.marathonos.shell.PermissionPortal`). Users can review and revoke permissions in Settings → Apps.

See `docs/PERMISSION_GUIDE.md` and `docs/ECOSYSTEM_IMPLEMENTATION_SUMMARY.md` for details.

## 🎨 MarathonUI Design System

Marathon includes a comprehensive design system with:

- **Theme**: Colors, typography, spacing, radius, elevation, motion
- **Core**: Buttons, text inputs, labels, dropdowns, pickers, icons
- **Controls**: Toggles, sliders, radio buttons, checkboxes
- **Containers**: Cards, pages, sections, layers, scroll views
- **Lists**: Section headers, dividers, list items
- **Navigation**: Top bar, bottom bar, action bar, navigation panes
- **Feedback**: Badges, progress bars, activity indicators
- **Modals**: Dialogs, sheets, overlays
- **Effects**: Inset, outset, ripple effects

All components are themeable and responsive. The UI library is built as a **monorepo** (`marathon-ui/`) and installed to `~/.local/share/marathon-ui/` for use by both the shell and apps.

## ⚙️ Configuration System

Marathon Shell uses a centralized **build-time configuration system** (`marathon-config.json`) that acts like Android's `build.xml`, providing a single source of truth for all shell parameters.

### What's Configurable

**Everything** can be customized without touching code:

- **Responsive Sizing**: Base DPI, scale factors, screen breakpoints
- **Z-Index Layering**: UI component stacking order
- **Gesture Physics**: Swipe thresholds, flick velocities, inertia
- **Animation Timing**: Durations for all transitions
- **Layout Dimensions**: Status bar, nav bar, action bar heights
- **Typography**: Font sizes, families (Inter, JetBrains Mono)
- **Spacing System**: XS/S/M/L/XL/XXL spacing values
- **Touch Targets**: BB10-inspired sizes (large/medium/small)
- **App Grid**: Columns, rows, breakpoints for phone/tablet/desktop
- **Quick Settings**: Tile sizes, grid layout, max width
- **Bottom Bar**: Icon margins, shortcut visibility
- **Feature Flags**: Enable/disable Wayland, Bluetooth, WiFi, etc.

### Customizing at Build Time

1. Edit `marathon-config.json` in the project root:
   ```json
   {
     "animations": {
       "fast": 100,
       "normal": 150,
       "slow": 250
     },
     "gestures": {
       "quickSettingsDismissThreshold": 0.25
     },
     "appGrid": {
       "columnsPhone": 4,
       "rowsPhone": 5
     }
   }
   ```

2. Rebuild:
   ```bash
   ./run.sh
   ```

3. Your changes take effect immediately!

### Benefits

- **No code changes** needed for common UI tweaks
- **Uniform scaling** across all form factors
- **Easy A/B testing** of gesture thresholds
- **Device-specific builds** (phone vs tablet vs desktop)
- **Sane defaults** with graceful fallbacks
- **Self-documenting** (JSON has descriptions)

### Advanced: Device-Specific Configs

Create device profiles:
```bash
# OnePlus 6 (high-DPI phone)
cp marathon-config.json marathon-config-oneplus6.json
# Edit for 2280x1080, 402 DPI

# PinePhone (low-DPI phone)  
cp marathon-config.json marathon-config-pinephone.json
# Edit for 1440x720, 270 DPI

# Build with specific config:
cp marathon-config-oneplus6.json marathon-config.json
./run.sh
```

## 🔧 Development

### Marathon Developer CLI (`marathon-dev`)

The `marathon-dev` tool is a comprehensive CLI for app development, packaging, and distribution.

**Build the tool:**
```bash
./scripts/build-all.sh  # Builds marathon-dev along with everything else
# Tool location: ./build/tools/marathon-dev/marathon-dev
```

**Available Commands:**
```bash
# Create a new app from template
marathon-dev init myapp

# Package an app into .marathon format
marathon-dev package apps/myapp myapp.marathon

# Sign an app with GPG
marathon-dev sign apps/myapp [key-id]

# Verify app signature
marathon-dev verify myapp.marathon

# Install app to Marathon
marathon-dev install myapp.marathon

# Uninstall app
marathon-dev uninstall myapp

# List installed apps
marathon-dev list

# Show app details
marathon-dev info myapp

# Validate app structure
marathon-dev validate apps/myapp
```

See `docs/DEVELOPER_GUIDE.md` and `docs/CODE_SIGNING_GUIDE.md` for full details.

### Creating a Marathon App (Manual)

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

