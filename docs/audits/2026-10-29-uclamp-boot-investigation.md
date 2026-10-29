# Hackberry uclamp boot investigation — 29 October 2026

The saved `6.12.85-1-rpi` kernel booted twice on the Hackberry during this
investigation, including once with the original, unmodified initramfs and
original quiet command line. Pilot's foreground cgroup read
`cpu.uclamp.min=30.00`. Pilot and TikTok rendered; Android completed boot
and reported no ANR since boot. Neither boot had failed system/user units.
The October 24 black-screen failure was **not reproduced**, and its original
trigger remains unproven.

## What the existing evidence establishes

The October 20 deployment transcript records a successful one-shot tryboot
of the custom kernel on boot partition 3. It temporarily pointed both the
normal and trial paths at that partition, with custom kernel selection
conditional on the tryboot flag. The kernel was then selected permanently.
By October 24 the device was on stock again; the available evidence does not
establish which change had removed the custom selection.

The October 24 attempt appended unconditional custom kernel/initramfs
selection. The user reported a black screen and unsuccessful power cycles.
Recovery required restoring the stock boot config through a card reader.
With custom selection unconditional, another normal power cycle selected it
again. Merely retaining a stock image under another filename was not an
automatic rollback mechanism.

The original initramfs starts its three-minute tryboot recovery timer in
`run_hooks /hooks`, **after** `setup_udev`, framebuffer setup and splash
startup. It therefore cannot recover a hang before reaching those hooks.
That is a verified coverage gap, not proof that the October 24 failure
occurred in that phase. An unconditional normal boot also does not satisfy
the guard's tryboot condition.

Current selector configuration is `tryboot_a_b=1`, normal partition 3,
trial partition 2. Consequently a plain tryboot without adjusting selection
would try the older OS slot, not the kernel staged on partition 3. This
behaviour follows the [Raspberry Pi A/B boot documentation](https://github.com/raspberrypi/documentation/blob/master/documentation/asciidoc/computers/config_txt/autoboot.adoc).

## Artifact and VM checks

Read-only copies of the two kernel images/initramfs archives were saved on
the USB build drive. Both images are valid ARM64 4 KiB-page Images. Their
embedded banners identify stock `6.12.85-0-rpi` and custom `6.12.85-1-rpi`.
The custom image contains the utilization-clamp sysctl strings.

Configurations were recovered from each release's compressed `configs.ko`.
They differ only in these three symbols:

```
CONFIG_UCLAMP_TASK=y
CONFIG_UCLAMP_BUCKETS_COUNT=5
CONFIG_UCLAMP_TASK_GROUP=y
```

All 46 initramfs kernel modules in each archive carry the matching release's
vermagic. After normalizing release-directory names, the non-module boot
script contents match. The archives were parsed successfully; the custom
archive omits the stock archive's root-directory entry.

Both kernels booted in QEMU `virt` with KVM using two CPUs/1 GiB and four
CPUs/16 GiB. The latter included the device's fake-eight-node NUMA options.
Twelve selected module probes succeeded in every run, including device-mapper,
crypto, DRM, VC4, RP1 DPI, backlight, RP1 firmware/PIO and DWC2. Custom-kernel
runs created a CPU cgroup and read back a clamp of `30.00`; stock lacked it.
QEMU did not emulate the CM5/RP1 hardware, probe real display hardware or
exercise the Pi EEPROM bootloader. These checks establish basic kernel/module
function, not physical-device boot equivalence.

## Controlled device trials

The user confirmed physical access for recovery. Each trial temporarily
pointed the trial selector at partition 3 and selected the candidate only
inside `[tryboot]`. Ordinary boots retained stock. The disabled OS tryboot
commit services remained disabled. Original selector/config files were backed
up, checked and restored after each trial.

| Trial | Kernel/initramfs | Command line | SSH returned |
| --- | --- | --- | ---: |
| 1 | Original custom kernel; instrumented initramfs | Verbose diagnostics | 67 s |
| 2 | Original custom kernel and original initramfs | Original quiet command line | 54 s |

These elapsed times include shutdown, boot, PIN entry and networking; they
are not isolated kernel boot times. Both were software-reboot trials. A full
cold power-on was not tested. The first PIN screen appeared normally,
confirmed by the user.

The diagnostic initramfs started a recovery timer before udev and recorded
stages to the boot filesystem. Its shortened VM self-test rebooted after
3.218 seconds. Physical-device stages in trial 1 were:

| Stage | Seconds since kernel start |
| --- | ---: |
| First persisted marker; early timer already armed | 12.76 |
| Before / after udev | 12.77 / 14.36 |
| Before / after framebuffer setup | 14.37 / 14.45 |
| Before / after splash startup | 14.46 / 14.47 |
| Before / after root discovery | 15.66 / 15.67 |
| Before / after root mount | 15.81 / 15.98 |
| Before / after data unlock and cleanup | 16.09 / 23.11 |
| Initramfs complete | 23.15 |

The early timer is software recovery. It cannot reset a kernel that cannot
schedule the timer process; physical recovery remained available. Kernel
panic records were not guaranteed by userspace log capture.

Both trial journals were checked for panic/Oops/BUG, invalid module format,
symbol-version errors, segfaults, fatal signals and OOM kills: none matched.
An RP1 PIO deferred-probe warning appeared; it did not prevent these boots.
The second boot's system and user failed-unit lists were empty. Its backlight
read power 0, brightness 8, and Pilot's settled page and TikTok feed were
visually inspected. The outgoing-app/loading screen was not accepted as a
completed app launch.

Android's outer cgroup followed the existing CPU/BFQ policy (200/200 while
TikTok was foreground). Its outer `cpu.uclamp.min` read `0.00`; this test does
not claim that the existing Deckard resource setter adds a clamp floor.

## Result and remaining uncertainty

The original artifacts work in today's one-shot boot configuration. The
instrumented initramfs was not required for the second success. We have not
established whether the old failure was a bootloader/load issue, a hardware
initialization race, a display/unlock problem or something else. No October
24 failed-boot journal or pstore record was available. A successful one-shot
warm reboot does not prove that an unconditional selection or full cold boot
will always succeed.

At completion, the running kernel is `6.12.85-1-rpi`; the original stock boot
configuration and original A/B selector have been restored. **The next normal
reboot selects stock.** The custom image was not made the permanent default.
The temporary diagnostic initramfs/command-line files were removed after
saving the logs. Original kernel images, initramfs files and module trees
were preserved. Earlier zbus/performance measurements were made on stock
`6.12.85-0-rpi`; no performance improvement is claimed from these boot tests.

[Results and artifact hashes](2026-10-29-uclamp/results.json),
[configuration difference](2026-10-29-uclamp/kernel-config.diff),
[boot stages](2026-10-29-uclamp/stages.txt),
[journal signature checks](2026-10-29-uclamp/journal-checks.json), and VM logs
are retained beside this report. Original images and private full device
journals remain outside the repository.
