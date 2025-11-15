# Boot Configuration Quick Reference

This is a quick reference for how Marathon Shell is configured to boot automatically on Raspberry Pi.

## Required Files

### 1. Session Startup Script
**Location**: `/usr/local/bin/marathon-shell-session`

**Purpose**: Launches Marathon Shell with proper environment variables

**Key Settings**:
```bash
export XDG_SESSION_TYPE=wayland
export XDG_SESSION_DESKTOP=marathon
export XDG_CURRENT_DESKTOP=marathon

# Detect if running as primary compositor or nested
if [ -n "$ORIGINAL_WAYLAND_DISPLAY" ] || [ -n "$ORIGINAL_DISPLAY" ]; then
    # Nested mode (testing)
    exec /usr/bin/marathon-shell-bin -platform wayland --fullscreen
else
    # Primary compositor mode (production)
    exec /usr/bin/marathon-shell-bin -platform eglfs
fi
```

**Must be executable**: `chmod +x /usr/local/bin/marathon-shell-session`

### 2. Session Desktop Entry
**Location**: `/usr/share/wayland-sessions/marathon.desktop`

**Contents**:
```ini
[Desktop Entry]
Name=Marathon Shell
Comment=Marathon OS Mobile Interface
Exec=/usr/local/bin/marathon-shell-session
Type=Application
```

**Why wayland-sessions?**: Tells LightDM this is a Wayland compositor, not an X11 session.

### 3. LightDM Configuration
**Location**: `/etc/lightdm/lightdm.conf`

**Critical Settings**:
```ini
[Seat:*]
user-session=marathon              # Default session for all users
autologin-user=pi                  # Auto-login as this user
autologin-session=marathon         # Session to use for autologin
greeter-session=lightdm-gtk-greeter # X11 greeter (avoids Wayland nesting issues)
```

**Why X11 greeter?**: If the greeter is a Wayland compositor (like `pi-greeter-labwc`), it conflicts with Marathon Shell (also a Wayland compositor) trying to start. Using an X11 greeter avoids this.

## Boot Sequence Summary

```
1. Power On
   ↓
2. Raspberry Pi Firmware (rainbow screen)
   ↓
3. Linux Kernel Loads
   ↓
4. systemd Starts Services
   ↓
5. lightdm.service Starts
   ↓
6. LightDM Reads /etc/lightdm/lightdm.conf
   ↓
7. Sees autologin-user=pi and autologin-session=marathon
   ↓
8. Skips greeter (or shows lightdm-gtk-greeter if manual login)
   ↓
9. Looks for session in /usr/share/wayland-sessions/
   ↓
10. Finds marathon.desktop
   ↓
11. Executes: /usr/local/bin/marathon-shell-session
   ↓
12. Script sets environment variables
   ↓
13. Script detects primary compositor mode
   ↓
14. Launches: /usr/bin/marathon-shell-bin -platform eglfs
   ↓
15. Marathon Shell starts as Wayland compositor
   ↓
16. Lock screen appears
   ↓
17. Ready for user interaction!
```

## Required Permissions

Marathon Shell needs special permissions to access the GPU directly:

```bash
# Add user to video and render groups (for /dev/dri/card0 access)
sudo usermod -a -G video,render pi

# Grant real-time priority capability
sudo setcap cap_sys_nice+ep /usr/bin/marathon-shell-bin

# Reboot required for group changes to take effect
sudo reboot
```

## Common Boot Issues

### Issue: Returns to Login Screen After Login

**Symptoms**: Log in → brief black screen → back to login screen

**Causes & Fixes**:

1. **Wrong greeter (Wayland compositor conflict)**
   ```bash
   # Check greeter
   grep "greeter-session" /etc/lightdm/lightdm.conf
   
   # Should be X11-based:
   greeter-session=lightdm-gtk-greeter
   
   # NOT Wayland-based:
   # greeter-session=pi-greeter-labwc  ❌
   ```

2. **Missing permissions**
   ```bash
   # Check groups
   groups pi
   # Should include: video render
   
   # Check capabilities
   getcap /usr/bin/marathon-shell-bin
   # Should show: cap_sys_nice+ep
   ```

3. **Session file not found**
   ```bash
   # Verify session file exists
   ls -l /usr/share/wayland-sessions/marathon.desktop
   
   # Verify startup script exists and is executable
   ls -l /usr/local/bin/marathon-shell-session
   ```

4. **Wrong autologin session**
   ```bash
   # Check autologin settings
   grep -E "(autologin-user|autologin-session)" /etc/lightdm/lightdm.conf
   
   # Should show:
   # autologin-user=pi
   # autologin-session=marathon
   ```

### Issue: Black Screen, No UI

**Symptoms**: Boot completes, screen is black, no Marathon Shell UI

**Causes & Fixes**:

1. **Qt platform plugin failure**
   ```bash
   # Check logs for Qt errors
   journalctl -u lightdm -b | grep -i "qt\|platform\|eglfs"
   
   # Common errors:
   # "Failed to create wl_display" → Using wrong platform plugin
   # "Could not open DRM device" → Permission issue
   ```

2. **Marathon Shell binary missing**
   ```bash
   # Verify binary exists
   which marathon-shell-bin
   # Should show: /usr/bin/marathon-shell-bin
   
   # Test if it runs
   /usr/bin/marathon-shell-bin --version
   ```

3. **Missing GPU drivers/libraries**
   ```bash
   # Check EGL/OpenGL libraries
   ls /usr/lib/aarch64-linux-gnu/libEGL*
   ls /usr/lib/aarch64-linux-gnu/libGLES*
   
   # Install if missing
   sudo apt install libegl1-mesa libgles2-mesa
   ```

### Issue: Boots to Raspberry Pi Desktop Instead

**Symptoms**: Raspberry Pi desktop (Wayfire) loads instead of Marathon Shell

**Cause**: LightDM is using the default session, not Marathon

**Fix**:
```bash
# Edit LightDM config
sudo nano /etc/lightdm/lightdm.conf

# Find [Seat:*] section and ensure:
user-session=marathon
autologin-session=marathon

# Save and reboot
sudo reboot
```

## Verification Commands

### Check if Marathon Shell is Running
```bash
# Look for the process
ps aux | grep marathon-shell

# Should show something like:
# pi  1234  ...  /usr/bin/marathon-shell-bin -platform eglfs
```

### Check Current Session
```bash
# Check session type
echo $XDG_SESSION_TYPE
# Should show: wayland

echo $XDG_CURRENT_DESKTOP
# Should show: marathon

# Check Wayland display
echo $WAYLAND_DISPLAY
# Should show: wayland-0
```

### Check LightDM Status
```bash
# Service status
sudo systemctl status lightdm

# View logs
journalctl -u lightdm -b

# Last 50 lines
journalctl -u lightdm | tail -50
```

### Check GPU Access
```bash
# List DRM devices
ls -l /dev/dri/

# Should show card0 with video/render group permissions:
# crw-rw----+ 1 root video 226, 0 Nov 12 14:00 /dev/dri/card0
# crw-rw----+ 1 root render 226, 128 Nov 12 14:00 /dev/dri/renderD128

# Check user groups
groups $USER
# Should include: video render
```

## Disabling Auto-Boot (Return to Raspberry Pi Desktop)

To temporarily or permanently disable Marathon Shell auto-boot:

### Temporary (One Boot)
At the LightDM login screen:
1. Click the session selector (gear icon)
2. Choose "LXDE-pi-Wayfire" or "LXDE-pi-Labwc"
3. Log in

### Permanent
```bash
# Edit LightDM config
sudo nano /etc/lightdm/lightdm.conf

# Change these lines:
user-session=LXDE-pi-wayfire
autologin-session=LXDE-pi-wayfire

# Or run the uninstall script:
cd ~/marathon-hackberry-pi
./scripts/uninstall.sh

# Reboot
sudo reboot
```

## Re-enabling Auto-Boot

```bash
# Edit LightDM config
sudo nano /etc/lightdm/lightdm.conf

# Change back to:
user-session=marathon
autologin-session=marathon

# Or run the install script:
cd ~/marathon-hackberry-pi
./scripts/install.sh

# Reboot
sudo reboot
```

## Testing Without Reboot

You can test Marathon Shell without configuring auto-boot:

```bash
# From Raspberry Pi desktop, open terminal and run:
/usr/local/bin/marathon-shell-session

# Marathon Shell will launch in fullscreen nested mode
# Press Ctrl+C or close to return to desktop
```

## Advanced: Multiple Sessions

You can keep Marathon Shell available as an option without making it the default:

```bash
# Edit LightDM config
sudo nano /etc/lightdm/lightdm.conf

# Set default to Raspberry Pi desktop:
user-session=LXDE-pi-wayfire
# autologin-session=LXDE-pi-wayfire  # Comment this out for manual login

# Disable autologin to show session selector
# Now at login, you can choose between:
# - LXDE-pi-Wayfire (Raspberry Pi desktop)
# - LXDE-pi-Labwc (Alternative Raspberry Pi desktop)
# - Marathon Shell (Your custom session)
```

## File Checklist

Before rebooting, verify all files are in place:

```bash
# Session script (must be executable)
ls -l /usr/local/bin/marathon-shell-session
# Should show: -rwxr-xr-x ... /usr/local/bin/marathon-shell-session

# Desktop entry
ls -l /usr/share/wayland-sessions/marathon.desktop
# Should show: -rw-r--r-- ... /usr/share/wayland-sessions/marathon.desktop

# LightDM config
ls -l /etc/lightdm/lightdm.conf
# Should show: -rw-r--r-- ... /etc/lightdm/lightdm.conf

# Marathon Shell binary
ls -l /usr/bin/marathon-shell-bin
# Should show: -rwxr-xr-x ... /usr/bin/marathon-shell-bin

# Capabilities set
getcap /usr/bin/marathon-shell-bin
# Should show: /usr/bin/marathon-shell-bin cap_sys_nice=ep

# User in groups
groups pi
# Should include: video render
```

All checks passed? **You're ready to reboot into Marathon Shell!** 🚀

---

*Last updated: 2025-11-12*

