# Marathon flash scripts

One shell script per target device. Each is invoked **after**
`build-qemu-image.sh` (or a device-specific build wrapper) has
produced an image artifact.

| Device | Script | Status | Path |
|---|---|---|---|
| OnePlus 6 (enchilada) | `flash-oneplus6.sh` | **Ready** | fastboot |
| Purism Librem 5 | `flash-librem5.sh` | **Ready** | `dd` to SD, or `uuu` SDP→Fastboot to eMMC |
| Hackberry Pi | `flash-hackberry-pi.sh` | **Blocked** | header explains 3 upstream gaps |

## OnePlus 6 (enchilada)

```bash
# 1. Power off, hold Vol-Up + plug USB → fastboot mode.
# 2. Run:
./scripts/flash/flash-oneplus6.sh
```

Script auto-detects boot.img + rootfs.img under `out/`, unlocks the
bootloader (confirm on-device), pins slot A, erases dtbo,
sparse-converts the rootfs, flashes. EDL/MSM Download Tool recovery
path in the header.

## Librem 5 (purism-librem5)

```bash
# microSD path (non-destructive — eMMC stays put):
./scripts/flash/flash-librem5.sh sd /dev/sdX /path/to/marathon-librem5.raw

# eMMC path (canonical pmOS):
./scripts/flash/flash-librem5.sh emmc /path/to/marathon-librem5.raw
```

The eMMC path uses NXP's `uuu` (mfgtools) to drive SDP →
Fastboot. Requires all three hardware kill switches OFF and the
Vol+ + battery sequence to enter SDP mode — script prints the
steps and waits for confirmation. Phone-boot.img is auto-located
or set via `UBOOT=…`.

## Hackberry Pi

Not flashable today. Read the header in
`scripts/flash/flash-hackberry-pi.sh` — three upstream items need
to land first (ST7701 panel timings, BBQ10 keyboard driver,
pmaports device dir).

`flash-hackberry-pi.sh --scaffold-4b /dev/sdX image.raw` will
write a postmarketOS image to a microSD for the HackberryPi-4B
variant and overlay pftf/RPi4 UEFI firmware so systemd-boot can
chainload. That gets you to a running kernel over UART/SSH, but
**the screen will be black and the keyboard inert** until the
three upstream items land.
