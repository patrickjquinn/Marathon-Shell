# Hackberry default uclamp kernel — 29 October 2026

At the user's request, the active boot configuration now selects the verified
`6.12.85-1-rpi` kernel on ordinary boots. The previous investigation used
one-shot trials and deliberately restored stock as the default afterward;
this change supersedes that temporary state.

The configuration explicitly selects the matching pair after `[all]`:

```
auto_initramfs=0
kernel=kernel_2712_uclamp.img
initramfs initramfs_2712_uclamp followkernel
```

Automatic initramfs selection is disabled because the matching archive is
specified explicitly. The normal/trial OS-slot selector was not changed.
No EEPROM, clock, display-overlay or kernel-image changes were made.

The selected files were checked before changing the default:

| File | SHA-256 |
| --- | --- |
| `kernel_2712_uclamp.img` | `7d6eaae98637287af2765fa0f023afc8046350519e69117b46410fb826d07173` |
| `initramfs_2712_uclamp` | `d078e11138186f11c1a29984baf91e2e96251802e534bf5ed0442be00f6d1c44` |

The new `config.txt` SHA-256 is
`d32c372a62d9ead575d95db6badb628565f6d1694f184b37967fc12248850ad5`.
The previous stock config is preserved at
`/boot/config.txt.stock-before-uclamp-default`, and stock kernel/initramfs
files remain intact. To select stock for the next normal boot:

```
sh /boot/restore-stock-kernel.sh --restore
```

The restore script does not reboot. It can also be invoked against the
mounted boot card from another machine. Configuration and hashes are backed
up under `/var/lib/marathon-kernel-default/20261029` on the device.

## Validation

An ordinary `systemctl reboot`, with no tryboot argument, returned with:

- Kernel `6.12.85-1-rpi`.
- Firmware `tryboot=0`.
- New boot ID `7e7f88c8-cb7d-47c9-9996-dc7ac9324a27`.
- SSH available after 40.5 seconds of monitoring following the reboot request.

That elapsed time includes shutdown, PIN entry and networking. It is not an
isolated kernel-startup measurement. A clean `systemctl poweroff` followed by physical power-on and PIN entry
also booted `6.12.85-1-rpi`, with firmware `tryboot=0` and new boot ID
`43c727a0-cd5c-499b-86f4-c65196532403`. Both failed-unit lists were empty;
no kernel crash or module-version error signatures matched. The config hash
remained unchanged. Pilot rendered and its foreground cgroup read
`cpu.uclamp.min=30.00`, returning to `0.00` after Home. Backlight power read
0 and brightness 8. NTP was
synchronized. The time waiting for physical power-on is not a boot benchmark.

The device remains on the uclamp kernel, with uclamp selected for subsequent
ordinary boots. Stock recovery files remain available. See
[activation evidence](2026-10-29-uclamp/default-activation.json) and the
[installed config](2026-10-29-uclamp/default-config.txt).

The earlier [boot investigation](2026-10-29-uclamp-boot-investigation.md)
records artifact/config comparisons, VM checks, two physical-device trial
boots, native foreground clamp readback and app rendering. Those tests did
not establish the historical October 24 black-screen trigger.
