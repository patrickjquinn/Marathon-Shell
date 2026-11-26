# MP01 (Z10) vs Zinwa Q25: hardware from the device trees

Sources:

- **Q25**: the final `mt8781-zinwa-q25.dts` and `mt6789.dtsi`, made by applying every DTS hunk of the 138-patch series to base 978b8b67 in a scratch tree. The runtime camera overlay `modules/camera/q25-camera.dtso` is used for cameras.
- **MP01**: factory `dt/base0.dts` (SoC base, built for project Z10) and `dt/dtbo0.dts` (Z10 overlay, 44 fragments). Where noted, the stock module list and input dump, and the property-name-only live `/proc/device-tree` listing.

GPIO numbers are decimal. **(inferred)** marks a conclusion that is not stated in a DT.

## SoC, memory, reserved memory

| Item | Q25 | MP01 |
|---|---|---|
| SoC | MT6789/MT8781, `zinwa,q25`, `mediatek,mt8781`, `mediatek,mt6789` | MT6789 (`mediatek,MT6789`), `ro.product.board=Z10` |
| CPU idle | 0097/0105: cpu-off 0x10001/0x10002, cluster-off 0x1010101/0x1010102, mcusys 0x1010701, system 0x1010f01/02/03 | Identical PSCI parameters and latencies, plus s2idle 0x1011f01 |
| /memory | None in DT (EFI memory map from U-Boot) | Placeholder `0x40000000 + 1 GiB`, filled in by LK |
| Boot image | U-Boot/UEFI chain (Q25 `lk_a`) | vendor_boot header v4, A/B (`_a`), dynamic partitions |
| Storage | UFS @11270000, VCC = VEMC (0042) | UFS @11270000 is the boot device (`ro.boot.boot_devices`), VCC = VEMC, clocks include unipro_tick and ufs_aes (matches 0104). An eMMC node @11230000 is also in the base, sharing VEMC |
| SD | No mmc node enabled in the final DTS | mmc@11240000, 4-bit, card detect on GPIO7 |

### Reserved memory

The Q25 DTS describes these regions statically. The MP01 factory static DT has none apart from a reusable 256 MiB `ssmr` CMA. Its live DT lists LK-injected `mblock-N-*` nodes by name only; the inventory has no values.

| Region | Q25 address / size | MP01 live node |
|---|---|---|
| BL31 | 0x48200000 / 0x200000 | mblock-14-BL31-reserved |
| crypto_hw | 0x48401000 / 0x1000 | mblock-19-crypto_hw |
| aee_lk | 0x50700000 / 0x800000 | mblock-12-aee_lk |
| TEE | 0x70000000 / 0x4600000 | mblock-18-tee-reserved |
| tee-secmem | 0x7ea00000 / 0x800000 (0095; Q25 mblock 17) | mblock-17-tee-secmem (same index) |
| CONSYS EMI | 0x7e000000 / 0x500000 (0007); `emi-addr` matches | mblock-31-consys_emi_reserved (factory consys node has `emi-addr = 0`, filled by LK) |
| q25-held | 0x7d000000 / 0x500000 (old vicky CONSYS) | n/a |
| MCUPM | 0x7feb0000 / 0x100000 | mblock-16-MCUPM-reserved |
| ap_md_c_smem | 0x8c000000 / 0x16a0000 | mblock-29-ap_md_c_smem |
| ap_md_nc_smem | 0x8e000000 / 0xe10000 (0011) | mblock-28-ap_md_nc_smem |
| scp_share | 0x8f000000 / 0x5a0000 | mblock-22-reserve-memory-scp_share |
| sspm_ap | 0x9f560000 / 0x110000 | mblock-30-sspm_ap-shared |
| SSPM | 0x9fe70000 / 0x180000 | mblock-15-SSPM-reserved |
| Wi-Fi DMA pool | 0xbf000000 / 0x600000 | mblock-32-shared-dma-pool_wifi-reserve-memory_dma |
| ccci_tag | 0xbf9f0000 / 0x10000 | mblock-23-ccci_tag_mem |
| SCP | 0xbfa00000 / 0x400000 | mblock-21-SCP-reserved |
| MD1 (4 regions) | 0xdc000000/0x1490000, 0xddc00000/0x430000, 0xde800000/0x2b10000, 0xe3200000/0xe00000 | mblock-24..27-md_mem_usage |
| dfdmcu | 0xfd000000 / 0x100000 | mblock-20-platform-debug_dfdmcu_dump |
| framebuffer | 0xfe0d0000 / 0x1f2f000; simplefb at 0xff97c000, 720x720, 736-px stride | mblock-13-framebuffer |
| Camera pool | 256 MiB dynamic, below 4 GiB (0010) | n/a (stock uses ssmr CMA) |
| Only on MP01 | - | dramc-rk0/rk1, emi_mbist_buf, **gz, unmap2, gz-log (GenieZone)**, log_store, atf-log, aee_debug_kinfo, pstore, minirdump |

**Conclusion.** The two boards share the MediaTek LK mblock scheme, down to tee-secmem being mblock 17 on both. Absolute addresses depend on LK and DRAM size and must be read on the MP01 (see open questions). The MP01 also reserves GenieZone regions that the Q25 DTS does not describe; stock loads the `gz_*` modules.

## PMIC and regulators

| Item | Q25 | MP01 |
|---|---|---|
| Main PMIC | MT6366 (`mediatek,mt6358` MFD) on pwrap, IRQ GPIO137, `system-power-controller` (0124) | MT6366 on pwrap, IRQ GPIO137 (0x89) |
| PMIC keys | power = KEY_POWER, "home" = KEY_VOLUMEUP | power + volume up (stock `mtk-pmic-keys`) |
| Extra PMICs | none | **MT6375** (i2c5 0x34: charger, TCPC, ADC, OTG regulator; IRQ GPIO4); **RT5133** 8-LDO (i2c5 0x18; IRQ GPIO5, enable GPIO188; likely camera rails **(inferred)**) |
| vgpu / vsram_gpu | 675-900 / 850-1000 mV, coupled 100 mV; MFG0 = vsram_gpu, MFG1 = vgpu (0084/0106) | Factory leaves both at 0.5-1.29 V; same SoC, so the Q25 constraints should apply **(inferred)** |
| VEMC | UFS VCC (0042) | UFS VCC and eMMC vmmc |
| vbif28 | always-on (0041) | always-on in the factory DT |
| vsim1 / vpa | always-on for the modem (0043) | Not always-on (vendor modem driver handles them) |
| vaud28 | Codec AVDD (0096) | Codec `reg_vaud28-supply`, always-on |
| vcn18/28/33 | CONNSYS supplies | CONNSYS rails (vcn28 always-on) |
| vibr | Defined, used by `q25-haptic` | `regulator_vibrator` loaded on stock (presumably vibr) **(inferred)** |
| Clock buffer | PMIC XO buffers as clock provider (0069-0071); XO_NFC feeds the ST21NFCD | XO_SOC/WCN/NFC/CEL/EXT supported; XO_NFC under SW control (`xo-buf-allow-control`) |

## Charging, battery, USB

| Item | Q25 | MP01 |
|---|---|---|
| Charger | UPM6922 (bq25601 clone) on i2c5 0x6b, INT GPIO37; 4.6 V VINDPM, 3 A input | **MT6375** primary (i2c5 0x34). ETA6937 "secondary_chg" at i2c5 0x6b (EN GPIO156, INT GPIO14), but no matching stock module is loaded. **CPS4021 wireless** at i2c5 0x30 (INT GPIO13, OVP_EN GPIO151, MOD0 GPIO150, MOD1 GPIO37, OVP_FLAG GPIO153) |
| Gauge | MT6366 coulomb counter (`mediatek,mt6358-gauge`), shunt 990 uOhm, Rint 80 mOhm, 2939 mAh, CV 4.44 V | `mediatek,mt6358-gauge` (stock `mt6358_battery`). Factory R_FG_VALUE 5 mOhm, CAR_TUNE 101, FG_METER_RESISTANCE 70 mOhm, battery_cv 4.465 V, 5-temperature profiles |
| USB | MUSB peripheral only, `power-supplies = <&charger>` (0113/0114) | MUSB (`musb_hdrc`) + `phy_mtk_tphy`, USB-C TCPC on the MT6375 with DRP/PD/DP-altmode data in the DT |

## Display

| Item | Q25 | MP01 |
|---|---|---|
| DSI host / PHY | dsi0 @14013000 (SPI 301), mipi_tx0 @11f60000 | Same addresses and IRQ (0x12d = 301); vendor compatibles |
| Panel | `zinwa,q20-hd720`, 720x720 video mode, **2 lanes**, 652 Mbit/s HS (0048/0052), about 70.93 Hz | `z10,eink,vdo` on dsi0, video mode (from the name). 800x600 class: touch reports 600x800. **Lane count not in the DT**. **Lane 2/3 swap per the handoff (vendor panel driver), not in the DT**. Mainline mtk_dsi/mipi-tx has no swap support |
| Panel power | Bias OCP2131 (i2c7 0x3e) enabled by GPIO84; panel enable GPIO156; reset GPIO85 (active low) | pm-enable **GPIO12**, reset **GPIO85**, v12_en GPIO158, v33_en GPIO159, v18_en GPIO43; `lcm_led_en` pin states also on GPIO12 |
| Controller side-channel | none | **Pango e-ink CPLD** at i2c7 0x4b (`mediatek,I2C_LCD_BIAS`, 1 MHz); stock `panel_z10_eink_i2c` |
| Bias / gate IC | OCP2131 (TPS65132-compatible) | `gate_ic@11` on i2c6 (power GPIO12); stock loads `rt4831a_drv`, so probably RT4831A **(inferred)** |
| Brightness | Bias voltage, 21 levels (panel driver) | `mtk_leds` PWM "lcd-backlight" on disp_pwm (frontlight), plus `pwm_warmlight` and `mtk_irtx_pwm` (warm light per the handoff) |
| TE | not used | DSI TE eint on GPIO83 (func 1), enabled |
| DDP path | OVL0→RDMA0→COLOR0→CCORR0→AAL0→GAMMA0→POSTMASK0→DITHER0→DSI0; SMI larb0/larb1 untranslated (0110-0112) | Same component addresses (aliases). Vendor runs the display through the M4U (`mt6789-disp-iommu` @14016000). Mainline Q25 runs it without the IOMMU |

## I2C bus and address map

| Bus (base) | Q25 | MP01 |
|---|---|---|
| i2c0 @11e00000 | 0x67 Synaptics S2716B touch (IRQ GPIO9, reset GPIO152) | 0x38 FocalTech touch (IRQ GPIO9, reset GPIO152; 3 virtual keys) |
| i2c1 @11e01000 | 0x30 MMC5603 magnetometer (SCP pins 132/133 handed to the AP) | No AP device (sensors on the SCP) |
| i2c2 @11eb0000 | - | 0x20 main camera (S5K3P3SP), 0x51 EEPROM, AF at 0x72 / 0x0d / 0x0c |
| i2c3 @11015000 | 0x08 ST21NFCD, 0x58 OCA72390 amp | 0x28 NXP NFC (IRQ GPIO1, VEN GPIO12, FW_DL GPIO3) |
| i2c4 @11eb1000 | 0x1a IMX111 front (overlay) | 0x7c sub camera (BF2553L), 0x51 EEPROM |
| i2c5 @11017000 | 0x6b UPM6922 charger, 0x2f WL2868C camera PMIC (overlay) | 0x34 MT6375, 0x18 RT5133, 0x30 CPS4021, 0x6b ETA6937 |
| i2c6 @1101a000 | 0x1f RP2040 keyboard (IRQ GPIO12) | 0x11 gate IC, 0x58 OCA72xxx amp, 0x5b AW9523B keyboard (IRQ GPIO5, reset GPIO35), 0x5c RT5512 amp, 0x63 LM3643 flash |
| i2c7 @11f00000 | 0x3e OCP2131 panel bias | 0x4b Pango e-ink CPLD (1 MHz) |
| i2c8 @11eb2000 | 0x10 S5KJN1 rear, 0x0c DW9714 (overlay) | 0x10 camera main_two, 0x50 EEPROM, 0x64 OCP81375 strobe |
| i2c9 @11eb3000 | 0x2b HX32062SE ALS/PS (SCP pins 148/149) | No AP device |
| spi2 | ICM-42607-P IMU (SCP pins 38-41) | No IMU in the AP DT. The fingerprint `focaltech_fp` (IRQ GPIO8, reset GPIO10) is a top-level node; its transport is not given in the DT |

Both boards register the I2C controllers with the same base addresses. The MP01 factory DT uses the `mediatek,mt6983-i2c` compatible, while mainline MT6789 uses its own. Both sets of clocks come from imp_iic_wrap, which 0032/0119 fix.

## Other peripherals

| Item | Q25 | MP01 |
|---|---|---|
| Keyboard | RP2040 BBQ20 protocol, LED, trackpad (bbqx0kbd) | AW9523B 6x6 matrix (input mask 0xfc00, output mask 0x00fc), keyboard backlight plus LEDs idx 1/8/9. Stock reports ~60 keycodes |
| SoC keypad | KPCOL0/1 (pins 66/67, R1R0 pull): volume down + assistant | Same pins in mode 1; stock `mtk-kpd` reports KEY_VOLUMEDOWN + 0xfc |
| NFC | ST21NFCD + XO_NFC | NXP (`nxp,nxpnfc`) |
| Audio | MT6366 codec + MT6789 AFE + OCA72390 (i2c3) | MT6366 codec (dmic-mode 0, mic-type 1) + AFE; OCA72xxx (i2c6 0x58) and RT5512 (i2c6 0x5c) amps; stock card `mt6789-mt6366`, `spk-i2s = <3 0>` |
| GNSS | CONNSYS, L1 LNA GPIO25 func 2 | CONNSYS, L1 LNA GPIO25 func 2, L5 LNA GPIO26 func 2 |
| CONNSYS | @18002000, SPI 410/111/411, CONN domain, TOPRGU reset | Same reg list and IRQs; `emi-addr` from LK |
| Modem | ECCCI nodes + `q25-md1-owner` (0011) | ECCCI `mddriver` (`md_sub_version` 1, vmodem/vsram supplies), CCIF, DPMAIF, `ccci_scp`, `md_auxadc`; SIM1 hot-plug GPIO23 |
| Cameras | IMX111 + S5KJN1 + WL2868C via runtime overlay | 3 sensors (main/sub/main_two) + EEPROMs; RT5133 rails **(inferred)** |
| Flash | SGM3140 on GPIO154/155 | LM3643 (i2c6 0x63), OCP81375 (i2c8 0x64), GPIO0 flashlight pin states |
| Wireless charging | none | CPS4021 |
| Fingerprint | none | FocalTech FP |

## GPIO conflicts and overlaps

**Within the MP01 DT:**

- **GPIO12** has four claimants: the panel `pm-enable-gpios`, the mtkfb `lcm_led_en1/en0` pin states, NFC `nxp,nxpnfc-ven`, and `gate_ic@11` `gate-power-gpios`. This is confirmed in the dtbo and base. A mainline DT can give it to only one gpiod consumer, so it either models a shared enable rail as a fixed regulator or follows the real wiring.
- **GPIO5**: AW9523B `irq-gpio` (dtbo) and RT5133 `interrupts-extended` (base). Confirmed in the DT; population and wiring unknown.
- **GPIO20**: cam2 reset, and also the `vcamafvdd` states of cam0 and cam1. **GPIO46**: vcamio of both cam0 and cam1. These are camera-only and probably shared rails **(inferred)**.

**Between the Q25 and MP01**, if Q25 DT hunks were copied across:

| GPIO | Q25 use | MP01 use |
|---|---|---|
| 1 | NFC IRQ | NFC IRQ (same) |
| 9 / 152 | Touch IRQ / reset | Touch IRQ / reset (same) |
| 12 | Keyboard IRQ | Panel PM / LCM LED / NFC VEN / gate IC |
| 25 | GNSS L1 LNA | GNSS L1 LNA (same) |
| 37 | Charger INT | Wireless-charger MOD1 |
| 66 / 67 | Keypad columns | Keypad columns (same) |
| 84 | Panel bias enable | not referenced in the DT |
| 85 | Panel reset | Panel reset (same) |
| 137 | PMIC IRQ | PMIC IRQ (same) |
| 150 | NFC enable | Wireless-charger MOD0 |
| 154 / 155 | Flash | not referenced in the DT |
| 156 | Panel enable | ETA6937 enable |
| 157 / 158 / 159 | Keyboard supplies | -, panel v12_en, panel v33_en |

The identical touch, NFC IRQ, panel reset, LNA, keypad and PMIC pins suggest both boards derive from the same MediaTek reference schematic **(inferred)**. Every pin that differs is one Q25 hunk that would drive an MP01 power rail or charger mode pin, so no Q25 board DTS hunk should be copied without checking this table.
