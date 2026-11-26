# Jolla Phone (2026) mainline bring-up

The plan and the reasons behind it are in
`reports/Jolla Phone 2026 mainline port.md`. This file tracks the kernel
tree and the Marathon image. On 2026-11-25 the stock LK booted the
chain-loaded U-Boot from `boot_b` (slot B) and the kernel below from a
rescue FIT there: 8 CPUs, 12 GB, UFS, simpledrm 1032x2272 with fbcon, and
the USB NCM gadget. The first Marathon image (below) has not run yet.

## Kernel tree

- `/mnt/deckard-build/jolla/linux`, branch `jp2601/initial`, on torvalds
  `4dce97c6c` (v7.4-rc4). Jolla's MT6858 pinctrl and power domains are
  already in that base.
- Build: `make O=<build> defconfig mt6858.config`, then `make Image dtbs`.
- The series is SoC work first, with one board patch on top. It belongs in
  the per-SoC kernel package (`linux-mt6858`), not in this directory.

| Commit | What |
|---|---|
| `dt-bindings: vendor-prefixes`, `arm: mediatek` | `jolla` prefix, `jolla,jp2601` |
| `dt-bindings: mfd: syscon`, `mediatek,mt8195-scpsys` | the six bus protection blocks and SCPSYS |
| `dt-bindings: serial`, `watchdog`, `usb: mtu3`, `phy: xsphy` | MT6858 compatibles with existing fallbacks |
| `arm64: dts: mediatek: Add MT6858 SoC` | CPUs, PSCI, GICv3, PMUs, timer, UARTs, pinctrl, watchdog, power controller |
| `mt6858: Add UFS and USB on a stand-in clock` | UFS host and PHY, MTU3 and XS-PHY |
| `Add Jolla Phone (JP2601)` | console, LK framebuffer, LK carve-outs, ramoops, UFS, USB device |
| `arm64: configs: Add an MT6858 first-boot fragment` | `mt6858.config` |

## What the device tree takes from the phone

Read from the live DTB (`~/q25-build/jolla2026-probe/jp2601.dtb`):
register addresses and interrupts, the CPU MPIDRs and which four are the
little cores, the 13 MHz timer, the GIC redistributor size, the pinctrl and
EINT banks, `mt8183-ufshci`/`mt8183-ufsphy`, the MTU3 and XS-PHY layout, the
26 MHz PHY reference clock, the UFS VCC rail, every fixed reserved region
(the vendor drivers' CMA pools are left out), and the framebuffer base and
size.

Inferred, not measured:

- The cores are Cortex-A55 and Cortex-A78: the stock DT names its PMU nodes
  that way, but no MIDR was read.
- The framebuffer is 1056 pixels a line, ARGB8888, and the first of three
  buffers. LK's 0x1b80000-byte reservation is three 1056x2272x4 frames
  rounded to 64 KiB, and other MediaTek phones pad the same way.
- The ramoops record and ftrace sizes are the stock kernel's defaults; the
  stock command line sets only the address, size, console and pmsg sizes.
- The panel is AMOLED: LK's panel name gives a Visionox VTDR6126 driver IC.

## Placeholders

Each goes away with the driver named:

- `clk_lk_gate`: one fixed clock for the UFS host, UFS PHY and MTU3 gates.
  It works only because LK leaves them running. Replace it with clk-mt6858.
- `reg_vemc`: the UFS VCC is MT6363 VEMC, described as an always-on fixed
  regulator. Replace it with the MT6363 regulators once SPMI is up.
- `/memory` has size 0 for the bootloader to fill.
- The reserved regions are copies of what LK placed on Sailfish OS 5.2.0.22.
  LK allocates most of them at boot, so the chain-loaded U-Boot has to pass
  on LK's own list.
- The UFS nodes use bare `mediatek,mt8183-*` compatibles, as the stock tree
  does; upstream will want MT6858 ones.

`make dtbs_check W=1` and `dt_binding_check` are clean for these files,
checkpatch is clean, and `make Image dtbs` builds without warnings (GCC 16.2,
native aarch64).

## Not there yet

- **Clocks.** There is no `clk-mt6858`. It is the main gap: every power
  domain beyond the three listed, cpufreq, I2C/SPI, display, GPU and audio
  wait on it. Ask Jolla (the pinctrl and pmdomain author) before writing
  one: duplicating an unposted Jolla driver is the biggest waste risk.
  The vendor `clk-mt6858.c` in OPPO's 6.12 tree is the register reference.
- CPU idle states and cpufreq-hw. The idle states in the stock DT are
  known, but the deeper ones need SPM firmware state; leave them out of the
  first boot.
- SPMI, MT6363 and MT6369 regulators, MT6720 charger and gauge.
- Display pipeline and the VTDR6126 panel, GPU (GPUEB), touch, radios.

## The Marathon image

`scripts/build-jolla-jp2601-image.sh` builds it, as the Q25's wrapper does:
mkosi bakes the root alone (`[boot.carrier]` in `device.toml`), and
`scripts/carrier/carrier-userdata-image.sh` makes the whole `userdata`
partition from it, a nested GPT with 4 KiB sectors:

- p1, the ESP: systemd-boot, `linux.efi`, the root's initramfs, the DTB and
  one loader entry (`jp2601.rootfs_file=`, the command line from
  `device-jolla-jp2601`);
- p2, the carrier: the root as
  `/var/lib/marathon/images/jolla-jp2601_marathon_edge_<version>.ext4`.

U-Boot (`jp2601-chainload.env`) finds `userdata`, maps it with blkmap and
runs `bootefi bootmgr` when `/EFI/BOOT/BOOTAA64.EFI` is on its first
partition; without that it boots the rescue FIT in `boot_b`. systemd-boot
loads the DTB and U-Boot's EFI DT fixup adds LK's reserved memory, the boot
reason and the framebuffer to it (`ft_system_setup`), as for the FIT. The
initramfs grows the carrier into the rest of `userdata` on first boot.

Packages: `linux-mt6858` (the SoC kernel), `device-jolla-jp2601`
(deviceinfo, command line), `marathon-carrier` (the carrier runtime, shared
with any carrier phone) and `device-jolla-jp2601-marathon` (session,
profile, splash, USB networking, Deckard's settings).

### What the first image carries, against the Q25

| Q25 feature | JP2601 | Notes |
|---|---|---|
| Marathon shell, base config, apps | yes | on the Mali-G610: Panthor (power through the GPUEB), eglfs on simpledrm's KMS device, which Mesa's kmsro pairs with Panthor; Qt Quick software on simpledrm's fbdev when Panthor has no render node |
| Encrypted `/home` (LUKS2 file on the carrier) | yes | `marathon-carrier-home-crypt`, the Q25's script made generic; opens with no prompt until a PIN is set |
| Startup PIN entry | yes, needs touch | no keyboard, so Plymouth's prompt (keyboard only) gives way to unl0kr's on-screen keyboard; it can take the PIN only once touch works. A developer image also takes it over USB: `echo PIN \| ssh root@172.16.42.1 marathon-carrier-home-unlock` |
| Plymouth splash, initramfs to shell | yes | `plymouth.use-simpledrm` (simpledrm is the real card here), one daemon, handover once the shell has `/dev/fb0` or the simpledrm card open |
| Boot reason, charger boot | yes | U-Boot passes `marathon,boot-reason`/`boot-mode` from LK; `marathon-charger` reads them. No charger driver, so nothing to show yet |
| Over-the-air root updates, boot counting, bless, rollback | yes | `marathon-carrier-root-install`/`-root-arm`, `packaging/ota/carrier` transfer; the feed `jolla-jp2601_marathon_edge` has no releases yet |
| Root growth, direct I/O, read-only ESP | yes | `marathon-carrier` |
| Deckard (Android) | yes, unverified | `deckard` and `deckard-images`, Rust binder (mainline's), legacy iptables; Android renders without the GPU |
| Vulkan | yes, unverified in the image | PanVK (`mesa-vulkan-panfrost`); an offscreen render test passes on the phone from the bring-up initramfs |
| Slot kept (LK's A/B tries) | yes | `jp2601-mark-boot-successful`, the MP01's, marks slot B successful in misc a minute into the session; without it LK falls back to slot A after seven boots |
| U-Boot update from the root (`q25-lk-update`) | no | U-Boot is in `boot_b`, written by hand; nothing in the root updates it yet |
| Q25 hardware services (modem, Wi-Fi, BT, GNSS, audio, camera, NFC, haptics, charger, zram after boot) | no | no drivers on this SoC yet; zram comes from `marathon-base-config` |
| Firewall, hardening sysctl, logind policy | no | Q25-only files in `device-zinwa-q25-marathon`; they belong in the shared `marathon-phone-base` (WP1) |

The screen never blanks (`screen_timeout_ms = 0`): there is no power-key
or touch driver to wake it.

### Touch

The live DTB has the panel's touch controller as `hynitron_spi@0`,
`compatible = "hyn,66xx"` (a Hynitron CST66xx), on SPI3 at `0x11013800`
(`mediatek,mt6858-spi`, GIC SPI 400) chip select 0, 6 MHz. Its interrupt is
EINT 6, falling edge; `vdd-gpio` is GPIO 130, `power-gpio` GPIO 131,
`reset-gpio` GPIO 137 and `irq-gpio` GPIO 6, all on the MT6858 pinctrl.
`display-coords` is 0 0 1030 2271, unswapped and unmirrored, ten contacts.
Stock Sailfish loads it as `hynitron_spi` and names the input device
`hyn_ts`. The kernel needs:

1. `clk-mt6858`: the SPI3 block takes `parent-clk`, `sel-clk` and `spi-clk`
   from `cksys` (topckgen) and `pericfg_ao`.
2. `spi-mt65xx` with an MT6858 compatible (its `pad-select`, `tickdly` and
   reset bit as in the stock node) and the SPI3 node in `mt6858.dtsi`.
3. A Hynitron CST66xx SPI input driver: mainline has only `hynitron_cstxxx`
   (CST3xx over I2C). The protocol comes from the stock `hynitron_spi`
   module's source (Jolla's or the vendor's GPL release).
4. The two GPIO rails as fixed regulators, the reset GPIO and EINT 6 in the
   board DTS.

## Next

1. Flash the first image (`/mnt/deckard-build/jolla/img/FLASH.md`) and
   read its boot over USB and from U-Boot's last-log screen.
2. Ask Jolla about their clock and DT plans; `clk-mt6858` unblocks touch,
   SPMI and everything after it.
3. Touch (above), then the PMIC keys, so the screen can blank and wake.
