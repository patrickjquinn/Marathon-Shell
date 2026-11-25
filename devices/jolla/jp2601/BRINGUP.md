# Jolla Phone (2026) mainline bring-up

The plan and the reasons behind it are in
`reports/Jolla Phone 2026 mainline port.md`. This file tracks the kernel
tree. Nothing in it has run on a phone yet.

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

## Next

1. Ask Jolla about their clock and DT plans.
2. Port the chain-loaded U-Boot (WP2 in the report) and boot this kernel
   from `boot_b` with an initramfs, slot A untouched.
3. First-boot signs of life: the panel console, a USB ACM/NCM gadget, and
   ramoops at 0x6ec00000, readable after a warm reboot into Sailfish.
