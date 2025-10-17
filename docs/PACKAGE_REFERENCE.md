# Marathon OS Package Reference

Quick reference for building and deploying Marathon OS packages.

## Package Overview

### 1. marathon-base-config

**Purpose:** System-wide tuning and configuration

**Installs:**
- `/etc/sysctl.d/99-marathon.conf` - Kernel tuning
- `/etc/systemd/zram-generator.conf.d/50-marathon.conf` - zram config
- `/etc/udev/rules.d/60-marathon-cpufreq.rules` - CPU governor
- `/etc/udev/rules.d/60-marathon-iosched.rules` - I/O scheduler
- `/etc/systemd/sleep.conf.d/50-marathon.conf` - Suspend config
- `/etc/security/limits.d/50-marathon.conf` - RT limits
- `/etc/systemd/system/pipewire.service.d/50-priority.conf` - Audio RT
- `/etc/systemd/system/ModemManager.service.d/50-priority.conf` - Modem RT

**Dependencies:**
- systemd, dbus, eudev
- Mesa (graphics)
- PipeWire (audio)
- ModemManager, NetworkManager (connectivity)
- F2FS tools, zram-generator
- Basic utilities (htop, nano, tmux, fonts)

**Build:**
```bash
cd packages/marathon-base-config
pmbootstrap build marathon-base-config
```

### 2. marathon-shell

**Purpose:** Wayland compositor and session management

**Installs:**
- `/usr/bin/marathon-shell` - Compositor binary
- `/usr/bin/marathon-compositor` - Session launcher with RT priorities
- `/usr/share/wayland-sessions/marathon.desktop` - Session file

**Dependencies:**
- Qt6 (base, declarative, wayland, qt5compat)
- Wayland, libinput, eudev
- Mesa EGL

**Build:**
```bash
cd packages/marathon-shell
pmbootstrap build marathon-shell
```

**Source:** https://github.com/patrickjquinn/Marathon-Shell

**Session environment:**
```bash
QT_QPA_PLATFORM=wayland
QT_WAYLAND_DISABLE_WINDOWDECORATION=1
XDG_SESSION_TYPE=wayland
XDG_CURRENT_DESKTOP=Marathon
QT_QUICK_CONTROLS_STYLE=Basic
```

**RT Priorities:**
- Compositor process: SCHED_FIFO priority 75
- Input thread: priority 85 (via --input-thread-priority)
- Render thread: priority 70 (via --render-thread-priority)

### 3. linux-marathon

**Purpose:** Custom kernel for OnePlus 6

**Version:** Linux 6.17+

**Key features:**
- PREEMPT_RT (mainlined, no patches needed)
- schedutil CPU governor default
- Kyber I/O scheduler default
- F2FS with compression support
- zram with LZ4
- Landlock LSM
- Mobile PM (autosleep, wakelocks)

**Installs:**
- `/boot/vmlinuz-marathon` - Kernel image
- `/boot/dtbs-marathon/` - Device trees
- `/lib/modules/6.17.0-marathon/` - Kernel modules

**Build:**
```bash
cd packages/linux-marathon
pmbootstrap build linux-marathon
```

**Configuration:**
- Base: `config-marathon-base.aarch64`
- Located in package directory
- Merge with device-specific configs during build

## Build Workflow

### Full System Build

```bash
# From project root
./scripts/build-and-flash.sh
```

This will:
1. Copy packages to pmaports
2. Build all three packages
3. Install to rootfs
4. Export boot image + rootfs
5. Copy images to `./out/`

### Manual Build

```bash
# Initialize pmbootstrap (first time only)
pmbootstrap init
# Select: edge, oneplus/enchilada, systemd, none

# Copy packages to pmaports
PMAPORTS="$HOME/.local/var/pmbootstrap/cache_git/pmaports"
cp -r packages/marathon-base-config "$PMAPORTS/main/"
cp -r packages/marathon-shell "$PMAPORTS/main/"
cp -r packages/linux-marathon "$PMAPORTS/device/main/"

# Build each package
pmbootstrap build marathon-base-config
pmbootstrap build marathon-shell
pmbootstrap build linux-marathon

# Install system
pmbootstrap install \
  --device oneplus-enchilada \
  --add marathon-base-config \
  --add marathon-shell \
  --kernel marathon

# Export images
pmbootstrap export --android-boot-img
pmbootstrap flasher export_rootfs
```

### Flashing

```bash
# Boot device into fastboot mode
# (Power off, then hold Power + Volume Down)

# Flash boot partition
fastboot flash boot out/boot-oneplus-enchilada.img

# Flash userdata partition
fastboot flash userdata out/postmarketos-oneplus-enchilada.img

# Reboot
fastboot reboot
```

## Post-Install Validation

### On-Device Checks

```bash
# SSH into device
ssh user@device-ip

# Run validation script
./validate-system.sh
```

### Manual Verification

```bash
# 1. Kernel
uname -r                    # Should show 6.17.0-marathon
zgrep PREEMPT_RT /proc/config.gz  # Should be =y

# 2. CPU Governor
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
# Should be: schedutil

# 3. I/O Scheduler
cat /sys/block/mmcblk0/queue/scheduler
# Should be: [kyber]

# 4. zram
zramctl
# Should show zram0 with lz4, ~50% RAM size

# 5. RT Processes
ps -eo pid,rtprio,ni,comm | grep -E '(marathon|pipewire|ModemManager)'
# marathon: RTPRIO 75
# pipewire: RTPRIO 88
# ModemManager: RTPRIO 90

# 6. Sleep Mode
cat /sys/power/mem_sleep
# Should show: s2idle [deep]

# 7. sysctl Settings
sysctl vm.swappiness        # Should be: 100
sysctl vm.page-cluster      # Should be: 0
sysctl net.ipv4.tcp_congestion_control  # Should be: bbr
```

## Package Updates

### Update marathon-base-config

1. Edit configs in `configs/` directory
2. Bump `pkgver` or `pkgrel` in APKBUILD
3. Rebuild and reinstall:
   ```bash
   pmbootstrap build marathon-base-config
   pmbootstrap install --add marathon-base-config
   ```

### Update marathon-shell

1. Update version in APKBUILD to match Marathon-Shell release
2. Update source URL and sha512sums
3. Rebuild:
   ```bash
   pmbootstrap build marathon-shell
   pmbootstrap install --add marathon-shell
   ```

### Update Kernel

1. Edit `config-marathon-base.aarch64`
2. Bump `pkgver` for new kernel version
3. Update kernel source URL
4. Rebuild:
   ```bash
   pmbootstrap build linux-marathon
   pmbootstrap install --kernel marathon
   pmbootstrap export --android-boot-img
   fastboot flash boot boot-oneplus-enchilada.img
   ```

## Debugging

### Build Failures

```bash
# Check build logs
pmbootstrap log

# Enter build chroot
pmbootstrap chroot

# Clean build
pmbootstrap zap -p
pmbootstrap build <package>
```

### Runtime Issues

```bash
# Check system logs
journalctl -b              # Current boot
journalctl -xe             # Recent errors
journalctl -u <service>    # Specific service

# Check kernel messages
dmesg | less

# Check service status
systemctl status marathon-compositor
systemctl status pipewire
systemctl status ModemManager
```

### Performance Profiling

```bash
# CPU usage
htop

# I/O usage
iostat -x 1

# Memory pressure
systemd-cgtop

# Process latency
cyclictest -m -p 95 -t 4 -n

# GPU performance
glmark2-wayland
```

## File Locations

### On Build System

```
Marathon-Image/
├── packages/
│   ├── marathon-base-config/
│   │   ├── APKBUILD
│   │   ├── marathon-base-config.post-install
│   │   └── [symlinks to configs/]
│   ├── marathon-shell/
│   │   ├── APKBUILD
│   │   ├── marathon-compositor
│   │   └── marathon.desktop
│   └── linux-marathon/
│       ├── APKBUILD
│       └── config-marathon-base.aarch64
├── configs/
│   ├── sysctl.d/
│   ├── udev.rules.d/
│   ├── systemd/
│   └── security/
└── scripts/
    ├── build-and-flash.sh
    └── validate-system.sh
```

### On Device

```
/etc/sysctl.d/99-marathon.conf
/etc/systemd/zram-generator.conf.d/50-marathon.conf
/etc/udev/rules.d/60-marathon-{cpufreq,iosched}.rules
/etc/systemd/sleep.conf.d/50-marathon.conf
/etc/security/limits.d/50-marathon.conf
/etc/systemd/system/pipewire.service.d/50-priority.conf
/etc/systemd/system/ModemManager.service.d/50-priority.conf
/usr/bin/marathon-shell
/usr/bin/marathon-compositor
/usr/share/wayland-sessions/marathon.desktop
/boot/vmlinuz-marathon
/boot/dtbs-marathon/
/lib/modules/6.17.0-marathon/
```

## Tips & Tricks

### Quick Iterations

For config changes (no rebuild needed):
```bash
# Edit config locally
vim configs/sysctl.d/99-marathon.conf

# Copy to device
scp configs/sysctl.d/99-marathon.conf user@device:/tmp/
ssh user@device "sudo cp /tmp/99-marathon.conf /etc/sysctl.d/ && sudo sysctl --system"
```

### Kernel Config Changes

```bash
# Make menuconfig on device
ssh user@device
sudo apk add build-base ncurses-dev
cd /usr/src/linux-6.17.0
sudo make menuconfig
sudo make -j8
sudo make modules_install install

# Or extract to dev machine:
scp user@device:/usr/src/linux-6.17.0/.config ./new-config
diff config-marathon-base.aarch64 new-config
```

### Test Without Flashing

For shell changes:
```bash
# Build locally, copy binary
scp build/marathon-shell user@device:/tmp/
ssh user@device "sudo cp /tmp/marathon-shell /usr/bin/ && sudo systemctl restart display-manager"
```

## Performance Targets

| Metric | Target | Measurement |
|--------|--------|-------------|
| Touch latency | < 16ms | evtest + high-speed camera |
| Frame time | 16.67ms (60 FPS) | QML profiler |
| App launch | < 300ms | time command |
| Idle power | ≤ 1%/hour | Battery stats |
| Memory idle | 180-220 MB | free -m |
| Suspend time | < 1s | time systemctl suspend |
| Resume time | < 2s | journalctl timing |

## Reference Documentation

- [BUILD_THIS.md](../docs/BUILD_THIS.md) - Complete build guide
- [KERNEL_CONFIG.md](../docs/KERNEL_CONFIG.md) - Kernel config explanations
- [TROUBLESHOOTING.md](../docs/TROUBLESHOOTING.md) - Common issues
- [README.md](../README.md) - Project overview

## Links

- Marathon Shell: https://github.com/patrickjquinn/Marathon-Shell
- postmarketOS Wiki: https://wiki.postmarketos.org
- pmbootstrap: https://gitlab.postmarketos.org/postmarketOS/pmbootstrap
- Linux RT: https://wiki.linuxfoundation.org/realtime/start

---

**Last updated:** October 2025


