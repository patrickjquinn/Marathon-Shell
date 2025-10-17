# Marathon OS

**BlackBerry 10-inspired mobile Linux powered by postmarketOS**

Marathon OS is a highly optimized mobile Linux distribution targeting real-time responsiveness, exceptional battery life, and security-first design. Built on postmarketOS with a custom Qt6/QML Wayland compositor, it brings the legendary BlackBerry 10 UX philosophy to modern mobile hardware.

## Target Specifications

- **Touch latency:** < 16ms (60 FPS capable)
- **App launch time:** < 300ms to first frame
- **Idle drain:** ≤ 1% per hour in deep sleep
- **Memory footprint:** 180-220 MB (shell + core services)

## Hardware

**Reference device:** OnePlus 6 (enchilada, SDM845)

Marathon OS is designed to run on **any ARM64 device** with mainline Linux support. The modular architecture separates device-agnostic components (performance tuning, shell) from device-specific ones (kernel drivers, bootloader).

### Supported Platforms

- **Snapdragon 845** (OnePlus 6, Poco F1, Shift6mq) - Excellent support
- **Snapdragon 855/+** (OnePlus 7 series) - Good support
- **Raspberry Pi 4/5** - Experimental
- **Generic ARM64** - Via U-Boot

See [Device Support Guide](docs/DEVICE_SUPPORT.md) for porting to new devices.

### Requirements

- ARM64 CPU (ARMv8+)
- 2GB+ RAM (3GB+ recommended)
- Mainline kernel 6.17+ support
- Wayland-capable GPU drivers
- 16GB+ storage

## Architecture

### Core Components

1. **Kernel:** Linux 6.17+ with mainlined PREEMPT_RT
2. **Init:** systemd for modern service management
3. **Shell:** Marathon Shell (Qt6/QML Wayland compositor)
4. **Audio:** PipeWire with real-time scheduling
5. **Telephony:** ModemManager with RT priority
6. **Security:** Landlock LSM + seccomp sandboxing

### Performance Optimizations

- **Real-time scheduling** for UI, input, audio, and modem paths
- **Kyber I/O scheduler** optimized for flash storage
- **schedutil CPU governor** for responsive power scaling
- **zram with LZ4** compression for memory efficiency
- **F2FS filesystem** for user data (flash-optimized)
- **Deep sleep (S3)** with minimal wake sources

## Project Structure

```
Marathon-Image/
├── packages/
│   ├── marathon-base-config/      # System tuning (universal ARM64)
│   ├── marathon-shell/             # Wayland compositor (universal)
│   └── linux-marathon/             # Modular kernel package
├── devices/
│   ├── enchilada/                  # OnePlus 6 device config
│   ├── sdm845/                     # SDM845 SoC config fragment
│   └── generic/                    # Generic ARM64 config
├── configs/
│   ├── sysctl.d/                   # Kernel tuning parameters
│   ├── udev.rules.d/               # Device management rules
│   ├── systemd/                    # Service configurations
│   └── security/                   # RT limits and permissions
├── scripts/
│   ├── build-and-flash.sh          # Build automation (multi-device)
│   └── validate-system.sh          # Post-boot validation
└── docs/
    ├── BUILD_THIS.md               # Complete build guide
    └── DEVICE_SUPPORT.md           # Device porting guide
```

## Quick Start

### Prerequisites

**On Linux (Fedora/Ubuntu):**

```bash
# Fedora
sudo dnf install pmbootstrap git android-tools

# Ubuntu/Debian
sudo apt install pmbootstrap git android-tools-adb android-tools-fastboot
```

**System Requirements:**
- 8GB+ RAM (for building)
- 20GB+ free disk space
- Internet connection (for downloading packages)
- Root access (for pmbootstrap chroot operations)

### Build Process

1. **Initialize pmbootstrap:**

```bash
pmbootstrap init
# Choose: v25.06 (stable), oneplus/enchilada, systemd, none (UI)
```

2. **Build complete Marathon OS:**

```bash
cd Marathon-Image

# For OnePlus 6 (default) - builds Marathon Shell + all optimizations
./scripts/build-and-flash.sh enchilada

# For other devices
./scripts/build-and-flash.sh <device-codename>

# For generic ARM64 (SBCs, VMs)
./scripts/build-and-flash.sh generic
```

This script will:
- Load device-specific configuration
- Build custom kernel with device fragment
- Build base config package (universal)
- Build Marathon Shell package (universal)
- Install Marathon Shell in rootfs
- Configure greetd for autologin
- Create flashable images in `./out/<device>/`

3. **Flash to device:**

```bash
# Boot OnePlus 6 into fastboot (Power + Vol Down)
fastboot flash boot out/enchilada/boot.img
fastboot flash system out/enchilada/oneplus-enchilada-root.img
fastboot reboot
```

**Result:** Device boots directly to Marathon Shell with all BlackBerry 10-inspired optimizations!

**Note:** The build creates two essential images:
- `boot.img` (26MB) - Contains kernel and initramfs
- `oneplus-enchilada-root.img` (624MB) - Contains the root filesystem with Marathon Shell

### Post-Boot Validation

SSH into the device and run:

```bash
./validate-system.sh
```

This will check:
- Kernel version and PREEMPT_RT status
- CPU governor (should be schedutil)
- I/O scheduler (should be kyber)
- zram configuration
- Real-time process priorities
- Sleep mode configuration
- Active wake sources

## Configuration Files

All system configurations are in `configs/` and deployed by `marathon-base-config`:

- **99-marathon.conf** - sysctl tuning (VM, network, scheduler)
- **60-marathon-cpufreq.rules** - schedutil governor enforcement
- **60-marathon-iosched.rules** - Kyber scheduler + I/O tuning
- **50-marathon.conf** - Deep sleep configuration
- **50-priority.conf** - RT priorities for PipeWire & ModemManager

## Development

### Marathon Shell

The Marathon Shell compositor is developed separately at:
https://github.com/patrickjquinn/Marathon-Shell

The `marathon-shell` package in this repo builds and integrates it into Marathon OS.

### Kernel Configuration

The kernel config fragment (`config-marathon-enchilada.aarch64`) enables:
- PREEMPT_RT (mainlined in 6.12+)
- schedutil CPU governor
- Kyber I/O scheduler
- F2FS with compression
- zram with LZ4
- Landlock LSM
- Mobile power management (PM_AUTOSLEEP, PM_WAKELOCKS)

### Custom Packages

All packages follow Alpine/postmarketOS APKBUILD format and can be customized in `packages/`:

- `marathon-base-config` - System configuration files (universal ARM64)
- `marathon-shell` - Compositor and session management (universal)
- `linux-marathon` - Modular kernel with device-specific fragments

### Device Configs

Device-specific configurations are in `devices/<codename>/`:

- `device.conf` - Device metadata, bootloader, partitions
- `kernel-config.fragment` - Device-specific kernel options (optional)

SoC family configs are shared in `devices/<soc-family>/`.

## Troubleshooting

### Build Issues

**"pmbootstrap not found":**
```bash
# Install pmbootstrap
sudo dnf install pmbootstrap  # Fedora
sudo apt install pmbootstrap  # Ubuntu/Debian
```

**"Permission denied" errors:**
```bash
# Ensure you have sudo access
sudo -v
# The build script needs root access for chroot operations
```

**Build hangs on password prompt:**
- The improved build script automatically uses a dummy password
- If using manual commands, add `--password "dummy123"`

**"Package build failed":**
```bash
# Check the build log
pmbootstrap log
# Rebuild with force if needed
pmbootstrap build <package-name> --force
```

### Laggy UI

- Check RT priorities: `ps -eo pid,rtprio,ni,comm | grep marathon`
- Verify I/O scheduler: `cat /sys/block/mmcblk0/queue/scheduler`
- Check CPU governor: `cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor`

### Battery Drain in Suspend

- Inspect wake sources: `cat /sys/kernel/wakeup_sources`
- Verify deep sleep: `cat /sys/power/mem_sleep` (should show `[deep]`)
- Check kernel cmdline: `cat /proc/cmdline` (should have `mem_sleep_default=deep`)

### Telephony Issues

- List modems: `mmcli -L`
- Check modem status: `mmcli -m 0`
- Restart ModemManager: `systemctl restart ModemManager`
- Verify RT priority: `ps -eo rtprio,comm | grep ModemManager`

### Audio Glitches

- Check PipeWire RT: `ps -eo rtprio,comm | grep pipewire`
- Verify limits: `ulimit -r` (should be 95 for audio group)
- Check service override: `systemctl cat pipewire.service`

## Performance Targets

Based on BUILD_THIS.md specifications:

| Metric | Target | How to Measure |
|--------|--------|----------------|
| Touch latency | < 16ms | `evtest` + high-speed camera |
| App launch | < 300ms | `time` command + QML profiler |
| Idle drain | ≤ 1%/hour | Battery stats over 8-hour sleep |
| Memory usage | 180-220 MB | `free -m` after boot |

## Contributing

Marathon OS is an experimental project exploring mobile Linux performance optimization. Contributions welcome!

### Areas for Improvement

- Additional device support (more SDM845/855 variants, Raspberry Pi)
- Further battery optimization (device-specific tuning)
- App ecosystem development
- Security hardening (SELinux profiles)
- Generic ARM64 testing and validation

## Documentation

- **BUILD_THIS.md** - Comprehensive build and tuning guide
- **DEVICE_SUPPORT.md** - Device porting guide and multi-device support
- **KERNEL_CONFIG.md** - Kernel configuration explanations
- **TROUBLESHOOTING.md** - Common issues and solutions
- **PACKAGE_REFERENCE.md** - Package build workflows

## License

- Marathon OS configurations: MIT
- Marathon Shell: GPL-3.0-or-later
- Linux kernel: GPL-2.0-only

---

**Marathon OS — make it buttery, make it last.**

