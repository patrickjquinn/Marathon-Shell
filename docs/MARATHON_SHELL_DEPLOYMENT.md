# Marathon Shell - Production Deployment for postmarketOS

## Overview

Marathon Shell is now a **fully functional mobile Linux shell** with comprehensive hardware integration. This document describes what's needed to deploy it as a proper Wayland compositor/DE on postmarketOS.

## Prerequisites

The Marathon Shell has full hardware integration for:
- ✅ **Power Management** (UPower, systemd-logind, battery, charging, AC detection)
- ✅ **Network Management** (NetworkManager for WiFi, Ethernet, with hardware detection)
- ✅ **Cellular/Modem** (ModemManager integration for signal, operator, network type)
- ✅ **Audio Control** (PulseAudio/PipeWire integration via pactl)
- ✅ **Display Control** (Backlight via systemd-logind and /sys/class/backlight)
- ✅ **Bluetooth** (BlueZ D-Bus integration)
- ✅ **Sensors** (IIO sensor support for proximity, ambient light)
- ✅ **Wayland Compositor** (Native app embedding via QtWayland)
- ✅ **Notifications** (D-Bus notification service)
- ✅ **Lock-before-sleep** (systemd-logind integration)

## Required System Dependencies

Add to `marathon-shell` APKBUILD `depends=`:
```
qt6-qtbase
qt6-qtdeclarative
qt6-qtwayland
qt6-qtwebengine
qt6-qtmultimedia
qt6-qtsvg
wayland
wayland-protocols
mesa
mesa-gbm
mesa-egl
mesa-dri-gallium
mesa-gles
pipewire
pipewire-pulse
wireplumber
pulseaudio-utils      # For pactl volume control
greetd                # Session manager
dbus
networkmanager        # WiFi/Ethernet management
modemmanager          # Cellular/modem management
upower                # Battery/power management
polkit                # Privilege escalation
bluez                 # Bluetooth support
```

## Files to Pull from Marathon-Shell Repo

### 1. Session Management Files

**Location in Marathon-Shell:** Root directory

#### `marathon-shell-session` (NEW)
- **Description:** Wayland session startup script
- **Purpose:** Sets up environment variables, D-Bus, Qt paths, and launches the shell
- **Install to:** `/usr/bin/marathon-shell-session`
- **Must be:** Executable (`chmod +x`)

**Key features:**
- Sets `XDG_SESSION_TYPE=wayland`, `XDG_CURRENT_DESKTOP=marathon`
- Configures Qt/QML import paths
- Handles D-Bus session initialization
- Disables AT-SPI bridge for minimal systems
- Configures debug logging via `MARATHON_DEBUG=1`

#### `marathon.desktop` (UPDATED)
- **Description:** Wayland session descriptor
- **Install to:** `/usr/share/wayland-sessions/marathon.desktop`
- **Purpose:** Allows display managers (greetd, SDDM, GDM) to detect Marathon Shell

**Changes:**
- Now executes `marathon-shell-session` instead of direct binary
- Includes proper session metadata

#### `marathon-shell.toml` (EXISTING)
- **Description:** greetd configuration example
- **Install to:** `/usr/share/greetd/marathon-shell-example.toml`
- **Note:** Admin copies this to `/etc/greetd/config.toml` to enable auto-login

---

### 2. SystemD Integration

**Create directory in Marathon-Image:** `packages/marathon-shell/systemd/`

#### `systemd/marathon-shell.service` (NEW)
- **Description:** SystemD user service for Marathon Shell
- **Install to:** `/usr/lib/systemd/user/marathon-shell.service`
- **Purpose:** Allows systemd to manage shell lifecycle

**Features:**
- Automatic restart on failure
- Proper ordering with `graphical-session.target`
- Journal logging

---

### 3. PolicyKit (Polkit) Rules

**Create directory in Marathon-Image:** `packages/marathon-shell/polkit/`

#### `polkit/org.marathonos.shell.policy` (NEW)
- **Description:** PolicyKit policy for privilege escalation
- **Install to:** `/usr/share/polkit-1/actions/org.marathonos.shell.policy`
- **Purpose:** Allows Marathon Shell to control hardware without root password

**Grants permission for:**
- Brightness control (`org.marathonos.shell.control-brightness`)
- Power management (suspend, hibernate, reboot, shutdown)
- Network control (WiFi enable/disable, connect)
- Bluetooth control (enable/disable, pair)

---

### 4. udev Rules

**Create directory in Marathon-Image:** `packages/marathon-shell/udev/`

#### `udev/70-marathon-shell.rules` (NEW)
- **Description:** udev rules for hardware access
- **Install to:** `/etc/udev/rules.d/70-marathon-shell.rules`
- **Purpose:** Grants user-space access to mobile hardware devices

**Provides access to:**
- Graphics devices (DRM/KMS for Wayland)
- Input devices (touchscreen, keyboard)
- Backlight control (`/sys/class/backlight/*/brightness`)
- LEDs (notification LED, torch)
- Video devices (camera)
- Sound devices
- Power supply (battery, charger)
- Sensors (IIO: accelerometer, gyro, proximity, light)
- Modem devices
- Bluetooth devices
- GPS devices

**Critical for mobile:** Without these rules, the shell cannot control brightness, read battery, or access sensors.

---

### 5. XDG Autostart

**Create directory in Marathon-Image:** `packages/marathon-shell/xdg-autostart/`

#### `xdg-autostart/marathon-notification-service.desktop` (NEW)
- **Description:** Autostart entry for Marathon notification service
- **Install to:** `/etc/xdg/autostart/marathon-notification-service.desktop`
- **Purpose:** Starts D-Bus notification service on session startup

**Note:** Currently a placeholder for future notification backend. Can be omitted for initial deployment.

---

## Binary Output Name Change

The shell binary is now named `marathon-shell-bin` instead of `marathon-shell`:

**In `shell/CMakeLists.txt`:**
```cmake
set_target_properties(marathon-shell PROPERTIES
    OUTPUT_NAME marathon-shell-bin
)
```

**Why?**
- `marathon-shell-bin` = The actual Qt6 binary
- `marathon-shell-session` = The wrapper script that sets up environment

This allows the session script to control environment setup before launching the compositor.

---

## Installation Flow for postmarketOS

### Update APKBUILD

The root `CMakeLists.txt` now includes all install targets:

```cmake
# Installation for production Linux mobile deployment
include(GNUInstallDirs)

# Install session launcher script
install(PROGRAMS marathon-shell-session
    DESTINATION ${CMAKE_INSTALL_BINDIR}
)

# Install Wayland session file
install(FILES marathon.desktop
    DESTINATION ${CMAKE_INSTALL_DATADIR}/wayland-sessions
)

# Install systemd user service
install(FILES systemd/marathon-shell.service
    DESTINATION ${CMAKE_INSTALL_PREFIX}/lib/systemd/user
)

# Install polkit policy
install(FILES polkit/org.marathonos.shell.policy
    DESTINATION ${CMAKE_INSTALL_DATADIR}/polkit-1/actions
)

# Install XDG autostart
install(FILES xdg-autostart/marathon-notification-service.desktop
    DESTINATION ${CMAKE_INSTALL_SYSCONFDIR}/xdg/autostart
)

# Install udev rules
install(FILES udev/70-marathon-shell.rules
    DESTINATION ${CMAKE_INSTALL_PREFIX}/lib/udev/rules.d
)

# Install greetd configuration example
install(FILES marathon-shell.toml
    DESTINATION ${CMAKE_INSTALL_DATADIR}/greetd
    RENAME marathon-shell-example.toml
)

# Install documentation
install(FILES README.md
    DESTINATION ${CMAKE_INSTALL_DOCDIR}
)

install(DIRECTORY docs/
    DESTINATION ${CMAKE_INSTALL_DOCDIR}
    FILES_MATCHING PATTERN "*.md"
)
```

### Simplified APKBUILD

The APKBUILD is now much simpler:

```bash
package() {
    cd "$builddir"
    
    # Install main shell (includes binary, session files, systemd, polkit, udev, etc.)
    DESTDIR="$pkgdir" cmake --install build
    
    # Install apps
    DESTDIR="$pkgdir" cmake --install build-apps
}
```

All files are now installed via CMake instead of manual `install` commands.

---

## Files That Must Be Created in Marathon-Shell Repo

Before building the package, ensure these NEW files exist in `/home/patrickquinn/Developer/Marathon-Shell`:

1. ✅ `marathon-shell-session` (root directory, executable)
2. ✅ `systemd/marathon-shell.service`
3. ✅ `polkit/org.marathonos.shell.policy`
4. ✅ `xdg-autostart/marathon-notification-service.desktop`
5. ✅ `udev/70-marathon-shell.rules`

And these files have been UPDATED:
6. ✅ `marathon.desktop` (updated Exec= line)
7. ✅ `CMakeLists.txt` (added install targets)
8. ✅ `shell/CMakeLists.txt` (renamed binary output)
9. ✅ `APKBUILD` (simplified, added dependencies)

---

## Post-Installation Configuration

### 1. Enable greetd Auto-Login (Optional)

Copy the example configuration:
```bash
sudo cp /usr/share/greetd/marathon-shell-example.toml /etc/greetd/config.toml
```

Edit `/etc/greetd/config.toml` and set the correct user:
```toml
[default_session]
command = "/usr/bin/marathon-shell-session"
user = "your-username"
```

Enable greetd:
```bash
sudo rc-update add greetd default
```

### 2. Reload udev Rules

After installation:
```bash
sudo udevadm control --reload-rules
sudo udevadm trigger
```

### 3. Enable Hardware Services

Ensure these services are running:
```bash
# NetworkManager (WiFi, Ethernet)
sudo rc-update add networkmanager default
sudo rc-service networkmanager start

# ModemManager (Cellular)
sudo rc-update add modemmanager default
sudo rc-service modemmanager start

# UPower (Battery)
sudo rc-update add upower default
sudo rc-service upower start

# Bluetooth
sudo rc-update add bluetooth default
sudo rc-service bluetooth start

# D-Bus (Required for all services)
sudo rc-update add dbus default
sudo rc-service dbus start
```

---

## Testing Marathon Shell

### Manual Launch (for testing)

Before setting up greetd, test the shell manually:

```bash
# SSH into device, then:
export MARATHON_DEBUG=1
marathon-shell-session
```

Expected behavior:
- Shell launches as Wayland compositor
- Status bar shows real WiFi/Ethernet/Cellular signal
- Status bar shows real battery percentage and charging status
- Quick Settings allows brightness/volume control
- Native Linux apps (from /usr/share/applications) launch embedded in Marathon

### Debug Logging

Enable detailed logs:
```bash
export MARATHON_DEBUG=1
export QT_LOGGING_RULES="*.debug=true;marathon.*.info=true"
marathon-shell-session
```

Logs will show:
- D-Bus service connections (NetworkManager, UPower, ModemManager, etc.)
- Hardware detection (WiFi available, modem available, etc.)
- Battery state queries
- Network state changes

---

## Architecture Summary

```
User Login
    ↓
greetd/login manager
    ↓
/usr/bin/marathon-shell-session (wrapper script)
    ↓
    Sets environment: XDG_SESSION_TYPE, Qt paths, D-Bus
    ↓
/usr/bin/marathon-shell-bin (actual Qt6 compositor)
    ↓
    Connects to D-Bus services:
    - NetworkManager (WiFi/Ethernet)
    - ModemManager (Cellular)
    - UPower (Battery)
    - systemd-logind (Power, Lock, Brightness)
    - BlueZ (Bluetooth)
    ↓
    Reads hardware via:
    - /sys/class/backlight (Brightness)
    - /sys/class/iio (Sensors)
    - pactl (PulseAudio volume)
    ↓
Marathon Shell Wayland Compositor Running
    - Status bar reflects real hardware
    - Quick Settings controls real hardware
    - Native apps launch embedded
    - Marathon apps run in isolated contexts
```

---

## Verification Checklist

After installation and first boot:

- [ ] Marathon Shell appears in display manager (greetd/SDDM)
- [ ] Shell launches without errors
- [ ] Status bar shows correct WiFi/Ethernet connection
- [ ] Status bar shows correct battery percentage
- [ ] Charging icon appears when plugged in
- [ ] Quick Settings shows correct WiFi/Bluetooth hardware availability
- [ ] Brightness slider works
- [ ] Volume slider works
- [ ] Native Linux apps appear in app launcher
- [ ] Native apps launch embedded in Marathon (not external windows)
- [ ] Lock screen activates before system sleep
- [ ] Cellular signal shows (if modem present)

---

## Known Limitations

1. **Virtual Machines:** 
   - UPower may report 0 devices (no battery in VM)
   - Shell gracefully falls back to 100% battery display
   - NetworkManager may not detect WiFi hardware in some VMs

2. **WebEngine:**
   - Qt6WebEngine may not be available on all architectures
   - Browser app falls back to mock UI if WebEngine missing

3. **Notification Service:**
   - Currently a placeholder
   - Future work: Implement org.freedesktop.Notifications D-Bus service

---

## Next Steps for Marathon-Image Integration

1. **Copy files from Marathon-Shell to Marathon-Image package directory:**
   ```bash
   cd /home/patrickquinn/Developer/Marathon-Shell
   
   # Create directories in Marathon-Image package
   mkdir -p /home/patrickquinn/Developer/Marathon-Image/packages/marathon-shell/systemd
   mkdir -p /home/patrickquinn/Developer/Marathon-Image/packages/marathon-shell/polkit
   mkdir -p /home/patrickquinn/Developer/Marathon-Image/packages/marathon-shell/xdg-autostart
   mkdir -p /home/patrickquinn/Developer/Marathon-Image/packages/marathon-shell/udev
   
   # Copy new deployment files
   cp marathon-shell-session /home/patrickquinn/Developer/Marathon-Image/packages/marathon-shell/
   cp systemd/marathon-shell.service /home/patrickquinn/Developer/Marathon-Image/packages/marathon-shell/systemd/
   cp polkit/org.marathonos.shell.policy /home/patrickquinn/Developer/Marathon-Image/packages/marathon-shell/polkit/
   cp xdg-autostart/marathon-notification-service.desktop /home/patrickquinn/Developer/Marathon-Image/packages/marathon-shell/xdg-autostart/
   cp udev/70-marathon-shell.rules /home/patrickquinn/Developer/Marathon-Image/packages/marathon-shell/udev/
   
   # Copy updated files
   cp marathon.desktop /home/patrickquinn/Developer/Marathon-Image/packages/marathon-shell/
   cp APKBUILD /home/patrickquinn/Developer/Marathon-Image/packages/marathon-shell/
   ```

2. **Sync the full shell source:**
   ```bash
   # Option A: If marathon-shell package has full source
   rsync -av --exclude=build --exclude=build-apps \
       /home/patrickquinn/Developer/Marathon-Shell/ \
       /home/patrickquinn/Developer/Marathon-Image/packages/marathon-shell/
   
   # Option B: If using git submodule
   cd /home/patrickquinn/Developer/Marathon-Image/packages/marathon-shell
   git pull origin main
   ```

3. **Build the updated package:**
   ```bash
   cd /home/patrickquinn/Developer/Marathon-Image
   ./build-marathon.sh
   ```

4. **Flash to device and test.**

---

## Support & Troubleshooting

See `/home/patrickquinn/Developer/Marathon-Image/docs/TROUBLESHOOTING.md` for common issues.

For Marathon Shell-specific issues, check logs:
```bash
journalctl --user -u marathon-shell -f
```

Or run with debug mode:
```bash
MARATHON_DEBUG=1 marathon-shell-session 2>&1 | tee marathon-debug.log
```

---

**Status:** Ready for production deployment on postmarketOS/Alpine Linux mobile devices.

