# Pre-Build Checklist for Fedora

**Before building Marathon OS on Fedora, verify these items.**

## ✅ System Requirements

### Hardware
- [ ] x86_64 or ARM64 Linux machine (Fedora 38+)
- [ ] 16GB+ RAM (recommended)
- [ ] 50GB+ free disk space
- [ ] USB port for device connection

### Target Device
- [ ] OnePlus 6 (or supported device) with unlocked bootloader
- [ ] USB cable for fastboot/ADB
- [ ] Device charged to 80%+
- [ ] Backup of existing data (build will wipe device)

## ✅ Software Prerequisites

### Fedora Packages
```bash
# Install required packages
sudo dnf install -y \
    pmbootstrap \
    git \
    android-tools \
    python3-pip \
    qemu-user-static \
    binfmt-support

# Verify installations
pmbootstrap --version  # Should show latest version
fastboot --version     # Should show Android fastboot
adb version           # Should show Android Debug Bridge
```

### pmbootstrap Initialization
- [ ] Run `pmbootstrap init`
- [ ] Select channel: **edge**
- [ ] Select device: **oneplus/enchilada** (or your device)
- [ ] Select init system: **systemd**
- [ ] Select UI: **none**
- [ ] Configuration saved in `~/.config/pmbootstrap.cfg`

## ✅ Repository Verification

### File Integrity
```bash
cd Marathon-Image

# Verify all critical files exist
ls -la packages/marathon-base-config/APKBUILD
ls -la packages/marathon-shell/APKBUILD
ls -la packages/linux-marathon/APKBUILD
ls -la devices/enchilada/device.conf
ls -la configs/sysctl.d/99-marathon.conf
ls -la scripts/build-and-flash.sh
```

### Checksums (Will be generated during build)
- [ ] APKBUILDs currently use `SKIP` for checksums
- [ ] First build will download sources
- [ ] Generate checksums with: `abuild checksum`

## ✅ External Dependencies

### Linux Kernel Source
- [ ] Linux 6.17 available at kernel.org
- [ ] Verify: `curl -I https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.17.0.tar.xz`
- [ ] Should return HTTP 200

### Marathon Shell Release
- [ ] Check https://github.com/patrickjquinn/Marathon-Shell/releases
- [ ] Update `pkgver` in `packages/marathon-shell/APKBUILD` if needed
- [ ] If no release yet, use `_git` suffix and fetch from main branch

## ✅ Device Preparation

### Bootloader Unlock
```bash
# Enable Developer Options on device:
# Settings → About → Tap "Build number" 7 times

# Enable OEM Unlocking:
# Settings → Developer Options → OEM Unlocking

# Enable USB Debugging:
# Settings → Developer Options → USB Debugging

# Connect device via USB and verify:
adb devices

# Should show:
# List of devices attached
# <serial>    device

# Reboot to bootloader:
adb reboot bootloader

# Verify fastboot:
fastboot devices

# Should show:
# <serial>    fastboot

# Unlock bootloader (THIS WIPES DATA):
fastboot oem unlock
# Or on newer devices:
fastboot flashing unlock

# Confirm on device screen
```

**⚠️ WARNING:** Unlocking bootloader will **factory reset** the device!

### Partition Backup (Optional but Recommended)
```bash
# Boot into fastboot mode
adb reboot bootloader

# Backup current boot image (in case you need to restore)
fastboot boot boot.img

# Or use TWRP recovery to backup partitions
```

## ✅ Build Environment Setup

### pmbootstrap Work Directory
```bash
# Check pmbootstrap work directory
pmbootstrap config work

# Default: ~/.local/var/pmbootstrap

# Ensure enough disk space:
df -h ~/.local/var/pmbootstrap
# Should have at least 20GB free
```

### Copy Packages to pmaports
This will be done by `build-and-flash.sh`, but verify paths:
```bash
# pmaports location
PMAPORTS="$HOME/.local/var/pmbootstrap/cache_git/pmaports"

# Verify directory exists after pmbootstrap init
ls -la "$PMAPORTS"
```

## ✅ Network Requirements

### Download Requirements
- [ ] Stable internet connection
- [ ] No restrictive firewall blocking:
  - kernel.org (kernel source)
  - github.com (Marathon Shell source)
  - dl-cdn.alpinelinux.org (Alpine packages)

### Estimated Downloads
- Linux kernel: ~150 MB
- Alpine packages: ~500 MB
- Qt6 dependencies: ~200 MB
- Total: ~1 GB

## ✅ Pre-Build Tests

### Test pmbootstrap
```bash
# Test pmbootstrap functionality
pmbootstrap status

# Should show device configuration
```

### Test Build Environment
```bash
# Try building a simple package (test)
pmbootstrap build hello-world || echo "Expected to fail if package doesn't exist"

# Verify chroot works
pmbootstrap chroot
# Should enter Alpine Linux chroot
# Type 'exit' to leave
```

### Verify Device Config
```bash
# Check if device is in pmaports
pmbootstrap config device

# Should show: oneplus-enchilada (or your device)
```

## ✅ Known Issues & Workarounds

### Issue: pmbootstrap not found
```bash
# Install from PyPI
pip3 install --user pmbootstrap
export PATH="$HOME/.local/bin:$PATH"
```

### Issue: Android tools not found
```bash
# Fedora/RHEL
sudo dnf install android-tools

# Or install manually from Android SDK
```

### Issue: Permission denied on device
```bash
# Add user to plugdev group
sudo usermod -aG plugdev $USER
# Logout and login again

# Or run with sudo (not recommended)
sudo fastboot devices
```

### Issue: Device not detected in fastboot
```bash
# Check USB cable (must be data cable, not charge-only)
# Try different USB port (prefer USB 2.0 over 3.0)
# Disable USB selective suspend in BIOS/firmware

# Check udev rules
echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="2a70", MODE="0666", GROUP="plugdev"' | \
sudo tee /etc/udev/rules.d/51-android.rules

sudo udevadm control --reload-rules
```

## ✅ Post-Checklist Next Steps

Once all items are checked:

1. **Run the build:**
   ```bash
   cd Marathon-Image
   ./scripts/build-and-flash.sh enchilada
   ```

2. **Monitor build progress:**
   - First build takes 30-60 minutes
   - Watch for errors in terminal
   - Check logs: `pmbootstrap log`

3. **Flash to device:**
   - Follow instructions output by build script
   - Device will boot into fastboot automatically
   - Flash boot and userdata partitions
   - First boot takes 2-3 minutes

4. **Post-boot validation:**
   ```bash
   # SSH into device (after enabling SSH in setup)
   ssh user@<device-ip>
   
   # Run validation
   ./validate-system.sh
   ```

## ✅ Emergency Recovery

### If Build Fails
```bash
# Clean pmbootstrap work directory
pmbootstrap zap -p

# Start fresh
pmbootstrap init
```

### If Flash Fails
```bash
# Reboot to bootloader
fastboot reboot-bootloader

# Try flashing again
# Device is still in fastboot, not bricked
```

### If Boot Fails
```bash
# Boot into recovery (Volume Up + Power)
# Or restore from backup
# Or flash stock ROM from OnePlus website
```

## ✅ Support Resources

- **postmarketOS Wiki:** https://wiki.postmarketos.org
- **OnePlus 6 Device Page:** https://wiki.postmarketos.org/wiki/OnePlus_6_(oneplus-enchilada)
- **pmbootstrap Issues:** https://gitlab.postmarketos.org/postmarketOS/pmbootstrap/-/issues
- **Marathon OS Docs:** See `docs/` directory

---

**Ready to build?** If all checkboxes are ✅, proceed with: `./scripts/build-and-flash.sh enchilada`

**Estimated time:** 30-60 minutes for first build, 10-20 minutes for subsequent builds.


