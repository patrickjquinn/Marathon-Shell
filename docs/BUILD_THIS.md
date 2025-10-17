# Marathon OS Build & Tuning Guide

## BlackBerry 10–inspired, Qt 6/QML Mobile Linux on postmarketOS (Oct 2025)

**Target example device:** OnePlus 6 (SDM845, `enchilada`)

**Base OS:** postmarketOS (edge) with **systemd**, immutable image via **mkosi**

**Kernel:** Linux **6.12+** (mainline **PREEMPT_RT**), custom config for mobile

**Shell:** **Marathon Shell** (Qt 6 Wayland Compositor, QML UI)

**Goal:** BB10-level responsiveness, days-long standby, secure-by-default

---

## 0) Outcome Targets

* Idle drain (screen off, deep sleep): **≤ 1%/hour**
* Touch → frame latency: **< 16 ms**
* App launch (first frame): **< 300 ms**
* Idle memory (shell + core services): **≈ 180–220 MB**

---

## 1) Workstation Setup

```bash
# Ubuntu/Debian
sudo apt update && sudo apt install pmbootstrap git python3-pip android-tools-adb android-tools-fastboot

# Arch
sudo pacman -S pmbootstrap git android-tools

# (Optional) latest pmbootstrap from git
git clone --depth=1 https://gitlab.postmarketOS.org/postmarketOS/pmbootstrap.git
mkdir -p ~/.local/bin && ln -s "$PWD/pmbootstrap/pmbootstrap.py" ~/.local/bin/pmbootstrap
pmbootstrap --version
```

---

## 2) Initialize postmarketOS (immutable, systemd)

1. Create a workspace:

```bash
mkdir -p ~/marathon-os && cd ~/marathon-os
```

2. Init pmbootstrap:

```bash
pmbootstrap init
```

**Prompts (critical choices):**

* **Channel:** `edge`
* **Device vendor/codename:** `oneplus` / `enchilada`
* **Init:** `systemd`
* **User interface:** `none` (Marathon Shell installed separately)

3. Pull latest pmaports:

```bash
pmbootstrap pull
```

4. **Immutable images**: enable mkosi flow

```bash
# Enables mkosi-backed immutable image builds in pmbootstrap
pmbootstrap kconfig edit postmarketos-install-recommends # only if needed
# (No manual edit usually required; mkosi is used internally by new tooling.)
```

---

## 3) Kernel: 6.12+ with PREEMPT_RT & mobile options

Create a device-specific kernel package (example: `linux-marathon`).

**Key `CONFIG` options (excerpt):**

```
# Real-time
CONFIG_PREEMPTION=y
CONFIG_PREEMPT_RT=y

# CPUfreq / scheduler
CONFIG_CPU_FREQ_GOV_SCHEDUTIL=y
CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y

# I/O scheduler
CONFIG_MQ_IOSCHED_KYBER=y
CONFIG_DEFAULT_KYBER=y

# Filesystems
CONFIG_EXT4_FS=y
CONFIG_F2FS_FS=y
CONFIG_F2FS_FS_COMPRESSION=y

# zram
CONFIG_ZRAM=y
CONFIG_ZRAM_DEF_COMP_LZ4=y
CONFIG_CRYPTO_LZ4=y

# Security
CONFIG_SECURITY_LANDLOCK=y
CONFIG_SECCOMP=y
CONFIG_SECCOMP_FILTER=y

# Suspend / wake
CONFIG_SUSPEND=y
CONFIG_PM_SLEEP=y
CONFIG_PM_AUTOSLEEP=y
CONFIG_PM_WAKELOCKS=y
```

Build and integrate the package via `pmaports` as usual (`APKBUILD`, `config-*`).

---

## 4) Base Packages & Roles

Create a meta package **`marathon-base-config`** that drops tuned configs.

**Depends (suggested):**

* `systemd`, `dbus`, `eudev`
* Graphics: `mesa-gbm`, `mesa-egl`, `mesa-dri-gallium`, `egl-wayland`
* Audio: `pipewire`, `pipewire-pulse`, `wireplumber`
* Telephony: `modemmanager`, `networkmanager`, `mobile-broadband-provider-info`
* Storage: `e2fsprogs`, `f2fs-tools`, `systemd-zram-generator`
* Power: `tlp` (optional), `powertop` (optional)
* Utils: `htop`, `iw`, `nano`, `tmux`, fonts (`font-noto`, `ttf-dejavu`)

Install **`marathon-shell`** (your compositor/QML app) as a separate package.

---

## 5) Filesystems & Layout (UFS/eMMC)

* **Root `/`**: **ext4** (`noatime,errors=remount-ro`) → stability-first
* **Home `/home`**: **F2FS** (`noatime,discard,fastboot,mode=adaptive`) → flash-optimized user data
* **Boot**: device default (often ext4 / vendor layout)

`/etc/fstab` template (adjust partition names):

```
/dev/mmcblk0p17  /      ext4  noatime,errors=remount-ro                       0 1
/dev/mmcblk0p18  /home  f2fs  noatime,discard,fastboot,mode=adaptive          0 2
```

---

## 6) Memory: zram & OOM behavior

**zram (via systemd-zram-generator or zram-init):**

* **Size**: ~**50% of RAM** (512 MB RAM → 256 MB zram)
* **Algorithm**: **`lz4`** (fast, low CPU)
* **Priority**: `100`

`/etc/systemd/zram-generator.conf` example:

```ini
[zram0]
zram-size = ram/2
compression-algorithm = lz4
priority = 100
```

**sysctl (memory & FS tuning):** `/etc/sysctl.d/99-marathon.conf`

```
# zram-friendly behavior
vm.swappiness = 100
vm.page-cluster = 0
vm.watermark_scale_factor = 125
vm.watermark_boost_factor = 0

# flash writeback
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
vm.dirty_writeback_centisecs = 1500

# cache & net
vm.vfs_cache_pressure = 50
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_congestion_control = bbr
```

**systemd-oomd**: ensure enabled; default pressure limits are acceptable. Override if needed in `/etc/systemd/oomd.conf.d/*.conf`.

---

## 7) CPU, I/O & IRQ policies

**CPU governor**: **`schedutil`** on all cores.

Udev rule `/etc/udev/rules.d/60-marathon-cpufreq.rules`:

```
ACTION=="add", SUBSYSTEM=="cpu", KERNEL=="cpu[0-9]*", \
  RUN+="/bin/sh -c 'echo schedutil > /sys/devices/system/cpu/%k/cpufreq/scaling_governor'"
```

**I/O scheduler**: **Kyber** for UFS/eMMC + sensible read-ahead & polling.

`/etc/udev/rules.d/60-marathon-iosched.rules`:

```
# Kyber on flash
ACTION=="add|change", KERNEL=="mmcblk[0-9]*", ATTR{queue/scheduler}="kyber"
# Polling (optional; test per device)
ACTION=="add|change", KERNEL=="mmcblk[0-9]*", ATTR{queue/io_poll}="1"
# Read-ahead
ACTION=="add|change", KERNEL=="mmcblk[0-9]*", ATTR{queue/read_ahead_kb}="128"
```

**IRQ balancing**: enable `irqbalance` to distribute interrupts across cores.

---

## 8) Power management: deep sleep & wake sources

**Kernel cmdline**: `mem_sleep_default=deep`

**systemd sleep policy**: `/etc/systemd/sleep.conf.d/50-marathon.conf`

```
[Sleep]
SuspendState=mem
SuspendMode=deep
```

**Wake sources** (enable only essentials): modem (calls/SMS), RTC alarms, power key, USB (charge detect). Example enabling device wake:

```bash
echo enabled | sudo tee /sys/devices/.../power/wakeup
```

List current wake sources:

```bash
cat /sys/kernel/wakeup_sources
```

**Runtime PM**: autosuspend for USB/PCIe/I2C devices via udev rules (`ATTR{power/control}="auto"`).

**CPU governor during screen-off**: keep `schedutil`; optional lower max freq via `cpupower` profiles if battery needs outweigh latency.

---

## 9) Audio/Media: PipeWire (low-latency)

* Ensure **PipeWire** + **WirePlumber** enabled for audio routing.
* Give audio a real-time budget and memlock.

`/etc/security/limits.d/50-marathon.conf` (excerpt):

```
@audio  - rtprio 95
@audio  - nice   -15
@audio  - memlock unlimited
```

`/etc/systemd/system/pipewire.service.d/50-priority.conf`:

```
[Service]
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=88
Nice=-15
IOSchedulingClass=realtime
IOSchedulingPriority=2
```

---

## 10) Telephony: ModemManager + NetworkManager

* Use **ModemManager** (active upstream, widely adopted on mobile UIs)
* Don’t run `ofono` and `ModemManager` simultaneously.

`/etc/systemd/system/ModemManager.service.d/50-priority.conf`:

```
[Service]
CPUSchedulingPolicy=fifo
CPUSchedulingPriority=90
Nice=-10
IOSchedulingClass=realtime
IOSchedulingPriority=1
```

---

## 11) Security model

* **Landlock LSM** + **seccomp-bpf** + namespaces for app sandboxes.
* Per-app manifests (permissions) and portals for files/camera/mic.
* Wayland isolation (no X11).

Optional: SELinux/AppArmor profiles for system daemons.

---

## 12) Marathon Shell integration

**Environment** (session script `marathon-compositor`):

```
#!/bin/sh
# RT priority for compositor
chrt -f 75 -p $$ 2>/dev/null || true
renice -n -12 -p $$ 2>/dev/null || true

export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=Marathon
export QT_QUICK_CONTROLS_STYLE=Basic

exec /usr/bin/marathon-shell \
  --input-thread-priority=85 \
  --render-thread-priority=70
```

Install a `wayland-session` desktop file and set autologin to the `marathon` user on tty1 if desired.

---

## 13) Build the image

**Device package**: point `deviceinfo_kernel` to `linux-marathon` in the device's pmaports entry.

**Package manifest** (example `marathon-packages.txt`): core/base, graphics, audio, telephony, `marathon-base-config`, `marathon-shell`, custom kernel.

**Install & export**:

```bash
# Build packages
pmbootstrap build marathon-base-config
pmbootstrap build marathon-shell
pmbootstrap build linux-marathon

# Install system to rootfs and export images
pmbootstrap install --device oneplus-enchilada --add marathon-base-config --add marathon-shell --add linux-marathon
pmbootstrap export --android-boot-img
pmbootstrap flasher export_rootfs
```

**Flash** via `fastboot` (adjust partitions for device):

```bash
fastboot flash boot boot-oneplus-enchilada.img
fastboot flash userdata postmarketos-oneplus-enchilada.img
fastboot reboot
```

---

## 14) Post-boot validation

```bash
# Kernel / Governor / Scheduler
uname -r
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
cat /sys/block/mmcblk0/queue/scheduler

# zram
zramctl; cat /proc/swaps

# Priorities
ps -eo pid,rtprio,ni,comm | grep -E '(pipewire|ModemManager|marathon)'

# Sleep mode
cat /sys/power/mem_sleep  # expect: s2idle [deep]

# Wake sources
cat /sys/kernel/wakeup_sources | awk '$3>0 || $4>0 {print}'
```

**Benchmarks / sanity:**

```bash
# I/O quick test
dd if=/dev/zero of=/tmp/test bs=1M count=100 oflag=direct

# Stress memory w/ zram
stress-ng --vm 2 --vm-bytes 400M --timeout 30s

# GPU sanity
glmark2-wayland
```

---

## 15) Power polish checklist

* Verify **deep** suspend + reliable resume
* Confirm only critical **wake** sources enabled (modem/RTC/power/USB)
* Aggressive runtime PM rules (`power/control=auto`)
* Screen-off profile (optional max freq cap) if needed for idle drain

---

## 16) Troubleshooting quick refs

**Laggy UI**

* Confirm RT priorities applied (compositor/input/audio/modem)
* Check I/O scheduler is Kyber; try toggling `io_poll`
* Verify `schedutil`; ensure min/max freq not clamped too low

**Battery drain (suspend)**

* Inspect `wakeup_sources`; disable noisy devices
* Ensure `mem_sleep_default=deep` and systemd sleep mode set

**Telephony quirks**

* `mmcli -L` (modem list), `mmcli -m 0`
* Restart ModemManager; check RT priority override status

**Audio glitches**

* Confirm PipeWire RT policy + memlock
* Lower `quantum`/`rate` only if stable

---

## 17) Optional Android app support

* **Waydroid** (LXC container, Wayland): add only if RAM allows. Expect +300–400 MB when active; keep disabled by default.

---

## 18) Expected “feel” after tuning

* Finger-to-pixel latency below **one frame** at 60 Hz
* Smooth edge gestures & Active Frames in Marathon Shell
* Reliable call/SMS wake from deep sleep
* Stable storage with ext4 root; fast user data on F2FS

---

## 19) Appendix: Package/File Drop Summary

* `linux-marathon` (custom kernel pkg)
* `marathon-base-config` (drops: sysctl, zram, iosched/cpufreq udev rules, limits, sleep policy, PipeWire & ModemManager overrides)
* `marathon-shell` (Wayland compositor + session file + `marathon-compositor` launcher)

---

**Marathon OS — make it buttery, make it last.**
