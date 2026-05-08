# Real-Time Scheduling in Marathon Shell

## TL;DR

Marathon's compositor and input-handling threads run on `SCHED_FIFO` for low-jitter
frame delivery. `SCHED_FIFO` is part of POSIX and is supported by **every** Linux
kernel -- it does **not** require `PREEMPT_RT`. The only thing the shell actually
needs is the `CAP_SYS_NICE` capability (or an equivalent `rtprio` entry in
`/etc/security/limits.conf`). This is the same setup model Plasma Mobile, Phosh,
postmarketOS and Android all use.

`PREEMPT_RT` is a separate, optional kernel feature that bounds worst-case
latency for `SCHED_FIFO` threads. It's a real benefit for hard-real-time audio
paths but the difference is below the noise floor for a 60–120 Hz touch UI.
**You do not need a `PREEMPT_RT` kernel to run Marathon.**

---

## What Marathon actually elevates

| Component | Thread | Policy | Priority | Source |
|---|---|---|---|---|
| Wayland compositor | render thread | `SCHED_FIFO` | 75 | `shell/src/wayland/waylandcompositor.cpp` |
| Input/UI main thread | shell main thread | `SCHED_FIFO` | 85 | `shell/main.cpp` (when enabled) |
| Marathon apps | runner threads | `SCHED_OTHER` | -- | (apps inherit normal scheduling) |

These priorities live below the conventional system slots that should always
out-prioritize the shell on a real device:

```
Priority 99 -- kernel critical
Priority 95 -- kernel softirq / NAPI
Priority 90 -- modem/cellular daemon (ModemManager)
Priority 88 -- audio (PipeWire / WirePlumber)
─── Marathon main thread (input)        ─ 85 ──
─── Marathon compositor render thread   ─ 75 ──
Priority 50 -- kernel IRQ threads
Priority  0 -- SCHED_OTHER (normal apps)
```

If audio or telephony glitch under load that's the wrong tradeoff -- keep the
audio/modem priorities above the compositor.

---

## Setting it up on a real device

### 1. Ensure `CAP_SYS_NICE` is granted

Pick one of:

```bash
# Option A -- capability on the binary (preferred for production images)
sudo setcap cap_sys_nice+ep /usr/bin/marathon-shell-bin

# Option B -- limits.conf for the user account (works for development too)
sudo tee /etc/security/limits.d/99-marathon.conf <<'EOF'
@marathon-users  -  rtprio  90
@marathon-users  -  nice   -10
@marathon-users  -  memlock unlimited
EOF
sudo groupadd -f marathon-users
sudo usermod -aG marathon-users "$USER"
# log out + log back in (or reboot) for limits to apply
```

Verify:

```bash
ulimit -r        # should print 90 (or whatever you set)
getcap /usr/bin/marathon-shell-bin
# cap_sys_nice=ep
```

### 2. Run the shell. Marathon will log:

```
[RTScheduler] Standard preemptible kernel (CONFIG_PREEMPT). PREEMPT_RT is not
              required for typical phone workloads.
[RTScheduler] SCHED_FIFO scheduling available
[WaylandCompositor] Compositor thread set to RT priority 75 (SCHED_FIFO)
```

### 3. Confirm the threads landed at the right priority

```bash
ps -eLo pid,tid,class,rtprio,comm | grep marathon-shell
#  PID   TID  CLS  RTPRIO  COMMAND
# 1234  1234   FF      85  marathon-shell
# 1234  1235   FF      75  marathon-shell
```

`CLS=FF` confirms `SCHED_FIFO`; `CLS=TS` would mean we fell back to `SCHED_OTHER`.

---

## When `PREEMPT_RT` is worth it

`PREEMPT_RT` reduces worst-case latency for `SCHED_FIFO` threads under load.
Published numbers (cyclictest under stress, comparable hardware):

| Kernel | Worst-case latency under load |
|---|---|
| `CONFIG_PREEMPT_NONE` (server) | many milliseconds |
| `CONFIG_PREEMPT_VOLUNTARY` (default) | low ms |
| `CONFIG_PREEMPT` (low-latency desktop) | ~700 µs |
| `CONFIG_PREEMPT_RT` (fully preemptible) | ~280 µs |

For a 60 Hz UI the frame budget is **16,667 µs**. The PREEMPT_RT improvement
(~420 µs) is 2.5 % of one frame -- invisible to a user. It matters when you have
a real-time audio thread that needs to wake on a 1 kHz tick, or when you're
piping cellular voice frames through user-space DSP. **For a phone shell it's a
nice bonus, not a requirement.**

`PREEMPT_RT` does carry costs:
- Slight throughput penalty (more context switches, sleeping spinlocks)
- Battery cost (more wake-ups under contention)
- Some vendor SoC drivers (cellular, camera ISP, GPU) haven't been audited for
  RT correctness -- using `PREEMPT_RT` can surface latent bugs in those drivers
- Diverges from the kernel ecosystem your distro of choice (postmarketOS,
  Mobian, Droidian) is targeting

If you want it anyway, build a kernel with `CONFIG_PREEMPT_RT=y`. Marathon will
detect it via `/sys/kernel/realtime` and log:

```
[RTScheduler] PREEMPT_RT kernel detected (bonus: bounded worst-case latency)
```

No further configuration is needed; the same `SCHED_FIFO` calls now run with
bounded preemption.

---

## How this compares to other mobile stacks

| Stack | Kernel | RT scheduling? |
|---|---|---|
| **Android (AOSP)** | `CONFIG_PREEMPT_FULL` | `SCHED_FIFO` for SurfaceFlinger / audio |
| **postmarketOS** | `CONFIG_PREEMPT` (mainline) | `SCHED_FIFO` via PipeWire / ModemManager / phosh-osk-stub. Explicitly disables `CONFIG_RT_GROUP_SCHED` (pmaports#2652) |
| **Plasma Mobile** | distro kernel (typically `CONFIG_PREEMPT`) | `SCHED_FIFO` via KWin compositor when permitted |
| **Phosh** | distro kernel | doesn't elevate by default |
| **Marathon** | `CONFIG_PREEMPT` (any) | `SCHED_FIFO` for compositor (75) + input (85) |

None of these require `PREEMPT_RT` for daily-driver use.

---

## Troubleshooting

### `SCHED_FIFO not permitted -- compositor/input threads will run on SCHED_OTHER`

You don't have the capability. Apply step 1 above and re-launch.

If it still fails after `setcap`:
```bash
getcap /usr/bin/marathon-shell-bin   # confirms cap_sys_nice=ep landed
ulimit -r                            # if zero, limits.conf isn't taking effect
groups                               # confirm marathon-users membership
```

The most common cause is logging in via a session manager that doesn't run
`pam_limits.so`; greetd/seatd/SDDM all do, but a stripped-down login may not.

### `PREEMPT_RT kernel detected`, but I'm seeing jitter anyway

`PREEMPT_RT` only helps if your threads are actually `SCHED_FIFO`. Confirm with
`ps -eLo class,rtprio,comm | grep marathon`. If `CLS=TS`, the SCHED_FIFO request
silently failed -- check `dmesg` for `denied`/EPERM messages.

### How do I know if I should bother with `PREEMPT_RT`?

Run `cyclictest -p 80 -t 1 -n -m -D 30s` under load. If your worst-case latency
fits comfortably inside your frame budget (`< 5 ms` at 60 Hz, `< 2 ms` at 120 Hz),
`PREEMPT_RT` will not noticeably help the UI.

---

## QML API

```qml
import MarathonOS.Shell

// Capabilities
RTScheduler.isRealtimeKernel()       // true on PREEMPT_RT, false elsewhere
RTScheduler.hasRealtimePermissions() // true if SCHED_FIFO is available

// Current thread
RTScheduler.getCurrentPolicy()       // "SCHED_FIFO" / "SCHED_OTHER" / ...
RTScheduler.getCurrentPriority()     // 0-99

// Elevate the calling QML thread (rare; usually only the C++ side does this)
RTScheduler.setRealtimePriority(80)
```

---

## References

- `man 7 sched` -- Linux scheduling overview
- `man 7 capabilities` -- `CAP_SYS_NICE` semantics
- [PREEMPT_RT -- Linux Foundation Wiki](https://wiki.linuxfoundation.org/realtime/start)
- [PREEMPT_RT -- Kernel docs](https://docs.kernel.org/core-api/real-time/)
- [postmarketOS pmaports kconfigcheck.toml](https://gitlab.com/postmarketOS/pmaports/-/blob/master/kconfigcheck.toml) -- the actual postmarketOS kernel-config policy (no `PREEMPT_RT` requirement)
- [postmarketOS pmaports#2652](https://gitlab.postmarketos.org/postmarketOS/pmaports/-/issues/2652) -- why postmarketOS disables `CONFIG_RT_GROUP_SCHED`
- [Reghenzani et al., "The Real-Time Linux Kernel: A Survey on PREEMPT_RT"](https://dl.acm.org/doi/fullHtml/10.1145/3297714) -- published latency / throughput tradeoffs
