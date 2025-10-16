# Marathon OS Quick Reference

One-page reference for common tasks.

## 🚀 Quick Start (When on Fedora)

```bash
# 1. Install tools
sudo dnf install pmbootstrap git android-tools

# 2. Initialize pmbootstrap
pmbootstrap init
# Select: edge, oneplus/enchilada, systemd, none

# 3. Build everything
cd Marathon-Image
./scripts/build-and-flash.sh

# 4. Flash device (in fastboot mode)
fastboot flash boot out/boot-oneplus-enchilada.img
fastboot flash userdata out/postmarketos-oneplus-enchilada.img
fastboot reboot
```

## 📦 Package Versions

- **marathon-base-config:** 1.0.0
- **marathon-shell:** 1.0.0 (from GitHub)
- **linux-marathon-enchilada:** 6.17.0

## 🔧 Key Configurations

| Setting | Value | Location |
|---------|-------|----------|
| CPU Governor | schedutil | udev: 60-marathon-cpufreq.rules |
| I/O Scheduler | kyber | udev: 60-marathon-iosched.rules |
| zram Size | 50% RAM | systemd: zram-generator.conf |
| zram Compression | lz4 | systemd: zram-generator.conf |
| Sleep Mode | deep | systemd: sleep.conf |
| vm.swappiness | 100 | sysctl: 99-marathon.conf |
| TCP Congestion | bbr | sysctl: 99-marathon.conf |

## 🎯 RT Priorities

| Service | Priority | Policy | Nice |
|---------|----------|--------|------|
| marathon-shell | 75 | FIFO | -12 |
| Input thread | 85 | FIFO | - |
| Render thread | 70 | FIFO | - |
| ModemManager | 90 | FIFO | -10 |
| PipeWire | 88 | FIFO | -15 |

## 📊 Performance Targets

- Touch latency: **< 16ms**
- App launch: **< 300ms**
- Idle drain: **≤ 1%/hour**
- Memory idle: **180-220 MB**
- Frame rate: **60 FPS**

## 🔍 Validation Commands

```bash
# Kernel & RT
uname -r
zgrep PREEMPT_RT /proc/config.gz

# CPU Governor
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

# I/O Scheduler
cat /sys/block/mmcblk0/queue/scheduler

# zram
zramctl

# RT Processes
ps -eo pid,rtprio,ni,comm | grep -E '(marathon|pipewire|ModemManager)'

# Sleep Mode
cat /sys/power/mem_sleep

# sysctl
sysctl vm.swappiness vm.page-cluster
```

## 🛠️ Quick Fixes

### Laggy UI
```bash
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo schedutil | sudo tee $cpu
done
sudo systemctl restart marathon-compositor
```

### Battery Drain
```bash
cat /sys/kernel/wakeup_sources | awk 'NR>1 && ($6>0 || $7>0)'
echo deep | sudo tee /sys/power/mem_sleep
```

### No Audio
```bash
systemctl --user restart pipewire pipewire-pulse wireplumber
pactl list sinks short
```

### Modem Issues
```bash
sudo systemctl restart ModemManager
mmcli -L
mmcli -m 0
```

## 📁 Critical Files

### On Device
```
/etc/sysctl.d/99-marathon.conf
/etc/udev/rules.d/60-marathon-{cpufreq,iosched}.rules
/etc/systemd/sleep.conf.d/50-marathon.conf
/etc/systemd/system/{pipewire,ModemManager}.service.d/50-priority.conf
/usr/bin/marathon-{shell,compositor}
/boot/vmlinuz-marathon
```

### In Repo
```
packages/marathon-base-config/APKBUILD
packages/marathon-shell/APKBUILD
packages/linux-marathon-enchilada/APKBUILD
configs/sysctl.d/99-marathon.conf
scripts/build-and-flash.sh
```

## 🔄 Update Workflow

### Config Change
```bash
# 1. Edit config in configs/
vim configs/sysctl.d/99-marathon.conf

# 2. Bump version in APKBUILD
vim packages/marathon-base-config/APKBUILD

# 3. Rebuild
pmbootstrap build marathon-base-config
pmbootstrap install --add marathon-base-config
```

### Kernel Change
```bash
# 1. Edit kernel config
vim packages/linux-marathon-enchilada/config-marathon-enchilada.aarch64

# 2. Bump version
vim packages/linux-marathon-enchilada/APKBUILD

# 3. Rebuild & flash
pmbootstrap build linux-marathon-enchilada
pmbootstrap export --android-boot-img
fastboot flash boot boot-oneplus-enchilada.img
```

### Shell Update
```bash
# 1. Update version to match Marathon-Shell release
vim packages/marathon-shell/APKBUILD

# 2. Rebuild
pmbootstrap build marathon-shell
pmbootstrap install --add marathon-shell

# 3. Restart
sudo systemctl restart display-manager
```

## 🐛 Debug Tools

```bash
# System logs
journalctl -b              # Current boot
journalctl -xe             # Recent errors
journalctl -f              # Follow logs

# Process monitoring
htop                       # CPU/Memory
systemd-cgtop              # Cgroup resources
top -H                     # Thread view

# Performance
iostat -x 1                # I/O stats
vmstat 1                   # VM stats
glmark2-wayland            # GPU test

# Device info
cat /proc/cpuinfo          # CPU info
cat /proc/meminfo          # Memory info
lsblk                      # Block devices
mmcli -L                   # Modem list
```

## 📚 Documentation

- **PROJECT_STATUS.md** - Current project status
- **README.md** - Project overview & quick start
- **docs/BUILD_THIS.md** - Original specification
- **docs/KERNEL_CONFIG.md** - Kernel config details
- **docs/TROUBLESHOOTING.md** - Problem solving
- **docs/PACKAGE_REFERENCE.md** - Package workflows

## 🌐 Links

- Marathon Shell: https://github.com/patrickjquinn/Marathon-Shell
- postmarketOS: https://postmarketos.org
- pmbootstrap: https://gitlab.postmarketos.org/postmarketOS/pmbootstrap

## 📞 Help

```bash
# Check system is properly configured
./scripts/validate-system.sh

# View validation script for manual checks
cat scripts/validate-system.sh
```

---

**Marathon OS — make it buttery, make it last.**


