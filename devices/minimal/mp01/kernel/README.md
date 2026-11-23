`packaging/packages/linux-minimal-mp01` builds the Minimal Phone MP01 (board
`Z10`) kernel, release `7.0.0-mp01`, from the same MT6789 tree as the Zinwa
Q25: ellyq's `mtk_g99-mainline` at `978b8b67`. Nothing in it has run on an
MP01 yet; it compiles and its DT is checked, nothing more.

## Layout: one MT6789 series, two boards

The MP01 package takes linux-zinwa-q25's SoC, PMIC and generic patches by
reference (`$_mt6789` in its APKBUILD, `../linux-zinwa-q25/<patch>`), so no
patch file exists twice and a change to a shared Q25 patch fails the MP01's
checksum until someone re-checks it for this board. The Q25 package is not
touched: its APKBUILD, patches and config are byte-for-byte what they were,
and `modules/build.sh` runs the same commands for it (checked by tracing both
versions with the compilers stubbed out).

A separate `linux-marathon-mt6789-common` directory was the alternative. It
means moving 62 Q25 patch files, editing the Q25 APKBUILD and rebasing every
open Q25 kernel branch, before the second board has booted once. Taking them
by reference gets the same single series now; the move becomes a mechanical
rename once both boards boot, and the MP01's new SoC patches below go with it.

| | Where | What |
|---|---|---|
| Shared SoC/PMIC series (62) | `linux-zinwa-q25/0001`…`0139`, listed in `$_mt6789` | DRM/DSI, clocks, power domains, watchdog, UFS, idle states, SMI, MUSB, MT6358 gauge and clock buffers, PSI, panfrost. Applied without their hunks to the Q25's board DT (only `0110` has one). |
| Not taken from the Q25 | | Its board DT patches, panel and bias, BBQ keyboard, ST21NFCD, HX32062SE, ICM-42607, MMC5633, bq256xx, camera sensors, `0011`'s MD1 owner. `0040` and `0119` are Q25-DT-only; `0119`'s clock parent is `mp01-0007` here. |
| New, SoC-level | `mp01-0003`…`0008` | dither unit address; MT6789 entries in the display and mutex bindings; the five display processors in `mt6789.dtsi` (the Q25 board DT carries copies); I2C from MAINPLL in `mt6789.dtsi`; `matrix_keypad` with rows on a sleeping irqchip. They belong in the shared series and move there with it. |
| New, SoC-level: DSI lane order | `mp01-0009`…`0012` | `data-lanes` on the DSI output endpoint, routed through the MIPI TX; does nothing without the property. Moves to the shared series with the rest (`eink-series.md`). |
| Board | `mp01-0001`, `0002`, `0013`, `0014`, `0015`, `config-minimal-mp01.fragment`, `mp01-*.dtso` | vendor prefix, compatible, the `minimal,z10-eink` binding and driver, `mt6789-minimal-mp01.dts`, config delta, vendor-driver overlays |
| Config | `config-zinwa-q25.aarch64` + the fragment (`merge_config.sh`) | the fragment holds only the MP01's differences |
| Out-of-tree modules | `linux-zinwa-q25/modules`, `BOARD=mp01` | see below |

`scripts/qemu/lib/build-aport-apk.sh` now copies the whole aports tree into
its container (as the device and UI builders already do) so the relative
sources resolve.

## The DT contract with the panel and DSI work

The board DT follows the bindings of the e-paper series in this package
(`mp01-0013`'s `minimal,z10-eink.yaml`, `mp01-0009`'s `data-lanes` addition to
`mediatek,dsi.yaml`):

- the panel module is the I2C device at I2C7 0x4b (the Pango controller, bus
  at the factory 1 MHz), compatible `minimal,z10-eink`, with
  `vdd12-supply`, `vdd18-supply`, `vdd33-supply` (fixed regulators on GPIO158,
  GPIO43 and GPIO159, the vendor's `v12_en`, `v18_en`, `v33_en`, boot-on
  because LK leaves its picture up), `reset-gpios` (GPIO85, active low),
  `backlight` (the frontlight), `rotation = <270>` (left side up: LK and
  the chain-loaded U-Boot turn their text that way on the phone, and DRM
  turns fbcon to match, as `fbcon=rotate:3` does) and a `port` to the DSI output; its
  driver registers the DSI device on that host;
- 4 data lanes, RGB888, video mode, 800x600 (vendor driver: `dsi->lanes = 4`,
  HFP/HSA/HBP 20/16/20, VFP/VSA/VBP 54/10/10, 34617 kHz);
- the lane map as `data-lanes = <1 2 4 3>` on the DSI output endpoint: the
  physical lane, 1 to 4, carrying each logical lane. The vendor's `lane_swap`
  table crosses lanes 2 and 3, which reads the same in either direction;

## GPIO decisions

| GPIO | Factory DT users | Decision |
|---|---|---|
| 12 | panel `pm-enable-gpios`, mtkfb `lcm_led_en` states, NXP NFC `nxpnfc-ven`, `gate_ic@11` power | **NFC VEN.** The vendor panel driver never requests `pm-enable`; the gate IC is commented out in it (`//gate-ic = <4831>`, bias code `#if 0`); the mtkfb states are MediaTek template. The DCT boots the pin as an output low, and LK shows its logo with it low, so the display does not need it. The stock `nxpnfc` driver toggles it for every NFC power cycle (LuneOS: NFC works on stock). |
| 5 | AW9523B `irq-gpio` (overlay), RT5133 `interrupts-extended` (base) | **AW9523B INTN.** The RT5133 never probes on stock (LuneOS: "rt5133@18 stays deferred, Failed to request HWEN gpio"); it would only feed camera rails, so it is left out. DCT: input, pull-up. |
| 35 | AW9523B reset | `reset-gpios`, active high: the upstream driver drives RSTN's level. DCT leaves it low (chip in reset) until the driver runs. |
| 9, 152 | touch IRQ, reset | edge-falling IRQ (overlay `<9 2>`), reset active low |
| 1, 3 | NFC IRQ, firmware download | IRQ edge-rising, so an unpowered controller cannot storm the line; `firmware-gpios` |
| 84 | DISP_PWM (DCT mode 1) | frontlight `pwm-backlight`, 39385 ns as the vendor |
| 66, 67 | KPCOL0/1 | as the Q25: volume down and the key between the volume keys |
| 85, 158, 159, 43, 83 | panel reset, EPD rails, DSI TE | panel contract above; TE unused |
| 68 | PWM_1 (DCT mode 3), the warm light | not described: the SoC PWM (`mediatek,mt6789-pwm`) has no driver match yet |

Keyboard: the AW9523B's upstream GPIO/pinctrl driver with
`gpio-matrix-keypad`. Rows are the inputs P1_2-P1_7 (AW9523 lines 10-15),
columns the outputs P0_2-P0_7 (lines 2-7), active low, columns floated when
inactive, which is what the vendor scanner does. The keymap is the vendor
table's first 36 entries, index row * 6 + column; its private codes become
`KEY_RIGHTALT` (SYM), `KEY_EMOJI_PICKER` (EM) and `KEY_VOICECOMMAND` (MIC).
The vendor table's later entries (F9-F12, arrows, copy/paste…) are not
reached by its matrix scan; an FN layer belongs in the keymap (xkb). The key between the volume keys
(stock 252, unassigned) is `KEY_REFRESH`. The keyboard LEDs (P0_0, P0_1,
P1_0, P1_1) need the AW9523's constant-current LED mode, which no upstream
driver has; driving them as plain GPIOs would sink unlimited current, so they
are not described.

`matrix_keypad` as it was called `disable_irq_nosync()`/`enable_irq()` under
its spinlock; the AW9523's irqchip takes a mutex there, so `mp01-0008` moves
those calls out of the lock (the commit explains why the disable depth stays
balanced). A scan is roughly 50 I2C transfers, on the order of 20 ms at the
factory 100 kHz.

## Memory and the boot chain

On MediaTek's stock LK the kernel's DT is LK's own `lk_main_dtb` plus the
signed `dtbo`; a DTB in `boot` or `vendor_boot` never reaches the kernel. The
Daylight DC-1 port gets its own DT in with a stub in the `boot` image's kernel
slot that swaps the FDT and copies `/chosen/bootargs`, the initrd and
`/memory` from LK's tree (github.com/denysvitali/dc-1-pmos `boot/dtbswap`). LK
prepends its `mblock-N-*` reserved regions only to its own tree. So this DT
describes its reserved memory itself:

- regions at fixed addresses: BL31, crypto, AEE, ramoops, TEE, CONSYS EMI,
  TEE secmem, GenieZone, MCUPM, log store, EMI MBIST, modem shared memory,
  SCP shared, SSPM, MET, Wi-Fi;
- windows over what LK places at boot: `0xbf600000` +10 MiB (SCP, ATF log,
  CCCI tag, rank 0's last page), `0xde000000` +128 MiB (the four MD1
  regions, the DSP image last at `0xe5200000`), `0xfd000000` +48 MiB (debug
  dump, logo framebuffer), and rank 1's last page.

The addresses are the MP01's own, from the `mblock` table its stock LK prints
at every boot (kept in the `expdb` partition; Android's
`/proc/device-tree/reserved-memory/*/reg` needs root). Every one of LK's
regions lies inside a node here, checked against an unlocked (orange) and a
locked boot: unlocked, LK adds `debug_met_res-ram` at `0x9f670000` and
moves `sspm_ap-shared` from `0x9fd60000` to `0x9f560000`; the nodes cover
both. A missed EMI-MPU-protected region is an
SError at first touch. The DT has no `simple-framebuffer`: U-Boot adds one for
LK's buffer at `0xffa23000`.

`/memory` is a 6 GiB placeholder for the boot chain to overwrite. There is no
`stdout-path`: the phone has no UART, and DC-1 found an early console on a
headerless UART can hang the boot. The console goes to ramoops (built in,
`0x48090000`, the stock layout) and the USB gadget.

How the MP01 boots this kernel (stock LK with a dtbswap-style stub, or an own
U-Boot as on the Q25) is not decided here; it decides `0123`/`0125`
(power-off through the PMIC, kept: same vendor BL31), `0105` (SPM/DPM
firmware), the framebuffer handoff (`0040`, `0046`, `0083`) and the modem.

## Out-of-tree modules

`linux-zinwa-q25/modules/build.sh` takes `BOARD=mp01` and builds, against the
MP01 tree: WMT/BTIF/connadp, `wlan_drv_gen4m_6789`, the STP Bluetooth bridge,
the CONNSYS GNSS driver, FM, the five ECCCI modules, and the audio set (MT6358
codec, MT6789 AFE, accdet, and the Q25 machine driver, which binds only to
`zinwa,q25-mt6366-sound`). Not built: the Q25 MD1 owner (it hardcodes the
Q25's `0xdc000000` image base), haptics glue (the MP01 uses upstream
`regulator-haptic`), cameras and the camera overlay.

Their DT nodes use vendor compatibles, so they are overlays in the kernel
package, not board DT: `mp01-connsys.dtso` (CONNSYS, Wi-Fi, BTIF, GNSS with
the MP01's L1 and L5 LNAs) is merged at build time into
`mt6789-minimal-mp01-vendor.dtb`; `mp01-modem.dtso` (ECCCI, as wired on the
Q25 minus `q25-md1-owner`) is built and shipped as `mp01-modem.dtbo` but not
merged.

Board-specific inputs these need, none of which may come from the Q25:

- CONNSYS ROM patches and Wi-Fi/BT firmware for the MP01's A-die (MT6631 or
  MT6635, unknown), its NVRAM/MAC. The CONSYS EMI at `0x7e000000` is the stock
  LK address on both other boards; confirm with the map above.
- the MD1 image, NV data and the four MD regions from the MP01's own LK. On
  the stock chain LK loads MD1 itself; who powers it afterwards (the Q25's
  owner module did both because its U-Boot replaced LK) is the open question
  before the modem overlay is used.
- a sound card: the MT6366 routes look like the Q25's (analog OCA72390 on
  LINEOUT, `spk-i2s` is for the RT5512 that is not fitted), but the card needs
  an MP01 compatible and the amplifier's MP01 register lists from the vendor
  `oca72xxx` configuration.

## Not described, or untested

- MT6375 charger, Type-C/PD and ADC: no upstream driver or binding (the DC-1
  tree has a board-tuned one for its pack, not usable here). Charging runs on
  what LK leaves programmed; there is no charger `power_supply`, so USB stays
  device-mode with no VBUS-based suspend, and the gauge has no charger to
  follow. ETA6937 (no stock driver loaded, likely not fitted) and the CPS4021
  wireless receiver are left out.
- Fuel gauge: driver and shunt are the Q25's; the battery node uses the
  factory 25 C profile (3112 mAh, 4.465 V CV, 70 mOhm) for an unidentified
  pack.
- OCA72390 amplifier, RT5512, LM3643/OCP81375 flash, cameras, fingerprint,
  microSD, the FocalTech capacitive keys below the panel (the vendor reports
  them as touches at y=1000; edt-ft5x06 has no key support).
- The touchscreen compatible is `focaltech,ft5426` for an FT5446U (same
  register protocol); the driver reads the chip at probe. It reports in the
  panel's scanout frame (`touchscreen-inverted-x`, then
  `touchscreen-swapped-x-y`), so a compositor that turns the display by the
  panel orientation turns touch with it.
- `0111`/`0112` replay the Q25 LK's display SMI setup and `0122` keeps system
  idle off while the CRTC runs; both need checking against the MP01's LK and
  an e-paper refresh policy that may stop the CRTC.
- Found, not changed: `mt6789.dtsi` puts the UFS PHY at `0x01fa0000` under a
  `ufs-phy@11fa0000` node name (dtc warns); the Q25 and the DC-1 boot UFS with
  it. Changing the address changes what the PHY driver programs on the boot
  storage, so it needs a hardware test first.

## Prior art compared

- Daylight DC-1 (`denysvitali/dc-1-linux-kernel`, branch `jagar`, the same
  MT6789 base): its reserved-memory map and dtbswap boot are what this DT's
  memory handling follows. It has its own MT6789 MIPI TX driver
  (`phy-mtk-mipi-dsi-mt6789.c`, which clears `DSI_SW_CTL_EN` at power-on; the
  Q25 and this board use the MT8183 path), an MT6375 TCPCI backend for TCPM
  (`tcpci_mt6375.c`: plain TCPCI at the secondary address 0x4e plus a PHY
  patch) and a read-mostly MT6375 charger tuned to its pack. The TCPCI driver
  is the best starting point for the MP01's USB-C; the charger is not.
- postmarketOS `ellyq/mtk_g99-mainline` is this tree's base.
- Minimal's `mp01-kernel` (`Z10.dts`, `panel-z10-eink-*`, `aw9523b.c`) and
  LuneOS's `knowledge/device-mp01.md` are the sources of the pin, panel,
  keyboard and fitted-parts facts above.

## Checks done

- The full series (62 shared + 15 MP01, the e-paper patches included) applies
  with the APKBUILD's own loop to a fresh extract.
- `mt6789-minimal-mp01.dtb` builds with `W=1` with one warning, the UFS PHY
  above; the vicky and Q25 DTBs still build in this tree.
- `dt-validate` (dtschema 2026.9) against this tree's bindings plus the panel
  series' `minimal,z10-eink` and DSI `data-lanes` bindings: every board node
  passes. What remains is shared: MT6789 compatibles missing from the I2C,
  SPI, UART, MMC, MUSB, T-PHY, SCP, timer, GPU and MIPI TX bindings,
  `0110`'s IOMMU-less `mediatek,larb`, the dtsi's RDMA FIFO size, and
  `system-power-controller` on the MT6358 node (`0123`).
- Both overlays build and merge onto the board DTB with `fdtoverlay`.
- The APKBUILD's `prepare`, `build`, `package` and `_modules`, run outside
  abuild against this checkout (clang 22, aarch64 host): `Image`,
  `vmlinuz.efi`, all in-tree modules and the 18 out-of-tree ones build, every
  module's vermagic is `7.0.0-mp01`, and the module count matches the list.
- The package builds under abuild with `scripts/qemu/lib/build-aport-apk.sh`
  (Alpine edge container): `linux-minimal-mp01` and `mp01-kernel-modules`
  7.0.0-r0, with `panel-minimal-z10-eink.ko`, and a board DTB carrying
  `data-lanes = <1 2 4 3>` and `rotation = <270>`. `../READY.md` lists the
  hashes.

## First boot, in order

1. Reserved memory: checked against the stock LK's map (above). Decide the
   boot path; keep slot A on stock.
2. Boot to the initramfs with UFS read-only and the USB gadget (ACM/NCM) as
   the console; ramoops for anything earlier. Check `pstore` after a failed
   boot from stock Android (same ramoops layout).
3. Display: `mediatek-drm` with the panel driver and lane map; the e-paper
   keeps LK's image until then.
4. Input: keypad and PMIC keys, AW9523 keyboard (confirm the row/column map by
   pressing every key with `evtest`), touch, frontlight.
5. Power: gauge readings against stock; charging stays on LK's settings until
   an MT6375 driver exists.
6. CONNSYS with MP01 firmware, then the modem once the MD1 handoff is
   understood, then audio.
