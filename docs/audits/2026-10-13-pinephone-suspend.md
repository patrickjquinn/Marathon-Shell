# PinePhone: "goes to sleep and never wakes" — 2026-10-13

Original PinePhone (1.2, A64 + AXP803 + EG25-G), Marathon image built with
patch 0022's U-Boot boot path. Symptom from the user: the phone goes to
sleep and does not wake until a hard restart.

## Evidence (on-device, 2026-10-12)

- **Not a kernel hang caught by the watchdog.** An unfed `/dev/watchdog0`
  reset the SoC in ~20 s. During field hangs the watchdog was reported armed
  and fed, yet nothing reset. The phone also dropped off USB.
  - The watchdog was only armed after a `systemctl daemon-reexec`: sunxi_wdt
    was an out-of-tree module that loaded at ~32 s, after systemd had
    already looked for a watchdog. **On a normal boot nothing fed or armed
    it**, so field hangs on normal boots tell us nothing about the watchdog.
- **Deep suspend resume is unreliable.** `mem_sleep` is `[deep]`.
  - `rtcwake -m mem +20 s` resumed.
  - RTC +120 s never resumed (the power key may have been pressed during
    it). It needed a hard power-off.
- **Firmware on the device** (from the dumped U-Boot area):
  - U-Boot SPL 2023.01 built 2026-05-31: pmaports `u-boot-pinephone`
    2023.01-r5, the current pmOS binary.
  - **TF-A `v2.14.0(release)`** (Alpine 2.14.0-r0).
  - Crust SCP at 0x50000, 10060 bytes (Alpine crust-pinephone 0.6-r2).
- **No evidence survived the field hangs:**
  - journald was volatile. marathon-base-config r39 in the image shipped
    `Storage=volatile`; journald starts in the initrd and never re-reads
    `/etc`.
  - The kernel had no pstore, no lockup detectors and no PM debug.

## 1. What initiates suspend in normal use?

I searched the shell, apps, the runner, `packaging/**`, the duranium tree,
and every pmaports package the PinePhone image pulls in (device-pine64-pinephone
and its subpackages, postmarketos-base-ui, postmarketos-base-systemd, upower,
eg25-manager). **Nothing in the shipped image suspends the phone on its
own.** Ranked by how reachable each path is:

| # | Path | Reachable? | Evidence |
|---|---|---|---|
| 1 | logind idle, lid or keys | No | Overlay `logind.conf.d/50-marathon.conf`: HandlePowerKey/SuspendKey/HibernateKey/LidSwitch=ignore, IdleAction=ignore. LidSwitchExternalPower/Docked inherit HandleLidSwitch. pmOS's own `logind.conf` only sets HandlePowerKey=ignore. |
| 2 | Shell power key / power menu "Sleep" | No (Doze) | `PowerPolicyController::sleep()` → `enterDoze()`: backlight + CRTC off, freeze apps, wifi PSM. No system suspend. |
| 3 | Shell idle timer | No | `PowerManagerCpp::checkIdleState` only logs "Auto-suspend triggered"; nothing acts on it. |
| 4 | Critical battery | Power-off, not suspend | `PowerPolicyController::performCriticalPowerAction` follows UPower's `GetCriticalAction`. device-pine64-pinephone-upower sets `CriticalPowerAction=PowerOff` at 15%. UPower 1.91 refuses Suspend without AllowRiskyCriticalPowerAction. A bogus AXP803 low reading on battery would **power the phone off**. That looks like "dead until I hold power", with no reset and off USB, so it fits the symptom too (see 2.4). |
| 5 | `org.marathonos.Shell.Power1.Suspend` | System callers only | `PowerObject::Suspend` → `requireSystem()`. `PowerClient::suspend()` in the runner has no caller in any app. |
| 6 | `SystemControlStore::sleep()` → `PowerManagerCpp::suspend()` | Dead code | No QML or C++ caller. It would be a real S3 path if anything ever called it. |
| 7 | gnome-settings-daemon (`sleep-inactive-battery-timeout=120`) | Not installed | Only installed with gnome-control-center. The Marathon session starts no xdg autostart target. |
| 8 | Manual `rtcwake` / `systemctl suspend` | Yes, testing only | `scripts/marathon-doze-measure*.sh`, tonight's experiments. |

So the field "sleep" is almost certainly **Doze** (screen off, system
running, CPUs mostly idle). Two hypotheses fit "never wakes, no reset, off
USB" without any S3:

- **A. CPU-idle hang from TF-A 2.14.0.** TF-A v2.13.0–lts-v2.14.2 pass
  `end_pwrlvl` where `max_off_lvl` belongs in `psci_cpu_suspend_start()`
  (83ec7e452, fixed by 3ea758882 in lts-v2.14.3 / v2.15.0).
  - On the A64 the cluster idle state is retention (0x01010013), so every
    cluster-sleep entry runs `cortex_a53_cluster_pwr_dwn`. That is a
    set/way clean+invalidate of L1 and the shared L2, plus an SMP exit,
    with the other cores possibly live.
  - That is exactly the screen-off idle pattern.
  - A hang here leaves the SoC dead. A fed watchdog would reset it, but on
    normal boots the watchdog was never armed.
  - Confidence: high that the bug is present, medium-low that it is the
    hang.
- **B. Unintended power-off** from a critical-battery reading (row 4). It
  is undetectable without a persistent journal.

A third, weaker one: **C. Doze wake wedge on sun4i-drm/st7703**.
CRTC ACTIVE=1 blocks the shell's thread ~800 ms on this panel, and the Doze
DPMS path was only validated on the Librem 5. The kernel stays alive here,
so USB/ssh would still answer and the new hung-task detector would log it.

The suspend that *did* fail (RTC +120 s) was a manual experiment. It
matches an open postmarketOS bug on this exact stack: **pmaports#4397**
(a power-key press shortly after entering suspend and the PinePhone never
wakes; USB/ssh dead too) and **crust#204** (power key intermittently doesn't
wake). Neither has a root cause upstream.

## 2. Why deep resume fails on this stack

How suspend flows on the A64:
1. Linux takes CPUs 1–3 offline and calls PSCI SYSTEM_SUSPEND.
2. TF-A sends SCPI SET_CSS_POWER_STATE to Crust over **its own** secure
   msgbox channels.
3. Crust puts DRAM into self-refresh, gates the clocks and the 24 MHz
   oscillator (which also stops the A64 watchdog), and cuts VDD-CPUX.
4. Crust then polls R_INTC for a wake interrupt: AXP803 NMI for the power
   key or VBUS, the RTC, and r_pio (modem RI on PL6).

Linux never talks SCPI itself: there is no `scpi` DT node. So the unbound
Linux msgbox at 0x1c17000 does not matter for suspend. `[deep]` being
offered proves TF-A came up in SCPI mode with Crust.

- **2.1 Known upstream race (#4397 / crust#204).** A wake event arriving in
  the suspend-entry window is lost or hangs a driver's resume after an
  aborted suspend. Unfixed upstream. Diagnosing it needs Crust's step
  record (below).
- **2.2 TF-A 2.14.0.** This does not affect SYSTEM_SUSPEND itself
  (`end_pwrlvl == max_off_lvl == 2`). It affects cpuidle and s2idle.
- **2.3 Ruled out.**
  - U-Boot 2023.01 loads the SCP correctly; megi's p-boot is not needed.
  - The pmaports#1974 resume failures were fixed by this U-Boot.
  - megi's 6.18 tree has the RSB runtime-PM and TWD-clock fixes Crust's
    ABI needs.
- **2.4 Worth checking.**
  - **EG25 modem firmware.** Forum reports tie old firmware to no-resume.
  - **pmaports#2834.** Charging stops ~10 min into sleep; a flat battery
    looks like "never wakes".
- **Power.** Deep is ~110 mW (megi). s2idle keeps DRAM, PLLs and the CPU
  rail on: several times that, not yet measured on the A64.

## 3. Fixes (commits on feat/keel-framework-1a)

| Commit | What |
|---|---|
| 10e49520 (earlier, lead) | journald `Storage=persistent` in `/usr/lib/systemd/journald.conf.d/50-marathon.conf`. The initrd copies this file, so the initrd journald now flushes to `/var/log/journal`; the old `/etc` drop-in never reached it. Systemd feeds the watchdog (RuntimeWatchdogSec=15s). |
| 04c3c734 (earlier, lead) | Kernel fork `linux-postmarketos-allwinner-marathon`: SUNXI_WATCHDOG=y (built in, so systemd finds it at boot), soft/hard lockup → panic, hung-task logging. |
| 47f32acc | Kernel fork: PSTORE + PSTORE_RAM/CONSOLE/PMSG, PM_DEBUG + PM_SLEEP_DEBUG (`pm_test`, `pm_wakeup_irq`, suspend timing), PANIC_TIMEOUT=10. Config regenerated with olddefconfig against the exact tarball; fs/pstore and kernel/power compile. |
| 46d3bda1 | systemd-sleep hook `marathon-sleep-log`. For every sleep it writes a pre/post line (sleep state, wakeup IRQ, last failed device, boot id) to `/var/log/marathon-sleep.log`, `/dev/kmsg` and `/dev/pmsg0`. A `pre` line with no `post` line before the next boot means a failed resume. |
| 8fa24f2e | Boot script reserves 1 MiB at 0x5ff00000 as `/reserved-memory/ramoops`, because the A64 DT has none. pstore survives watchdog and panic resets, not hard power-offs. |
| 7f8ffe21 | **Boot with `mem_sleep_default=s2idle`.** Anything that still suspends stays in Linux, where the power key is an ordinary wake IRQ. Deep is opt-in: `echo deep > /sys/power/mem_sleep`. |
| 139ffbbf | **`u-boot-pinephone-marathon`**: pmaports' U-Boot rebuilt against Alpine TF-A ≥ 2.14.3. Upstream's APKBUILD no longer builds on Alpine edge (SWIG 4.4), hence patch 0005. Built here: the blob reports `v2.14.6(release)` with the identical Crust image. The apk is cached in `mkosi.packages/`. |
| 8814a81a | `scripts/build-image.sh` builds the `linux-*-marathon` / `u-boot-*-marathon` aports the device overlay depends on (`scripts/qemu/lib/build-aport-apk.sh`, alpine:edge + pmOS repo). Previously nothing built the kernel fork, so 04c3c734 never reached an image. |
| b486def3 | The device overlay depends on both forks, which provide the pmaports names at r99 so apk picks them. |

The image build now compiles the kernel fork. That needs several GB free in
podman storage (`/home` had 4.8 GB tonight). **The kernel package was not
built here** for lack of space. The U-Boot package was built and checked.

Not changed:
- The shell (no suspend trigger there).
- Dead code: `SystemControlStore::sleep()`.
- Unused file: `packaging/configs/systemd/sleep.conf.d/50-marathon.conf`
  (`SuspendMode=deep`) is installed by no package.

## 4. Morning test procedure (user present; a failed resume needs a hard reset)

**0. Build and flash.**
- Build: `scripts/build-image.sh pine64-pinephone`. The kernel fork takes
  a while.
- Flash the SD card.
- Quicker path if only the bootloader is wanted first: the new U-Boot can be
  written alone from the cached apk
  (`usr/share/u-boot/pine64-pinephone/u-boot-sunxi-with-spl-528.bin`):
  - `dd ... of=/dev/<sd> bs=1024 seek=8 conv=notrunc,fsync`
  - Do this from the host, with the SD card out of the phone.

**1. Boot checks** (ssh root@172.16.42.1):
- `uname -v` shows the fork's build.
- `cat /proc/cmdline` contains `mem_sleep_default=s2idle`.
- `cat /sys/power/mem_sleep` shows `[s2idle] deep`.
- `systemctl show -p WatchdogDevice,RuntimeWatchdogUSec`, plus `dmesg | grep -i watchdog` reporting "Using hardware watchdog". Expect this without a daemon-reexec.
- `journalctl --list-boots` lists earlier boots; `/var/log/journal` exists.
- `dmesg | grep -i -e pstore -e ramoops` shows "Registered ramoops"; `ls /sys/fs/pstore`.
- `dmesg | grep -i "NOTICE:  BL31"` or the U-Boot console shows TF-A v2.14.6.
- `ls /proc/device-tree/cpus/idle-states` and
  `grep . /sys/devices/system/cpu/cpu0/cpuidle/state*/{name,usage}` confirm cluster-sleep is in use.
- Modem firmware: `mmcli -m any | grep -i revision`. Note the version.

**2. Doze soak (hypotheses A/C).** Screen off with the power key, wait
10 min, wake. Repeat ~10× over the morning, on battery and on USB.
- If it fails to wake, try ssh first.
  - **ssh answers:** the kernel is alive; it is the display path (C).
    Collect `journalctl -b -t marathon-shell` and
    `dmesg | grep -i "blocked for more than"`.
  - **ssh dead:** expect a watchdog reset within ~20 s.
- After the next boot, collect:
  - `journalctl -b -1 -e`
  - `cat /sys/fs/pstore/*`
  - `cat /var/log/marathon-sleep.log`
- A clean shutdown at the end of `-b -1` means it powered off (B). Look for
  UPower/critical battery lines.

**3. s2idle (the new default).**
- `rtcwake -m mem -s 30` should resume by itself. Then
  `cat /sys/power/suspend_stats/last_failed_step /sys/power/pm_wakeup_irq`
  and `tail /var/log/marathon-sleep.log`.
- Repeat with a power-key press at ~1 s and ~5 s after the screen goes
  dark: the #4397 timing.
- Measure the current draw in s2idle vs Doze if a meter is at hand.

**4. Deep, only to characterise #4397.**
- `echo deep > /sys/power/mem_sleep`, then the same three runs (RTC only;
  key at ~1 s; key at ~5 s).
- Before a deep run, `echo devices > /sys/power/pm_test` (later
  `platform`, `processors`, `core`) checks Linux's half without firmware.
  `echo none > /sys/power/pm_test` restores real suspend.
- On a hang: **long-press power off, do not pull the battery** (it keeps
  the RTC registers). Boot, then read
  `journalctl -b -1 | grep -e "PM:" -e marathon-sleep`.
- The decisive data needs a Crust built with
  `CONFIG_DEBUG_RECORD_STEPS=y CONFIG_DEBUG_VERIFY_DRAM=y` and a boot with
  `cpuidle.off=1`. After a failed resume, the last step is in the RTC
  general-purpose registers (`busybox devmem 0x01f0010c`):
  - 0x60a: asleep, never saw the wake IRQ
  - 0x611–0x613: PMIC/RSB
  - 0x615–0x616: DRAM
  - 0x619: Crust finished, so the hang is in TF-A or Linux
- A serial console on the headphone jack (kill switch 6 off,
  `no_console_suspend loglevel=8`) gives Linux's side.

**5. Outcome → next step.**
- Doze solid and s2idle solid: keep the defaults.
- Doze still hangs with TF-A 2.14.6: disable cluster-sleep
  (`echo 1 > /sys/devices/system/cpu/cpu*/cpuidle/state2/disable`) to
  confirm the cpuidle path, then look at Crust/cpuidle.
- Deep only fails with the key-press timing: it is #4397. Report the
  step-record value upstream.

## Still unconfirmed

- Which hypothesis (A, B or C) caused the field hangs. Only the next
  failure with the new evidence chain will tell.
- That the U-Boot `fdt` commands build the ramoops node as intended
  (checked with fdtput on the 1.2 DTB, not in U-Boot).
- That apk picks the r99 forks over pmaports' packages in the mkosi
  install.
- That the kernel fork builds in `build-aport-apk.sh` (not built: disk).
- The s2idle power draw.
