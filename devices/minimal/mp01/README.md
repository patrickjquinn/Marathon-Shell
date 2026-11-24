# Minimal Phone MP01 (board Z10)

MediaTek Helio G99 (MT6789), 4.3-inch e-paper, AW9523B physical keyboard.
Bring-up: everything above the kernel is in the tree; no Marathon kernel
has booted on the phone yet.

Sources: the factory device tree (base and Z10 overlay), the stock
`getprop`, `lsmod` and input dump, the partition table, and
[minimalcompany/mp01-device](https://github.com/minimalcompany/mp01-device)
`ProjectConfig.mk`.

## Hardware

**Untested** means the part is there and the stock system drives it,
but no Marathon kernel has run it. **Not fitted** means the factory DT
declares it but stock loads no driver for it.

| Subsystem | Part | State | Notes |
|---|---|---|---|
| SoC, UFS, PMIC | MT6789, UFS at 11270000, MT6366 | untested | Same addresses, PSCI states and UFS clocks as the Q25 |
| Display | Z10 e-paper on DSI0, Pango CPLD on i2c7 0x4b | untested | `panel-minimal-z10-eink` and the DSI `data-lanes` order (lanes 2/3 crossed) are in `linux-minimal-mp01`. The driver cannot address the CPLD's firmware-update registers |
| Display orientation | panel mounted at 270° | untested | `MTK_LCM_PHYSICAL_ROTATION = 270`, so scanout is 800x600 while the UI is 600x800. The DT's `rotation = <270>` makes the connector's panel orientation "Left Side Up"; fbcon follows it, and so does the shell's compositor (`panel_orientation = "kms"`), which turns the scene and the `wl_output` |
| Frontlight, warm light | white LEDs on `disp_pwm` (backlight `backlight`, capped at the stock 25% duty), warm LEDs on PWM_1 (LED `amber:frontlight`) | both light (user-confirmed); white needed `mp01-0028` before its PWM reached GPIO84; both come up lit at boot | The shell's brightness slider drives the white string; the night light crossfades it into the warm one by its warmth (profile `frontlight_warm`) |
| Touch | FocalTech on i2c0 0x38 (IRQ GPIO9, reset GPIO152) | untested | The controller reads 0–600 x 0–800 upright; the DT (`touchscreen-inverted-x`, `touchscreen-swapped-x-y`) reports it in the 800x600 scanout frame, so it turns with the display and needs no `touch_params`. Stock also has three virtual keys (back, home, switcher) |
| Keyboard | AW9523B 6x6 matrix on i2c6 0x5b | untested | Keymap goes in the DT (`linux,keymap` on `gpio-matrix-keypad` over `pinctrl-aw9523`). `60-mp01-keyboard.rules` marks it as the built-in keyboard. Symbol layer: open question |
| Keyboard light | AW9523B LED pins | untested | One LED device per pin |
| Trackpad | — | not fitted | Stock `ff_key` (arrows, enter) is the fingerprint sensor's navigation |
| Keys | PMIC power and volume up, keypad volume down | untested | Same keypad pins as the Q25 |
| Wi-Fi, Bluetooth, FM | CONNSYS, `wlan_drv_gen4m_6789`, `wmt_drv`, A-die MT6631 | untested | Same drivers, units and firmware as the Q25 (`mp01-kernel-modules`, `mt6789-platform`, `q25-connsys-firmware`) |
| GNSS | CONNSYS GNSS, L1 and L5 LNAs | untested | `q25-gnss-firmware` only knows the Q25's `libmnl.so` (sha256 `c0eba0a2…`); the MP01's is another build (`784eb16e…`) whose MT6789 L1 image offset is not yet found |
| Modem | MD1 over ECCCI, LTE | blocked | `q25-md1-owner` hardcodes the Q25's memory map. The MD1 image is on the phone's own `md1img_a` |
| Audio | MT6366 codec and AFE, OCA72390 PA (i2c6 0x58) | untested | Card `mp01-mt6366` from the Q25's machine driver (`mp01-audio.dtso`); the PA's Music/Off lists come from the phone's `ocs72xxx_cf.bin`. Stock also loads RT5512 and TFA98xx drivers, which bind nothing |
| Headset | MT6358 ACCDET | untested | |
| Charger | MT6375 (i2c5 0x34), USB-C TCPC | blocked | No mainline driver |
| Secondary charger | ETA6937 (i2c5 0x6b) | not fitted | |
| Wireless charging | CPS4021 (i2c5 0x30) | untested | Stock loads `cps_wls_charger` |
| Fuel gauge | MT6366 coulomb counter | untested | Calibration in "Charging" below |
| NFC | NXP PN8x on i2c3 0x28 | untested | Shares GPIO12 with the panel enable and the gate IC |
| Cameras | S5K3P3SP main, BF2553L front | untested | The DT has a third sensor (`main_two`) that `ProjectConfig.mk` doesn't list, so it is probably not fitted |
| Flash | LM3643 (i2c6 0x63), OCP81375 (i2c8 0x64) | untested | |
| Sensors | accelerometer, gyroscope, light, proximity | untested | Behind the SCP, none on the AP |
| Fingerprint | FocalTech FP (IRQ GPIO8, reset GPIO10) | untested | |
| SD card | mmc@11240000, card detect GPIO7 | untested | |

## Shared and board-specific

| Piece | Where | Shared? |
|---|---|---|
| SoC facts, GPU stack, Vulkan driver | `socs/mt6789.toml` | MT6789 |
| CONNSYS (WMT) tool and units, Wi-Fi, Bluetooth, FM, Wi-Fi sleep hook, gen4m options, per-network MAC | `mt6789-platform` | MT6789 |
| Panfrost autosuspend delay, MT6366 codec modules-load | `mt6789-platform` | MT6789 |
| Panfrost Mesa (no client-buffer import into mediatek-drm) | `mesa` aport, pinned by `device-minimal-mp01-marathon` and `q25-gpu-render` | MT6789 |
| CCCI daemons, ModemManager plugin | `q25-modem`, `modemmanager-mtk-ccci` | SoC code, but not reusable until a board-neutral MD1 owner exists |
| Device profile (e-paper, density, DPI) | `devices/minimal/mp01/device.toml` | MP01 |
| deviceinfo, initramfs modules, kernel package | `device-minimal-mp01` | MP01 |
| Display symlink, eglfs config, session, keyboard rule, UCM | `device-minimal-mp01-marathon` | MP01 |
| Kernel, DT, panel, CPLD, keyboard keymap, battery | `linux-minimal-mp01` (separate) | MP01 |
| CONNSYS firmware | `q25-connsys-firmware` | MT6789 with an MT6631 A-die |

The Q25 keeps its old unit names (`q25-connsys.service` and the rest) as
aliases of the `mt6789-*` units.

## Charging

The charge limits go in the board DT's `monitored-battery`, not in a
udev rule. Until the cell is characterised, use these conservative
values from the factory DT:

- `constant-charge-voltage-max-microvolt = <4340000>`: the base DT's JEITA
  CV for 10–45 °C, just under its 4.35 V `battery_cv`. The Z10 overlay
  raises `battery_cv` to 4.465 V, so don't start there.
- `constant-charge-current-max-microamp = <1500000>`: below the MT6375
  node's 2.0 A `ichg` and the overlay's 2.5 A AC current.
- `charge-term-current-microamp = <150000>`: the MT6375's `ieoc`.
- Input limit: 500 mA on a standard USB port (`usb_charger_current`).
- Temperature: stock charges only from 0 °C to 55 °C (resuming at 6 °C
  and 50 °C), with CV 4.24 V from 0 to 10 °C and above 45 °C.

None of the Q25's battery values apply.

## Bring-up checklist

1. [ ] Unlock: the inventoried phone reports `vbmeta.device_state = locked`.
   Find an unlock that keeps `md1img`, `nvdata`, `nvram` and `proinfo`.
   Back up every partition first.
2. [ ] Boot chain: the stock LK loads a U-Boot from `boot_b` while slot
   `_a` still boots stock (FLASHING.md; U-Boot itself has run). Prove it
   starts systemd-boot and a Marathon kernel from userdata.
3. [ ] Kernel: `linux-minimal-mp01` (release 7.0.0-mp01) boots to a USB
   shell. Its modules carry that vermagic, never the Q25's.
4. [ ] `scripts/build-minimal-mp01-image.sh` builds, and a composer turns
   its output into the userdata image `scripts/flash/flash-minimal-mp01.sh`
   writes.
5. [ ] Display: DSI link with the lane swap fixed in the host or PHY,
   `mediatek-drm` scanout, `/dev/dri/mp01-display`, read-only CPLD
   control (no firmware writes). Then refresh modes and clear.
6. [ ] Orientation: a portrait shell on the landscape scanout.
7. [ ] Keyboard keymap in the DT, touch and frontlight. Keyboard
   symbols in an XKB layout.
8. [ ] Wi-Fi, Bluetooth and FM through `mt6789-platform` with the Q25's
   CONNSYS firmware.
9. [ ] Charger and gauge with the limits above. Doze, wake and suspend.
10. [ ] Audio: card `mp01-mt6366` plays through the speaker; mic and headset.
11. [ ] Modem: an MD1 owner for the MP01's memory map. Then reuse the CCCI
    stack.
12. [ ] Move `status` on in `device.toml`.

## Open questions

- **Base rotation.** Settled: the compositor follows the connector's DRM
  panel orientation (DT `rotation = <270>`), behind the profile's
  `panel_orientation = "kms"`, and touch reports in the scanout frame.
  Untested on the phone: if the UI comes up upside down, the DT's rotation
  is 90 and the touch inversion moves to y; nothing in the shell changes.
- **E-paper refresh policy.** `DISPLAY_TECHNOLOGY=epaper` only reduces
  motion. A refresh-mode key needs a consumer first: an e-paper service
  or compositor hook, which doesn't exist yet.
- **CONNSYS firmware.** Settled: the Q25's. The MP01's `connsys_*`
  partitions are empty and its firmware is in `vendor`, as on the Q25.
  Stock reports the A-die as `vendor.connsys.adie.chipid = 0x6631` and the
  firmware `t-neptune-main-soc2_2-2118-MOET_SOC2_2_E1_MT6631_ASIC_MINIROM`,
  the Q25's branch and chip; its `WMT_SOC.cfg`, `fm_cust.cfg` and FM
  patches are byte-identical to the Q25's, and only its RAM code is a
  later build (20250320 against 20231117). `q25-connsys-firmware` is the
  set already proven with these donor drivers. If it misbehaves here, the
  MP01's own files are the fallback (copied out of its `vendor_a`, kept
  outside the tree).
- **Keyboard symbols.** Stock's driver emits Sun keycodes (`KEY_STOP` to
  `KEY_CUT`, F9–F12) for a symbol layer. The printed legends are needed
  for an XKB layout.
