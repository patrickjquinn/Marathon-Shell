# Troubleshooting Guide

This document covers common issues you might encounter when running Marathon Shell on Raspberry Pi and how to resolve them.

## Table of Contents

- [Boot Issues](#boot-issues)
- [Display Issues](#display-issues)
- [Session Lock Issues](#session-lock-issues)
- [Performance Issues](#performance-issues)
- [Logging and Debugging](#logging-and-debugging)

---

## Boot Issues

### Black Screen After Boot

**Symptoms**: After boot, screen is black with a blinking cursor, but no Marathon Shell UI appears.

**Possible Causes & Solutions**:

1. **LightDM not starting Marathon session**
   ```bash
   # Check LightDM status
   sudo systemctl status lightdm
   
   # Check if session is set correctly
   grep -E "(user-session|autologin-session)" /etc/lightdm/lightdm.conf
   # Should show: user-session=marathon and autologin-session=marathon
   
   # Check session file exists
   ls -l /usr/share/wayland-sessions/marathon.desktop
   ```

2. **Marathon Shell binary missing or incorrect**
   ```bash
   # Verify binary exists
   which marathon-shell-bin
   # Should show: /usr/bin/marathon-shell-bin
   
   # Check it's executable
   ls -l /usr/bin/marathon-shell-bin
   
   # Test if it runs
   /usr/bin/marathon-shell-bin --help
   ```

3. **GPU/DRM permissions issue**
   ```bash
   # Check user is in video/render groups
   groups $USER
   # Should include: video render
   
   # Add user to groups if missing
   sudo usermod -a -G video,render $USER
   
   # Grant capabilities
   sudo setcap cap_sys_nice+ep /usr/bin/marathon-shell-bin
   
   # Reboot required
   sudo reboot
   ```

4. **Qt platform plugin failure**
   ```bash
   # Check logs for Qt errors
   journalctl -u lightdm | grep -i "qt\|platform\|eglfs"
   
   # Verify Qt6 is installed
   dpkg -l | grep qt6
   
   # Check EGL/OpenGL libraries
   ls /usr/lib/aarch64-linux-gnu/libEGL*
   ls /usr/lib/aarch64-linux-gnu/libGLES*
   ```

### Returning to Login Screen After Login

**Symptoms**: You log in, see a brief black screen, then return to the LightDM login screen.

**Solution**:

1. **Check if another compositor is conflicting**
   ```bash
   # Ensure greeter is X11-based, not Wayland
   grep "greeter-session" /etc/lightdm/lightdm.conf
   # Should show: greeter-session=lightdm-gtk-greeter
   
   # If it shows pi-greeter-labwc or another Wayland greeter:
   sudo sed -i 's/greeter-session=.*/greeter-session=lightdm-gtk-greeter/' /etc/lightdm/lightdm.conf
   sudo apt-get install lightdm-gtk-greeter
   sudo reboot
   ```

2. **Session script errors**
   ```bash
   # Check session script is executable
   ls -l /usr/local/bin/marathon-shell-session
   
   # Test it manually
   /usr/local/bin/marathon-shell-session
   # (Ctrl+C to exit after testing)
   ```

3. **Check session logs**
   ```bash
   # View detailed LightDM session logs
   sudo journalctl -u lightdm -b | less
   
   # Look for Marathon-specific errors
   grep -i marathon /var/log/lightdm/
   ```

### Boot Hangs at Rainbow Screen

**Symptoms**: Raspberry Pi shows the rainbow screen but never progresses.

**Solution**:

This is usually unrelated to Marathon Shell. Check:

```bash
# Boot into recovery mode (hold Shift during boot)
# Or connect via SSH if network is up

# Check boot partition
sudo fsck /boot

# Review boot config
cat /boot/config.txt

# Check kernel messages
dmesg | less
```

---

## Display Issues

### Screen Too Small/Too Large (Scaling Issues)

**Solution**:

Edit the session script to adjust Qt scaling:

```bash
sudo nano /usr/local/bin/marathon-shell-session
```

Find and modify these lines:

```bash
# For smaller displays or higher DPI:
export QT_SCALE_FACTOR=1.5

# For larger displays or lower DPI:
export QT_SCALE_FACTOR=0.8

# To enable automatic scaling:
export QT_AUTO_SCREEN_SCALE_FACTOR=1
```

Reboot after changes.

### Choppy/Laggy Graphics

**Symptoms**: UI animations are stuttering or slow.

**Solutions**:

1. **Verify GPU acceleration is enabled**
   ```bash
   # Check that eglfs is being used
   ps aux | grep marathon-shell-bin
   # Should show: -platform eglfs
   ```

2. **Check if running in software rendering mode**
   ```bash
   # If it shows -platform linuxfb, edit session script:
   sudo sed -i 's/-platform linuxfb/-platform eglfs/' /usr/local/bin/marathon-shell-session
   sudo reboot
   ```

3. **Enable GPU memory allocation**
   ```bash
   # Edit boot config
   sudo nano /boot/firmware/config.txt
   
   # Add or modify:
   gpu_mem=256
   
   # Reboot
   sudo reboot
   ```

### No Touch Input

**Symptoms**: Touch screen doesn't respond, but mouse/keyboard works.

**Solutions**:

1. **Check touchscreen device is detected**
   ```bash
   # List input devices
   ls /dev/input/event*
   
   # Check if touchscreen is recognized
   dmesg | grep -i touch
   ```

2. **Verify Qt touch input is enabled**
   ```bash
   # Add to session script
   sudo nano /usr/local/bin/marathon-shell-session
   
   # Add these lines before the exec command:
   export QT_QPA_EGLFS_INTEGRATION=eglfs_kms
   export QT_QPA_ENABLE_TERMINAL_KEYBOARD=1
   export QT_QPA_EVDEV_TOUCHSCREEN_PARAMETERS=/dev/input/event0
   ```

---

## Session Lock Issues

### Immediate Re-Lock After Unlock

**Symptoms**: You swipe up and enter the PIN, but Marathon Shell immediately locks again.

**Solution**:

This should be fixed by the patches included in this repository. Verify patches are applied:

```bash
# Check SessionManager has the fix
grep "property double lastActivityTime" ~/Marathon-Shell/shell/qml/services/SessionManager.qml

# Should return:
#   property double lastActivityTime: Date.now()
# NOT:
#   property int lastActivityTime: 0

# If still showing 'int', re-apply patches:
cd ~/Marathon-Shell
patch -p1 < ~/marathon-hackberry-pi/patches/01-sessionmanager-fix.patch
cd build
ninja install
sudo reboot
```

### Screen Doesn't Lock at All

**Symptoms**: Marathon Shell never locks, even after hours of inactivity.

**Solutions**:

1. **Check idle detection is enabled**
   ```bash
   # Edit SessionManager.qml
   nano ~/Marathon-Shell/shell/qml/services/SessionManager.qml
   
   # Verify this line:
   property bool idleDetectionEnabled: true
   ```

2. **Check timeout values**
   ```bash
   # In SessionManager.qml:
   property int idleTimeout: 3600000  // 1 hour in milliseconds
   property int lockTimeout: 3600000  // Additional time before lock
   
   # For testing, temporarily reduce to 30 seconds:
   property int idleTimeout: 30000  // 30 seconds
   ```

3. **Rebuild after changes**
   ```bash
   cd ~/Marathon-Shell/build
   ninja install
   sudo systemctl restart lightdm
   ```

### Can't Unlock - Swipe Not Working

**Symptoms**: Swipe gesture on lock screen doesn't work.

**Solutions**:

1. **Test with mouse instead of touch**
   - Click and drag upward on the lock screen

2. **Check touch calibration**
   ```bash
   # Test touch input
   sudo evtest
   # Select your touch device and test if events are firing
   ```

3. **Try PIN screen instead**
   - If swipe-to-unlock isn't working, the PIN screen should still appear after swiping

---

## Performance Issues

### High CPU Usage

**Symptoms**: Marathon Shell uses 50%+ CPU even when idle.

**Solutions**:

1. **Check QML disk cache**
   ```bash
   # Ensure QML cache is enabled
   ls ~/.cache/marathon-qml/
   
   # Clear cache and regenerate
   rm -rf ~/.cache/marathon-qml/*
   # Restart Marathon Shell
   ```

2. **Disable debug logging**
   ```bash
   # Edit session script
   sudo nano /usr/local/bin/marathon-shell-session
   
   # Ensure this is NOT set:
   # MARATHON_DEBUG=1
   
   # Should use:
   export QT_LOGGING_RULES="*.warning=true;marathon.*.info=true"
   ```

3. **Check for background processes**
   ```bash
   # See what Marathon Shell is doing
   sudo strace -p $(pgrep marathon-shell)
   ```

### High Memory Usage

**Symptoms**: Marathon Shell uses >1GB of RAM.

**Solutions**:

1. **Close unused apps**
   - Use the app switcher (swipe from bottom edge) to close apps

2. **Reduce QML cache size**
   ```bash
   # Clear cache
   rm -rf ~/.cache/marathon-qml/*
   ```

3. **Monitor memory usage**
   ```bash
   # Check Marathon Shell memory
   ps aux | grep marathon-shell
   
   # Detailed memory breakdown
   sudo pmap $(pgrep marathon-shell)
   ```

---

## Logging and Debugging

### Enable Full Debug Logging

```bash
# Method 1: Environment variable
MARATHON_DEBUG=1 /usr/local/bin/marathon-shell-session

# Method 2: Temporary edit to session script
sudo sed -i 's/MARATHON_DEBUG="0"/MARATHON_DEBUG="1"/' /usr/local/bin/marathon-shell-session
sudo systemctl restart lightdm
# (Remember to revert after debugging)
```

### View Marathon Shell Logs

```bash
# View current session logs
journalctl -u lightdm -f

# View logs since last boot
journalctl -u lightdm -b

# View last 100 lines
journalctl -u lightdm -n 100

# Search for specific errors
journalctl -u lightdm | grep -i "error\|warning\|failed"

# Export logs to file
journalctl -u lightdm -b > ~/marathon-shell-debug.log
```

### Debug Specific Components

```bash
# Test Marathon Shell directly (not through LightDM)
cd ~/Marathon-Shell
QT_DEBUG_PLUGINS=1 /usr/bin/marathon-shell-bin -platform eglfs

# Test with specific logging categories
QT_LOGGING_RULES="marathon.session.debug=true" /usr/bin/marathon-shell-bin -platform eglfs

# Test in nested mode (within existing desktop)
WAYLAND_DISPLAY=wayland-0 /usr/bin/marathon-shell-bin -platform wayland --fullscreen
```

### Get System Information

```bash
# Raspberry Pi model
cat /proc/device-tree/model

# Qt version
qmake6 --version

# OpenGL/EGL info
glxinfo | grep "OpenGL"

# Wayland compositor info
echo $WAYLAND_DISPLAY
echo $XDG_SESSION_TYPE

# All environment variables
env | sort
```

---

## Getting Help

If you're still experiencing issues:

1. **Collect debug information**:
   ```bash
   # Create a debug report
   echo "=== System Info ===" > ~/marathon-debug-report.txt
   cat /proc/device-tree/model >> ~/marathon-debug-report.txt
   uname -a >> ~/marathon-debug-report.txt
   echo "" >> ~/marathon-debug-report.txt
   
   echo "=== Marathon Shell Version ===" >> ~/marathon-debug-report.txt
   /usr/bin/marathon-shell-bin --version >> ~/marathon-debug-report.txt
   echo "" >> ~/marathon-debug-report.txt
   
   echo "=== LightDM Logs ===" >> ~/marathon-debug-report.txt
   journalctl -u lightdm -b | tail -100 >> ~/marathon-debug-report.txt
   
   echo "=== Configuration ===" >> ~/marathon-debug-report.txt
   cat /etc/lightdm/lightdm.conf >> ~/marathon-debug-report.txt
   ```

2. **Open a GitHub issue** with:
   - Description of the problem
   - Steps to reproduce
   - Your debug report
   - Screenshots/video if applicable

3. **Check existing issues**:
   - [Marathon Shell Issues](https://github.com/MarathonOS/marathon-shell/issues)
   - [This Repository Issues](https://github.com/YOUR_USERNAME/marathon-hackberry-pi/issues)

---

*Last updated: 2025-11-12*

