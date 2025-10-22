# Testing Marathon Shell on Device (OnePlus 6 / postmarketOS)

## Critical Fixes Applied (2025-01-17)

✅ **Fixed greetd crash**: Removed `QT_QPA_PLATFORM=wayland` (compositors must not set this)
✅ **Added qt6-qtsql**: Fixes SQLite database errors
✅ **Fixed app installation path**: Apps now install to `/usr/share/marathon-apps`
✅ **Added geoclue**: For location services

## Rebuild and Deploy

### 1. On Development Machine

```bash
cd /home/patrickquinn/Developer/Marathon-Image/packages/marathon-shell

# Pull latest changes from Marathon-Shell repo
rsync -av --exclude=build --exclude=build-apps \
    /home/patrickquinn/Developer/Marathon-Shell/ ./

# Rebuild the package
cd /home/patrickquinn/Developer/Marathon-Image
./build-marathon.sh
```

### 2. On Device (marathon-ev1)

After flashing/installing the updated package:

```bash
# Install missing dependencies
sudo apk add qt6-qtsql geoclue

# Verify installation
ls -la /usr/bin/marathon-shell-*
# Should see:
# -rwxr-xr-x  marathon-shell-session
# -rwxr-xr-x  marathon-shell-bin

# Check if apps are installed
ls -la /usr/share/marathon-apps/
# Should see: browser, calculator, clock, etc.

# Restart greetd
sudo rc-service greetd restart
```

## Testing Steps

### Test 1: Manual Launch (Quick Test)

```bash
# SSH into device
ssh user@marathon-ev1

# Set environment
export XDG_RUNTIME_DIR=/run/user/10000
export MARATHON_DEBUG=1

# Launch shell directly (should work without crashing)
/usr/bin/marathon-shell-bin
```

**Expected:**
- Shell launches without core dump
- No SQLite driver errors
- Battery shows 93%, charging indicator
- Backlight detected
- Apps visible in launcher

### Test 2: Session Script

```bash
# Test the session script
/usr/bin/marathon-shell-session
```

**Expected:**
- Same as Test 1
- Should NOT crash
- QT_QPA_PLATFORM should NOT be set to "wayland"

### Test 3: greetd Auto-Login

```bash
# Edit greetd config
sudo vi /etc/greetd/config.toml
```

```toml
[terminal]
vt = 1

[default_session]
command = "/usr/bin/marathon-shell-session"
user = "user"
```

```bash
# Restart greetd
sudo rc-service greetd restart

# Check logs
journalctl -u greetd -f
```

**Expected:**
- No "greeter exited without creating a session" error
- No core dump
- Shell launches on VT1
- Display shows Marathon Shell UI

## Verification Checklist

After successful boot into Marathon Shell:

- [ ] Shell launches without crashing
- [ ] Status bar visible
- [ ] Battery shows correct percentage (93%)
- [ ] Charging indicator visible
- [ ] Time displays correctly (fix system clock if showing 1970)
- [ ] App launcher opens
- [ ] Marathon apps visible (Browser, Settings, Clock, etc.)
- [ ] Native Linux apps visible
- [ ] Tapping an app launches it
- [ ] Quick Settings opens
- [ ] Brightness slider works
- [ ] Volume slider works
- [ ] Lock screen appears on power button

## Known Issues (Current Status)

### ✅ Fixed
- ~~greetd crash / core dump~~ (QT_QPA_PLATFORM removed)
- ~~SQLite driver not loaded~~ (qt6-qtsql added)
- ~~Apps install to wrong path~~ (now system-wide)

### ⚠️ Non-Critical (Expected in this environment)
- **ModemManager not available**: OnePlus 6 modem needs specific drivers
- **No WiFi/Bluetooth hardware detected**: Check if drivers loaded (`lsmod | grep bcm`)
- **GeoClue2 not available**: Install with `sudo apk add geoclue`
- **Wallpaper missing**: Resource file needs wallpaper.jpg added
- **System clock shows 1970**: Run `sudo setup-timezone` and configure NTP

### 🔧 To Fix (Terminal App)
- **Terminal plugin missing libterminal-plugin.so**: RPATH issue
  ```bash
  # Check if file exists
  ls -la /usr/share/marathon-apps/terminal/
  
  # Check shared library dependencies
  ldd /usr/share/marathon-apps/terminal/Terminal/libterminal-pluginplugin.so
  ```
  
  **Fix**: Rebuild apps with proper RPATH or install to correct location

## Debug Commands

### Check D-Bus Services

```bash
# NetworkManager
busctl --system status org.freedesktop.NetworkManager

# UPower (battery)
busctl --system status org.freedesktop.UPower

# ModemManager
busctl --system status org.freedesktop.ModemManager1

# systemd-logind (power, brightness)
busctl --system status org.freedesktop.login1
```

### Check Hardware Access

```bash
# Backlight
ls -la /sys/class/backlight/
cat /sys/class/backlight/*/brightness
cat /sys/class/backlight/*/max_brightness

# Battery
ls -la /sys/class/power_supply/
cat /sys/class/power_supply/*/capacity

# Sensors (IIO)
ls -la /sys/bus/iio/devices/
```

### Check Qt Installation

```bash
# Qt version
qmake -v

# Qt plugins
ls /usr/lib/qt6/plugins/platforms/
ls /usr/lib/qt6/plugins/sqldrivers/

# Should see libqsqlite.so
ls -la /usr/lib/qt6/plugins/sqldrivers/libqsqlite.so
```

### Full Debug Launch

```bash
export MARATHON_DEBUG=1
export QT_DEBUG_PLUGINS=1
export QT_LOGGING_RULES="*.debug=true"
/usr/bin/marathon-shell-bin 2>&1 | tee /tmp/marathon-debug.log
```

## System Configuration

### Enable Services

```bash
# Ensure required services are running
sudo rc-update add networkmanager default
sudo rc-update add upower default
sudo rc-update add bluetooth default
sudo rc-update add dbus default

sudo rc-service networkmanager start
sudo rc-service upower start
sudo rc-service bluetooth start
```

### Set System Time

```bash
# Fix 1970 date issue
sudo setup-timezone
# Select your timezone

# Enable NTP
sudo apk add chrony
sudo rc-update add chronyd default
sudo rc-service chronyd start
```

### WiFi Setup (if hardware detected)

```bash
# List WiFi networks
nmcli dev wifi list

# Connect
nmcli dev wifi connect "SSID" password "PASSWORD"
```

## Performance Notes

### OnePlus 6 (enchilada) Specifications
- **Display**: 1080x2280, ~402 DPI, 6.28"
- **SoC**: Snapdragon 845 (SDM845)
- **RAM**: 6-8GB
- **GPU**: Adreno 630

### Display Scaling
Current configuration in `marathon-shell-session`:
```bash
export QT_SCALE_FACTOR=1
export QT_AUTO_SCREEN_SCALE_FACTOR=0
export QT_SCREEN_SCALE_FACTORS=1
export QT_ENABLE_HIGHDPI_SCALING=0
```

If UI elements are too small, adjust:
```bash
export QT_SCALE_FACTOR=1.5  # Try 1.25, 1.5, or 2.0
```

## Success Criteria

Marathon Shell is working correctly if:

1. ✅ Boots into shell automatically via greetd
2. ✅ No core dumps or crashes
3. ✅ Hardware controls work (brightness, volume)
4. ✅ Battery status accurate
5. ✅ Apps launch and run
6. ✅ Touch input responsive
7. ✅ Lock screen functional
8. ✅ Power button suspends device

## Next Steps After Success

1. **WiFi/Bluetooth**: Load BCM43xx firmware (`linux-firmware-brcm` package)
2. **Modem**: Load Qualcomm modem firmware for OnePlus 6
3. **Camera**: Test camera app with device camera
4. **Performance**: Profile and optimize for 60fps
5. **Power Management**: Test suspend/resume cycle

---

**Status**: Ready for testing on OnePlus 6 (enchilada) with postmarketOS.

