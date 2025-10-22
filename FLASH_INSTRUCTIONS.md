# Marathon OS - Flash Instructions

## Build Date
October 22, 2025 - 17:57 UTC

## Image Files
- **Boot Image**: `out/enchilada/boot-MARATHON-FINAL.img` (26MB)
- **Root Image**: `out/enchilada/oneplus-enchilada-MARATHON-FINAL.img` (1.3GB sparse)

## What's Included
✓ Marathon Shell 1.0.0 (Wayland compositor with QML UI)
✓ All QML UI modules properly installed
✓ greetd display manager configured
✓ System optimizations (ZRAM, F2FS, performance tuning)
✓ All Marathon apps (Phone, Messages, Settings, Browser, etc.)
✓ PostmarketOS base with systemd
✓ Linux kernel 6.14.0-rc5 for SDM845

## Flash Commands

### Prerequisites
1. Device in fastboot mode (Power + Volume Down)
2. USB cable connected
3. ADB/fastboot tools installed

### Commands
```bash
cd /home/patrickquinn/Developer/Marathon-Image

# Flash boot image (kernel + initramfs)
fastboot flash boot out/enchilada/boot-MARATHON-FINAL.img

# Flash root filesystem
fastboot flash userdata out/enchilada/oneplus-enchilada-MARATHON-FINAL.img

# Optional: Wipe userdata if coming from different OS
# fastboot erase userdata

# Reboot
fastboot reboot
```

## What to Expect

### First Boot
1. Device boots to kernel console briefly
2. greetd starts automatically
3. Marathon Shell launches as user 'user'
4. Full gesture-based UI should appear

### Default Credentials
- **Username**: `user`
- **Password**: `147147`
- **Root Password**: `147147`

## Troubleshooting

### If you see a black screen:
1. SSH into device: `ssh user@10.88.0.128` (password: 147147)
2. Check greetd status: `systemctl status greetd`
3. Check Marathon Shell: `ps aux | grep marathon`
4. View logs: `journalctl -u greetd -f`

### Manual start (if needed):
```bash
export XDG_RUNTIME_DIR=/run/user/10000
export QT_QPA_PLATFORM=eglfs
export QT_QPA_EGLFS_INTEGRATION=eglfs_kms
/usr/bin/marathon-shell-bin
```

## Verification

Marathon Shell components installed:
- Binary: `/usr/bin/marathon-shell-bin` (51.7MB)
- Session script: `/usr/bin/marathon-shell-session`
- QML modules: `/usr/lib/qt6/qml/MarathonUI/`
- Apps: `/usr/share/marathon-apps/`
- Config: `/etc/greetd/config.toml`

## Build Notes

This build includes:
- Properly configured RPATH for all binaries
- QML plugin libraries installed alongside QML files
- greetd configured to auto-start Marathon Shell
- System tuned for mobile performance
- All dependencies resolved

## Known Issues
- Boot logo not yet integrated (shows kernel console)
- SQLite drivers not included (affects phone/messages apps data storage)

## Next Steps
1. Flash images using commands above
2. Boot and verify Marathon Shell starts
3. Test touch gestures and navigation
4. Report any issues

---
Built with pmbootstrap 3.5.0 on PostmarketOS systemd-v25.06

