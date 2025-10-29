# Marathon OS Linux Configuration Documentation

## Real-Time Scheduling Implementation

This directory contains the implementation of RT thread priorities per **Marathon OS Technical Specification v1.2, Section 3**.

### Files Added

1. **`shell/src/rtscheduler.h/cpp`** - C++ RT scheduler class
2. **`shell/src/waylandcompositor.cpp`** - Compositor RT priority (75)
3. **`shell/main.cpp`** - Main thread RT priority (85) for input handling
4. **`scripts/configure-rt-linux.sh`** - Linux system configuration script

---

## How It Works

### Priority Hierarchy (SCHED_FIFO)

```
Priority 99  - Kernel critical tasks
Priority 90  - ModemManager (telephony)
Priority 88  - PipeWire (audio)
Priority 85  - Input handling (Marathon main thread) ✅ IMPLEMENTED
Priority 80  - Default user RT apps
Priority 75  - Compositor rendering ✅ IMPLEMENTED
Priority 50  - Kernel IRQ handlers
Priority 0   - SCHED_OTHER (normal tasks)
```

### On macOS (Development)

- RT scheduling APIs are not available
- Code compiles but does nothing (guarded by `#ifdef Q_OS_LINUX`)
- Logs: `"RT scheduling not available (not Linux)"`

### On Linux (Production)

#### Without PREEMPT_RT Kernel

- Code compiles and runs
- `pthread_setschedparam()` calls fail with permission errors
- Logs: `"⚠ Failed to set RT priority (need CAP_SYS_NICE or limits.conf)"`
- Shell continues to work normally (SCHED_OTHER)

#### With PREEMPT_RT Kernel + Configuration

1. **Kernel detects PREEMPT_RT**:
   ```
   [MarathonShell] ✓ PREEMPT_RT kernel detected
   ```

2. **Main thread sets RT priority 85**:
   ```
   [MarathonShell] ✓ Main thread (input handling) set to RT priority 85 (SCHED_FIFO)
   ```

3. **Compositor sets RT priority 75**:
   ```
   [WaylandCompositor] ✓ Compositor thread set to RT priority 75 (SCHED_FIFO)
   ```

4. **RTScheduler available to QML**:
   ```qml
   // QML can query RT status
   console.log("RT Kernel:", RTScheduler.isRealtimeKernel())
   console.log("Policy:", RTScheduler.getCurrentPolicy())
   console.log("Priority:", RTScheduler.getCurrentPriority())
   ```

---

## Linux Configuration Script

### Running the Script

**On PostmarketOS or Alpine Linux:**

```bash
# Copy script to device
scp scripts/configure-rt-linux.sh user@device:/tmp/

# SSH to device
ssh user@device

# Run as root
sudo /tmp/configure-rt-linux.sh

# Reboot to apply RT limits
sudo reboot
```

### What the Script Does

1. **Verifies PREEMPT_RT kernel** (`/sys/kernel/realtime == 1`)
2. **Creates `/etc/security/limits.d/99-marathon.conf`**:
   ```
   @marathon-users  -  rtprio  90
   @marathon-users  -  nice   -10
   @marathon-users  -  memlock unlimited
   ```
3. **Creates `marathon-users` group** and adds default user
4. **Configures systemd services** (ModemManager, PipeWire, marathon-shell)
5. **Sets kernel parameters** (`/etc/sysctl.d/99-marathon.conf`)
6. **Configures I/O scheduler** (Kyber for flash storage)

### Verification After Reboot

```bash
# 1. Check RT limits
ulimit -r
# Should show: 90

# 2. Check kernel
cat /sys/kernel/realtime
# Should show: 1

# 3. Check thread priorities
ps -eLo pid,tid,class,rtprio,comm | grep marathon
# Should show:
#   PID   TID  CLS  RTPRIO  COMMAND
#  1234  1234  FF      85  marathon-shell  (main thread)
#  1234  1235  FF      75  marathon-shell  (compositor thread)

# 4. Check systemd services
systemctl show ModemManager | grep CPUScheduling
# Should show:
#   CPUSchedulingPolicy=fifo
#   CPUSchedulingPriority=90
```

---

## Performance Impact

### Expected Results (OnePlus 6 / Librem 5)

| Metric | Before | After RT | Improvement |
|--------|--------|----------|-------------|
| Touch Latency | 20-30ms | <16ms | **~40% faster** |
| Frame Jitter | 5-10ms | <2ms | **80% reduction** |
| Audio Glitches | Occasional | None | **100% eliminated** |
| Input Responsiveness | Good | Instant | **Subjectively better** |

### Why It Matters

1. **Touch Input** (Priority 85): No delays processing screen touches
2. **Compositor** (Priority 75): No frame drops during rendering
3. **Audio** (Priority 88): No audio stuttering during load
4. **Telephony** (Priority 90): Phone calls never interrupted

---

## Troubleshooting

### "⚠ No RT scheduling permissions"

**Solution**: Run `configure-rt-linux.sh` as root, then reboot.

**Manual fix**:
```bash
# Add user to marathon-users group
sudo usermod -aG marathon-users $USER

# Verify limits.conf
cat /etc/security/limits.d/99-marathon.conf

# Re-login or reboot
```

### "⚠ Not running on PREEMPT_RT kernel"

**Solution**: Rebuild kernel with `CONFIG_PREEMPT_RT=y`.

**PostmarketOS**:
```bash
# Edit kernel config
pmbootstrap kconfig edit linux-postmarketos-qcom-sdm845

# Enable: General Setup → Preemption Model → Fully Preemptible Kernel (Real-Time)
# CONFIG_PREEMPT_RT=y

# Rebuild kernel
pmbootstrap build linux-postmarketos-qcom-sdm845

# Flash to device
pmbootstrap flasher flash_kernel
```

### "Operation not permitted" even with limits.conf

**Check**:
```bash
# 1. Verify group membership
groups
# Should include: marathon-users

# 2. Check PAM configuration
cat /etc/pam.d/system-login
# Should include: session required pam_limits.so

# 3. Check ulimit
ulimit -r
# Should show: 90 (not 0)
```

---

## QML API Reference

### RTScheduler Object

Available globally in QML:

```qml
// Check if RT kernel is active
if (RTScheduler.isRealtimeKernel()) {
    console.log("Running on PREEMPT_RT kernel")
}

// Check permissions
if (RTScheduler.hasRealtimePermissions()) {
    console.log("RT scheduling enabled")
}

// Get current thread info
console.log("Policy:", RTScheduler.getCurrentPolicy())  // "SCHED_FIFO"
console.log("Priority:", RTScheduler.getCurrentPriority())  // 85

// Set RT priority for current thread (from QML worker thread)
RTScheduler.setRealtimePriority(80)
```

---

## Future Work (Spec Implementation)

### Completed ✅
- [x] RT thread priorities (compositor: 75, input: 85)
- [x] App launch time measurement (<300ms)
- [x] Active Frames throttling (10 FPS)

### In Progress 🚧
- [ ] Touch latency optimization (<16ms target) - needs hardware testing
- [ ] Performance profiling hooks

### Planned 📋
- [ ] VSync-synchronized frame delivery
- [ ] App sandboxing (Landlock/seccomp)
- [ ] D-Bus permission system
- [ ] Memory quota enforcement
- [ ] Suspend/resume lifecycle
- [ ] QT_LOGGING_RULES configuration

---

## References

- **Marathon OS Technical Spec v1.2** - Section 3 (RT Priority Hierarchy)
- **Linux PREEMPT_RT Documentation** - https://wiki.linuxfoundation.org/realtime/start
- **PostmarketOS Wiki** - https://wiki.postmarketos.org/
- **SCHED_FIFO man page** - `man 7 sched`
- **pthreads man page** - `man 7 pthreads`

---

**Last Updated**: October 27, 2025  
**Status**: Ready for Linux testing

