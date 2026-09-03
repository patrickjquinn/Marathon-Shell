# Marathon OS Kernel Configuration

This document explains the kernel configuration choices for Marathon OS, targeting Linux 6.17+ on the OnePlus 6 (SDM845).

## Overview

The Marathon kernel is based on mainline Linux 6.17+ with carefully selected configuration options to achieve:
- Real-time responsiveness (PREEMPT_RT)
- Optimal mobile power management
- Flash storage optimization
- Security hardening
- Mobile hardware support

## Critical Configuration Sections

### 1. Real-Time Preemption

**Goal:** Guaranteed low-latency response for UI, input, and audio

```
CONFIG_PREEMPTION=y
CONFIG_PREEMPT_RT=y
CONFIG_PREEMPT_COUNT=y
```

**Why:**
- PREEMPT_RT was mainlined in Linux 6.12, eliminating the need for external patches
- Provides deterministic latency for interactive workloads
- Essential for sub-16ms touch-to-photon latency
- Enables real-time scheduling policies (SCHED_FIFO, SCHED_RR)

**Trade-offs:**
- Slightly higher context switch overhead (~5-10%)
- More CPU time spent in kernel mode
- Worth it for mobile UI responsiveness

### 2. CPU Frequency Scaling

**Goal:** Responsive performance with minimal power waste

```
CONFIG_CPU_FREQ_GOV_SCHEDUTIL=y
CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y
```

**Why:**
- `schedutil` integrates directly with the scheduler
- Responds to workload changes faster than `ondemand`
- Better power efficiency than `performance`
- Ideal for bursty mobile workloads (touch, app launch)

**Alternatives considered:**
- `ondemand`: Too slow to respond, stuttery UI
- `performance`: Battery drain, thermal issues
- `powersave`: Laggy, unresponsive
- `conservative`: Similar issues to ondemand

### 3. I/O Scheduling

**Goal:** Optimal flash storage performance and latency

```
CONFIG_MQ_IOSCHED_KYBER=y
CONFIG_DEFAULT_KYBER=y
CONFIG_DEFAULT_IOSCHED="kyber"
```

**Why:**
- Kyber is designed for fast NVMe and modern flash
- Lower latency than mq-deadline for random I/O
- Better for mobile workloads (app launch, camera, media)
- Separate read/write queues minimize latency variance

**Why not BFQ:**
- BFQ adds overhead on mobile flash controllers
- Kyber's simplicity = lower CPU usage
- We don't need BFQ's fairness guarantees on single-user mobile

### 4. Filesystems

**Goal:** Stability for root, flash optimization for user data

```
CONFIG_EXT4_FS=y
CONFIG_F2FS_FS=y
CONFIG_F2FS_FS_COMPRESSION=y
CONFIG_F2FS_FS_LZ4=y
```

**Why:**
- **ext4 for `/`:** Battle-tested, stable, good for immutable root
- **F2FS for `/home`:** Flash-friendly wear leveling
- **F2FS compression:** Save space, reduce writes, improve endurance
- **LZ4 compression:** Fast, low CPU overhead

**Mount options:**
- Root: `noatime,errors=remount-ro`
- Home: `noatime,discard,fastboot,mode=adaptive`

### 5. Memory Management (zram)

**Goal:** Extend effective RAM without swap I/O penalties

```
CONFIG_ZRAM=y
CONFIG_ZRAM_DEF_COMP_LZ4=y
CONFIG_CRYPTO_LZ4=y
```

**Why:**
- **zram > swap partition:** No I/O to flash, faster
- **LZ4 compression:** 2-3x compression ratio with minimal CPU
- **Size:** 50% of RAM (512 MB RAM → 256 MB zram)
- Allows more apps in memory without OOM kills

**sysctl tuning (in marathon-base-config):**
```
vm.swappiness = 100          # Aggressively use zram
vm.page-cluster = 0          # Don't read-ahead from zram
vm.watermark_scale_factor = 125  # Earlier reclaim
```

### 6. Power Management

**Goal:** Deep sleep with minimal wake sources, aggressive runtime PM

```
CONFIG_PM_AUTOSLEEP=y
CONFIG_PM_WAKELOCKS=y
CONFIG_PM_SLEEP=y
CONFIG_SUSPEND=y
```

**Why:**
- **PM_AUTOSLEEP:** Android-style automatic suspend
- **PM_WAKELOCKS:** Kernel-level wakelock API for critical services
- **Deep sleep (S3):** Orders of magnitude better than s2idle
- Target: ≤1% battery drain per hour in suspend

**Wake sources:**
Only enable for:
- Modem (incoming calls/SMS)
- RTC (alarms)
- Power button
- USB (charge detection)

Disable for:
- Wi-Fi (use RTC for periodic sync)
- Bluetooth (explicit user wake)
- Sensors (wake on user interaction only)

### 7. Security

**Goal:** Sandboxed apps, no root escape, wayland isolation

```
CONFIG_SECURITY_LANDLOCK=y
CONFIG_SECCOMP=y
CONFIG_SECCOMP_FILTER=y
CONFIG_NAMESPACES=y
CONFIG_USER_NS=y
```

**Why:**
- **Landlock:** Modern LSM, simpler than SELinux/AppArmor
- **seccomp-bpf:** Per-app syscall filtering
- **Namespaces:** Container-like app isolation
- **USER_NS:** Unprivileged containers for apps

**Why not SELinux/AppArmor:**
- Complexity: harder to maintain custom policies
- Performance: overhead on every syscall/file access
- Landlock + seccomp provide 90% of the security with 10% of the complexity

### 8. Mobile Hardware

**Goal:** Support OnePlus 6 hardware (SDM845)

```
CONFIG_DRM_MSM=y           # Adreno GPU
CONFIG_DRM_MSM_DSI=y       # Display
CONFIG_SND_SOC_QCOM=y      # Audio
CONFIG_USB_CONFIGFS=y      # USB gadget/host
CONFIG_MHI_BUS=y           # Modem interface
```

**Hardware specifics:**
- **GPU:** Adreno 630 (freedreno driver in mesa)
- **Display:** Samsung AMOLED via DSI
- **Audio:** WCD9340 codec
- **Modem:** Snapdragon X20 LTE via MHI

### 9. Networking

**Goal:** Low latency, high throughput

```
CONFIG_TCP_CONG_BBR=y
CONFIG_DEFAULT_BBR=y
CONFIG_NET_SCH_FQ=y
```

**Why:**
- **BBR:** Better throughput on mobile networks (variable latency)
- **FQ (Fair Queue):** Required for BBR, reduces bufferbloat
- Works well with schedutil (CPU scales with network load)

### 10. Scheduler Tuning

**Goal:** Minimize wakeup latency for interactive tasks

```
kernel.sched_latency_ns = 6000000       # 6ms (default: 24ms)
kernel.sched_min_granularity_ns = 2000000  # 2ms (default: 3ms)
kernel.sched_wakeup_granularity_ns = 3000000  # 3ms (default: 4ms)
```

**Why:**
- Lower latency → faster response to touch/input
- More preemption → smoother UI
- Trade-off: slightly higher context switching overhead
- Acceptable on 8-core SDM845

### 11. Timer Frequency

**Goal:** Balance timer resolution with power efficiency

```
CONFIG_HZ_300=y
CONFIG_HZ=300
```

**Why:**
- **300 Hz:** Good middle ground for mobile
- Higher than 250 Hz desktop default (better latency)
- Lower than 1000 Hz (better power, less overhead)
- Aligns well with 60 FPS displays (60 * 5 = 300)

**Alternatives:**
- 100 Hz: Too coarse, stuttery
- 1000 Hz: Battery drain, cache pressure
- 250 Hz: Slightly worse frame pacing

## Configuration Validation

After booting, verify configuration:

```bash
# Check if PREEMPT_RT is active
zgrep CONFIG_PREEMPT_RT /proc/config.gz

# Verify schedutil governor
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

# Check I/O scheduler
cat /sys/block/mmcblk0/queue/scheduler

# Verify zram
zramctl

# Check timer frequency
grep CONFIG_HZ /boot/config-$(uname -r)
```

## Future Optimizations

### Potential improvements:

1. **Per-CPU governor tuning:**
   - Little cores (0-3): schedutil with lower max freq
   - Big cores (4-7): schedutil with aggressive scaling

2. **Energy Aware Scheduling (EAS):**
   - `CONFIG_ENERGY_MODEL=y`
   - Requires device-specific energy model
   - Better idle power consumption

3. **Process-specific CPU affinity:**
   - Pin compositor to big cores
   - Pin background services to little cores
   - Reduces migration overhead

4. **Custom SCHED_FIFO priorities:**
   - Compositor: 75
   - Input thread: 85
   - Render thread: 70
   - Modem: 90
   - Audio: 88

## References

- [Linux RT Documentation](https://docs.kernel.org/realtime-preempt.html)
- [schedutil Governor](https://lwn.net/Articles/682391/)
- [Kyber I/O Scheduler](https://lwn.net/Articles/720071/)
- [F2FS Documentation](https://docs.kernel.org/filesystems/f2fs.html)
- [Landlock LSM](https://landlock.io/)

## Kernel Build Notes

To customize the config:

```bash
# Start with Marathon config
cd packages/linux-marathon
cp config-marathon-base.aarch64 .config

# Customize with menuconfig
make ARCH=arm64 menuconfig

# Save changes
make ARCH=arm64 savedefconfig
mv defconfig config-marathon-base.aarch64
```

**Important:** Always test on device after config changes. Some options (like `io_poll`) may cause instability depending on hardware.

---

**Last updated:** October 2025 (Linux 6.17)


