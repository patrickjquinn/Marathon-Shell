<div align="center">
  <img src="github-media/marathon.png" alt="Marathon Shell Logo" width="200"/>
  
  # Marathon Shell
  
  **A Wayland compositor and mobile-oriented application shell for Linux**
  
  [Watch Demo Video](github-media/Screencast%20From%202025-11-09%2004-01-02.mp4)
</div>

---

Marathon Shell is a Wayland compositor and mobile-oriented application shell for Linux, designed for touch-first interaction. The shell provides gesture-based navigation, application management, and system service integration, with support for both QML-based Marathon apps and native Linux desktop applications.

## Architecture

Marathon Shell consists of four main components:

1. **Wayland Compositor** - Qt6-based compositor for embedding native Linux applications
2. **QML Shell Interface** - Touch-optimized UI with gesture navigation inspired by BlackBerry 10
3. **Application Framework** - QML-based app development platform with optional C++ plugins
4. **System Integration** - D-Bus services for network, power, Bluetooth, telephony, and other system functions

### Core Features

**Shell Interface:**
- Gesture-based navigation (swipe up for app grid, down for quick settings)
- Hub workflow for unified notifications and messaging
- Active Frames for live app previews in task switcher
- Peek gesture for quick notification preview
- Physics-based scrolling and transitions

**Native Application Support:**
- Wayland protocol implementation for embedding Linux apps
- D-Bus session integration for desktop services
- Flatpak and Snap container support with automatic permission handling
- gapplication command conversion for GNOME app compatibility

**Application Development:**
- QML-based app framework with MarathonUI design system
- `.marathon` package format with GPG code signing
- Runtime permission system via D-Bus portal
- Lifecycle management (background/foreground states)

**System Services:**
- Network management (WiFi, cellular via NetworkManager)
- Power management (battery, profiles via UPower)
- Bluetooth (device pairing via BlueZ)
- Telephony (calls, SMS via ModemManager)
- Display, audio, and notification services

## Requirements

### Build Dependencies

**Fedora/RHEL:**
```bash
sudo dnf install cmake ninja-build gcc-c++ \
    qt6-qtbase-devel \
    qt6-qtdeclarative-devel \
    qt6-qtwayland-devel \
    qt6-qtmultimedia-devel \
    qt6-qtsvg-devel \
    qt6-qtlocation-devel \
    qt6-qtpositioning-devel \
    qt6-qtsensors-devel \
    pam-devel \
    hunspell-devel \
    hunspell-en-US
```

**Ubuntu/Debian:**
```bash
sudo apt install cmake ninja-build g++ \
    qt6-base-dev \
    qt6-declarative-dev \
    qt6-wayland-dev \
    qt6-multimedia-dev \
    qt6-svg-dev \
    qt6-sensors-dev \
    qt6-dbus-dev \
    libpam0g-dev \
    dbus-daemon \
    libhunspell-dev \
    hunspell-en-us
```

### Runtime Requirements

- Qt 6.5 or later (tested with Qt 6.9.x)
- Wayland display server support
- D-Bus session bus
- Linux kernel 5.10 or later

### Optional Dependencies

- NetworkManager - WiFi and cellular network management
- UPower - Battery and power profile management  
- BlueZ - Bluetooth device management
- ModemManager - Cellular modem and telephony support
- qt6-qtvirtualkeyboard-devel - On-screen keyboard support

### Browser Requirement
- **qt6-qtwebengine-devel** (Fedora) / **qml-module-qtwebengine** (Ubuntu/Debian)
  - Required for the **Browser** app to function.
  - If missing, the Browser app will fail to launch with `module "QtWebEngine" is not installed`.

## Building

> **⚠️ Important**: If you encounter the error `module "MarathonUI.Theme" is not installed`, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md#-error-module-marathonuitheme-is-not-installed) for a quick fix.

### Initial Setup

Clone the repository with submodules:

```bash
git clone --recursive https://github.com/patrickjquinn/Marathon-Shell.git
cd Marathon-Shell
```

If you cloned without `--recursive`, initialize submodules:

```bash
git submodule update --init --recursive
```

The project uses [AsyncFuture](https://github.com/vpicaver/asyncfuture) as a git submodule for Promise-like async programming with QFuture.

### Build All Components (Recommended)

```bash
# Build shell, UI library, and apps
./scripts/build-all.sh
```

This builds:
- **MarathonUI** design system library (QML modules)
- **Marathon Core** library (app management)
- **Marathon Shell** executable
- All bundled applications
- Developer tools

**And installs** MarathonUI to `~/.local/share/marathon-ui` (required for shell to run).

### Incremental Builds

```bash
# Quick rebuild and run (incremental)
./run.sh

# Clean rebuild
CLEAN=1 ./run.sh

# Rebuild apps only
./scripts/build-apps.sh

# Rebuild shell only
cd build && cmake --build .
```

### Manual CMake Build (Alternative)

The provided build scripts are recommended, but you can also use CMake directly:

```bash
# CRITICAL: Build and install MarathonUI FIRST (required for shell to run)
cmake -B build -S . -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(nproc)
cmake --install build  # Installs MarathonUI to ~/.local/share/marathon-ui

# Now run the shell
./build/shell/marathon-shell-bin

# Apps (optional, installs to ~/.local/share/marathon-apps by default)
cmake -B build-apps -S apps -DCMAKE_BUILD_TYPE=Release
cmake --build build-apps -j$(nproc)
cmake --install build-apps
```

**For system-wide installation** (requires root):
```bash
# System-wide MarathonUI (installs to /usr/lib/qt6/qml/MarathonUI)
cmake -B build -S . -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release
sudo cmake --install build

# System-wide apps (installs to /usr/share/marathon-apps)
cmake -B build-apps -S apps -DMARATHON_APPS_DIR=/usr/share/marathon-apps
sudo cmake --install build-apps
```

> **⚠️ CRITICAL**: Marathon Shell **requires MarathonUI to be installed** before it can run. If you see `module "MarathonUI.Theme" is not installed`, run `cmake --install build`.

> **Note**: Apps default to `~/.local/share/marathon-apps` to avoid permission issues during development. This ensures the build works out of the box without sudo, making it IDE-friendly.

### Platform Support

**Linux (Primary Target):**
- Full Wayland compositor support
- Native app embedding functional
- All system services available

**macOS (Development Only):**
- Shell runs without Wayland compositor
- UI development and testing only
- Native app embedding not available

## Running

### First-Time System Setup (Required)

> **⚠️ CRITICAL**: Marathon Shell requires system permissions and services for full mobile functionality. Run the setup script once before first use:

```bash
# One-time system setup (requires sudo)
./scripts/setup-system.sh
```

This configures:
- **Brightness control** permissions (udev rule for `/sys/class/backlight`)
- **Bluetooth** service (installs and enables BlueZ)  
- **PAM authentication** (copies config to `/etc/pam.d/marathon-shell`)

### Start Marathon Shell

```bash
# From project directory
./run.sh

# Or directly from build directory
./build/shell/marathon-shell

# With debug logging
MARATHON_DEBUG=1 ./run.sh
```

## System Configuration

### PAM Authentication Setup (Required)

> **⚠️ CRITICAL**: Marathon Shell requires a PAM configuration file to authenticate users. Without this file, password authentication will fail with "Authentication failure" errors.

The shell uses PAM (Pluggable Authentication Modules) for system password authentication. Install the PAM configuration file:

```bash
sudo cp pam.d/marathon-shell /etc/pam.d/marathon-shell
```

This file configures:
- System password authentication via `pam_unix.so`
- Rate limiting (5 failed attempts = 5 minute lockout) via `pam_faillock.so`
- Optional fingerprint authentication via `pam_fprintd.so`
- Session integration with systemd-logind

**Note**: Without this file, you won't be able to unlock the shell with your password. If you see PAM authentication failures in the logs, this is the fix.

### Power Management Permissions

Marathon Shell implements opportunistic suspend with kernel wakelocks and RTC wake alarms. These features require specific permissions to function optimally.

#### Wakelock Support

For kernel wakelock support (`/sys/power/wake_lock`), the shell process needs `CAP_BLOCK_SUSPEND` capability:

```bash
# Option 1: Grant capability to the binary (recommended for production)
sudo setcap cap_block_suspend+ep /path/to/marathon-shell-bin

# Option 2: Use udev rules for development (easier for testing)
# Create /etc/udev/rules.d/99-marathon-power.rules:
SUBSYSTEM=="power", ACTION=="add", RUN+="/bin/chmod 666 /sys/power/wake_lock /sys/power/wake_unlock"
SUBSYSTEM=="rtc", KERNEL=="rtc0", MODE="0664", GROUP="users"

# Reload udev rules:
sudo udevadm control --reload-rules
sudo udevadm trigger
```

**Note**: If wakelock permissions are not available, Marathon Shell automatically falls back to systemd-logind inhibitor locks, which provide similar functionality without requiring special permissions.

#### RTC Wake Alarm

For RTC alarm support (`/sys/class/rtc/rtc0/wakealarm`), the shell needs write access to the RTC device:

```bash
# Add your user to the appropriate group (usually dialout or users)
sudo usermod -a -G dialout $USER

# Or use udev rule (included in the snippet above)
SUBSYSTEM=="rtc", KERNEL=="rtc0", MODE="0664", GROUP="dialout"
```

#### Verification

Check if power management features are available:

```bash
# Check wakelock support
ls -la /sys/power/wake_lock /sys/power/wake_unlock

# Check RTC alarm support
ls -la /sys/class/rtc/rtc0/wakealarm

# Test wakelock (should not error if permissions are correct)
echo "test_lock" | sudo tee /sys/power/wake_lock
cat /sys/power/wake_lock
echo "test_lock" | sudo tee /sys/power/wake_unlock
```

### XDG Desktop Portals

Marathon Shell uses XDG Desktop Portals for secure permission management (Camera, Location, Microphone).

**Droidian / Linux Mobile:**
Ensure `xdg-desktop-portal` and a backend (e.g., `xdg-desktop-portal-phosh` or `xdg-desktop-portal-gtk`) are installed.

```bash
sudo apt install xdg-desktop-portal xdg-desktop-portal-phosh
```

If portals are not available, Marathon Shell automatically falls back to a custom permission dialog.

### First Launch

On first launch, Marathon Shell scans for applications in:

- `~/.local/share/marathon-apps/` - Marathon apps
- `/usr/share/applications/` - System applications
- `/var/lib/flatpak/exports/share/applications/` - Flatpak apps
- `~/.local/share/flatpak/exports/share/applications/` - User Flatpak apps

Default Marathon apps include: Browser, Calculator, Calendar, Camera, Clock, Gallery, Maps, Messages, Music, Notes, Phone, Settings, Store, and Terminal.

### Gesture Navigation

- **Swipe up from bottom** - Open app grid
- **Swipe down from top** - Quick settings panel
- **Swipe right from left edge** - Hub (notifications and messages)
- **Swipe up (short)** - Peek at notifications
- **Swipe left/right in app grid** - Navigate between Hub/Switcher/Grid
- **Long press app icon** - Open task switcher

## Project Structure

```
Marathon-Shell/
├── shell/                      # Main shell executable
│   ├── main.cpp               # Entry point, app scanning, D-Bus setup
│   ├── qml/                   # QML UI implementation
│   │   ├── MarathonShell.qml  # Main shell orchestration
│   │   ├── components/        # Shell UI components
│   │   ├── stores/            # Global state management
│   │   ├── services/          # System service integrations
│   │   └── core/              # Core utilities
│   ├── src/                   # C++ backend implementation
│   │   ├── waylandcompositor* # Wayland compositor + D-Bus
│   │   ├── desktopfileparser* # .desktop file parser
│   │   ├── appmodel*          # App registry
│   │   ├── networkmanagercpp* # NetworkManager integration
│   │   ├── powermanagercpp*   # UPower integration
│   │   └── securitymanager*   # PAM authentication
│   └── resources/             # Embedded assets (icons, fonts, sounds)
├── marathon-ui/                # MarathonUI Design System
│   ├── Theme/                 # Colors, typography, spacing, motion
│   ├── Core/                  # Buttons, inputs, labels, icons
│   ├── Controls/              # Toggles, sliders, radio buttons
│   ├── Containers/            # Pages, cards, sections, scroll views
│   ├── Lists/                 # List items, dividers
│   ├── Navigation/            # Top bar, bottom bar, action bar
│   ├── Feedback/              # Badges, progress bars, activity indicators
│   ├── Modals/                # Dialogs, confirmation sheets, overlays
│   └── Effects/               # Ripple, inset/outset effects
├── marathon-core/              # Shared C++ library
│   └── src/                   # App management infrastructure
│       ├── marathonapppackager*    # .marathon package creation
│       ├── marathonappverifier*    # GPG signature verification
│       ├── marathonappinstaller*   # App installation logic
│       ├── marathonappregistry*    # App catalog
│       └── marathonappscanner*     # App discovery
├── apps/                       # Bundled Marathon apps
│   ├── browser/               # Web browser
│   ├── calculator/            # Calculator
│   ├── settings/              # System settings
│   ├── store/                 # App store
│   ├── terminal/              # Terminal emulator (C++ plugin)
│   └── ...                    # Other bundled apps
├── tools/                      # Developer tools
│   └── marathon-dev/          # CLI for app development
├── third-party/                # External dependencies
│   └── asyncfuture/           # Promise-like QFuture API (submodule)
├── scripts/                    # Build and utility scripts
├── docs/                       # Documentation
├── systemd/                    # Service files
├── udev/                       # Hardware access rules
├── polkit/                     # Privilege elevation policies
├── pam.d/                      # PAM authentication config
└── CMakeLists.txt              # Root build configuration
```

## Marathon App Ecosystem

### Package Format

Marathon apps use the `.marathon` package format:

- ZIP-based archive containing app files
- `manifest.json` - App metadata (id, name, version, permissions)
- `SIGNATURE.txt` - GPG detached signature (optional but recommended)
- Structured layout with QML files, assets, and optional C++ plugins

### Code Signing

```bash
# Generate GPG key
gpg --full-generate-key

# Sign app
marathon-dev sign apps/myapp

# Verify signature
marathon-dev verify myapp.marathon
```

Apps can be signed with GPG for authenticity verification. The shell verifies signatures during installation and displays trust status. See `docs/CODE_SIGNING_GUIDE.md` for details.

### Permissions System

Apps request permissions in `manifest.json`:

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

Permissions are enforced via D-Bus Permission Portal (`org.marathonos.shell.PermissionPortal`). Users can review and revoke permissions in Settings.

See `docs/PERMISSION_GUIDE.md` for implementation details.

### App Store

Marathon includes an integrated App Store for browsing, installing, and updating Marathon apps. The store uses the same `marathon-core` library as the `marathon-dev` CLI tool, ensuring consistent behavior.



## Development

### marathon-dev CLI Tool

The `marathon-dev` tool provides comprehensive app development functionality:

```bash
# Create new app from template
./build/tools/marathon-dev/marathon-dev init myapp

# Package app
./build/tools/marathon-dev/marathon-dev package apps/myapp myapp.marathon

# Sign app
./build/tools/marathon-dev/marathon-dev sign apps/myapp [key-id]

# Verify signature
./build/tools/marathon-dev/marathon-dev verify myapp.marathon

# Install app
./build/tools/marathon-dev/marathon-dev install myapp.marathon

# List installed apps
./build/tools/marathon-dev/marathon-dev list

# Show app details
./build/tools/marathon-dev/marathon-dev info myapp

# Validate app structure
./build/tools/marathon-dev/marathon-dev validate apps/myapp
```

See `docs/DEVELOPER_GUIDE.md` for complete CLI documentation.

### Creating Marathon Apps

Marathon apps are QML-based with optional C++ plugins.

**Minimal app structure:**

```
apps/myapp/
├── CMakeLists.txt          # Build configuration
├── manifest.json           # App metadata
├── MyApp.qml              # Entry point
├── qmldir                 # QML module definition
└── assets/                # Icons and images
    └── icon.svg
```

**Example manifest.json:**

```json
{
  "id": "myapp",
  "name": "My App",
  "version": "1.0.0",
  "author": "Your Name",
  "description": "Application description",
  "icon": "assets/icon.svg",
  "entryPoint": "MyApp.qml",
  "permissions": [],
  "minShellVersion": "1.0.0"
}
```

**Example MyApp.qml:**

```qml
import QtQuick
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core

MApp {
    appId: "myapp"
    appName: "My App"
    
    content: MPage {
        title: "My App"
        
        MLabel {
            anchors.centerIn: parent
            text: "Hello Marathon!"
        }
    }
}
```

Build and install:

```bash
./scripts/build-apps.sh
```

See `docs/APP_DEVELOPMENT.md` for complete app development guide.

### Debugging

```bash
# Enable debug logging
MARATHON_DEBUG=1 ./run.sh

# Qt logging rules
export QT_LOGGING_RULES="marathon.*.debug=true"
./run.sh

# GDB debugging
gdb --args ./build/shell/marathon-shell

# Valgrind memory check
valgrind --leak-check=full ./build/shell/marathon-shell
```

### QML Validation

```bash
# Validate all QML files
./scripts/validate-qml.sh

# Validate specific file
qmllint apps/myapp/MyApp.qml
```

## Native Application Integration

### Wayland Compositor

Marathon Shell implements a Wayland compositor that embeds native Linux applications as first-class citizens in the shell environment.

**Application Discovery:**
- Desktop files scanned from standard freedesktop.org locations
- Flatpak and Snap apps detected automatically
- gapplication commands converted to direct binary execution

**Launch Process:**
1. Marathon creates isolated Wayland + D-Bus environment
2. Application connects to `marathon-wayland-0` compositor socket
3. Wayland surface embedded in shell UI via `WaylandShellSurfaceItem`
4. D-Bus session provides desktop service integration

**Flatpak Support:**
- Automatic `--socket=wayland` flag addition
- Environment variables passed for compositor connection
- Permission handling for sandboxed apps

**Snap Support:**
- Interface detection and logging
- Manual interface connection may be required: `snap connect APP:wayland :wayland`

### Supported Application Types

**Fully Supported:**
- Native Wayland applications (GTK4, Qt6)
- Flatpak applications with Wayland support
- GNOME applications (with gapplication conversion)
- Electron applications (with Wayland flags)

**Partially Supported:**
- Snap applications (requires manual interface connection)
- X11 applications via XWayland (not yet implemented)

**Not Supported:**
- Applications requiring systemd user services
- Applications requiring system D-Bus services
- Root/privileged applications

## Known Issues

### Build Warnings

- `Qt6WebEngineQuick not found` - Browser uses mockup UI (expected if QtWebEngine not installed)

**Note:** Marathon OS uses a fully custom keyboard implementation (not Qt VirtualKeyboard). The custom keyboard is BlackBerry 10-inspired with Marathon design system integration and includes:
- **Hunspell spell-checking** for word prediction and auto-correction
- **Content-aware layouts** (email, URL, number, phone)
- **Word Fling** gesture (swipe up on a key to accept prediction)
- **Predictive Spacing** (BB10-style automatic spacing)

### Runtime

- Qt logging verbosity in debug mode (can be filtered with `QT_LOGGING_RULES`)
- EGL display warnings on some systems (hardware acceleration fallback, benign)
- NetworkManager/UPower warnings if services not running (expected on non-systemd systems)

### Native Apps

- Applications requiring system D-Bus may not function correctly
- Some Flatpak applications need additional permission configuration
- Snap applications require manual Wayland interface connection

## Documentation

- [App Development Guide](docs/APP_DEVELOPMENT.md) - Creating Marathon apps
- [UI Design System](docs/UI_DESIGN_SYSTEM.md) - MarathonUI component reference

- [Development Workflow](docs/DEVELOPMENT_WORKFLOW.md) - Development process and conventions
- [Developer CLI Guide](docs/DEVELOPER_GUIDE.md) - marathon-dev tool usage
- [Code Signing Guide](docs/CODE_SIGNING_GUIDE.md) - GPG signing for apps
- [Permission Guide](docs/PERMISSION_GUIDE.md) - Permission system implementation
- [Publishing Guide](docs/PUBLISHING_GUIDE.md) - App distribution process
- [Keyboard Specification](docs/KEYBOARD_SPEC.md) - Virtual keyboard implementation
- [QML Validation](docs/QML_VALIDATION.md) - QML linting and validation
- [RT Scheduling](docs/RT_SCHEDULING.md) - Real-time scheduling configuration

## Contributing

1. Edit source files in `apps/`, `shell/`, or `marathon-ui/`
2. Never edit files in `~/.local/share/marathon-apps/` (build artifacts)
3. Run `./scripts/build-all.sh` to rebuild after changes
4. Test thoroughly before committing
5. Follow existing code style and conventions

See `docs/DEVELOPMENT_WORKFLOW.md` for detailed contribution workflow.

## License

Apache License 2.0. See [LICENSE](LICENSE) file for details.

## Acknowledgments

Marathon Shell is inspired by BlackBerry 10's gesture navigation and Hub workflow. Built with Qt6/QML and implementing the Wayland compositor protocol for native Linux application support. System integration follows freedesktop.org standards.
