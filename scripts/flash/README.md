# Marathon flash scripts

One shell script per target device. Each is invoked **after** its
matching `build-*-image.sh` has produced an image artifact.

| Device | Script | Status | Path |
|---|---|---|---|
| OnePlus 6 (enchilada) | `flash-oneplus6.sh` | **Ready, hardware-unverified** | fastboot (boot.img + sparse rootfs) |
| Purism Librem 5 | `flash-librem5.sh` | **Ready, hardware-unverified** | `dd` to SD, or `uuu` SDP→Fastboot to eMMC |
| HackberryPi CM5 | `flash-hackberry-cm5.sh` | **Ready, hardware-unverified** | `dd` to microSD |
| Other Hackberry variants | `flash-hackberry-pi.sh` | **Wrapper** — dispatches to CM5; other variants not supported yet | n/a |

"hardware-unverified" means the script follows the documented protocol
for each device but hasn't been tested on the actual hardware on
Marathon's branch yet. First flashes will likely need iteration.

## OnePlus 6 (enchilada)

```bash
# 1. Power off, hold Vol-Up + plug USB → fastboot mode.
# 2. Run:
./scripts/flash/flash-oneplus6.sh
```

Auto-detects the duranium GPT `.raw` + extracted `boot.img` from
`~/.cache/marathon-build/duranium/mkosi.output/oneplus-enchilada_marathon_edge/`,
unlocks the bootloader (confirm on-device), pins slot A, erases dtbo,
flashes boot.img to `boot`, sparse-converts the .raw and flashes it
to `userdata`. EDL/MSM Download Tool recovery path documented in the
script header. Use `--rootfs-only` for subsequent updates that don't
need to re-flash the bootimg.

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
steps and waits for confirmation. `phone-boot.img` is auto-located
in the build output directory (the orchestrator extracts it from
the `u-boot-librem5` apk during the bake) or can be set via
`UBOOT=…`.

## HackberryPi CM5

```bash
./scripts/flash/flash-hackberry-cm5.sh /dev/sdX
```

Decompresses (xz/gzip/zstd) on the fly and `dd`s the
`marathon-hackberry-cm5.img.xz` from `build-hackberry-cm5-image.sh`
to the target microSD. Safety: refuses common host-disk paths
(`/dev/sda`, `/dev/nvme0n1`, `/dev/vda`, `/dev/mmcblk0`), requires
explicit `YES` confirmation.

After flash: insert microSD into the Hackberry CM5 carrier, power
on. RaspiOS firmware boots → systemd → lightdm → marathon-shell as
the Wayland session under autologin user `pi` (default password
`raspberry`; change on first SSH/console login).

Marathon's QML renders responsively at 720×720 — verified
locally during the build pipeline scaffolding. Hardware bring-up
will iterate on HyperPixel timing and any RP1 DPI quirks.
