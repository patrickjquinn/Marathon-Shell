# MT6789 common vs board split: linux-zinwa-q25 audit

Inputs: `packaging/packages/linux-zinwa-q25` at pkgrel 61 (base `ellyq/mtk_g99-mainline` 978b8b67, **138** numbered patches, not the 136 the handoff counts), plus the Minimal Phone MP01 (Z10) factory `base0.dts`/`dtbo0.dts`, its stock lsmod and its input dump. Each patch was classified from its diff. The per-patch table is `patch-audit.csv`.

How the patches were checked: all DTS, DRM and SMI hunks were applied in order to a scratch copy of the base, so the Q25 board DTS below is the final one. The proposed common subset (62 patches, with the Q25 board-DTS hunks excluded) was then `git apply`-ed in numeric order to a scratch copy of the touched base files, and every patch applied cleanly. Nothing was built.

Marking: **(inferred)** means not confirmed from a diff or DT, and **(handoff)** means the claim comes from the handoff document and is not visible in the DTs.

## 1. Counts per class

| Class | Count | Patches |
|---|---|---|
| soc-common | 51 | 0001 0003 0004 0009 0026 0027 0032-0037 0044 0045 0047 0048 0063-0067 0069-0071 0077 0078 0081 0082 0085 0086 0097-0104 0107-0110 0113 0115 0117-0119 0126 0128 0129 0135 |
| soc-common-with-q25-assumption | 10 | 0040 0046 0076 0083 0105 0111 0112 0122 0123 0125 |
| q25-board | 37 | 0005-0008 0010 0028 0029 0038 0039 0041-0043 0049 0051-0053 0056 0059 0061 0062 0068 0075 0079 0084 0087 0088 0090 0091 0094-0096 0106 0114 0116 0124 0127 0132 |
| device-class-optional | 38 | 0002 0012-0025 0030 0031 0050 0054 0055 0057 0058 0060 0072-0074 0080 0089 0092 0093 0120 0121 0130 0131 0133 0134 0136 0138 |
| donor-compat | 1 | 0137 |
| unsafe-to-generalize | 1 | 0011 |

Where this differs from the handoff's first guess (sections 3.2 and 5):

- **0004, 0009, 0063, 0064-0067, 0069-0071, 0123, 0125, 0128, 0129** are MT6358/MT6366 PMIC code, not SoC IP. Both boards carry the MT6366, so they go in common. A future MT6789 board with a different PMIC would not use them.
- **0040, 0119** touch only the Q25 board DTS, but their content is generic. 0119 is a pure SoC clock-tree setting and should move to `mt6789.dtsi`. 0040 belongs in every board's framebuffer node whose bootloader scans out.
- **0110** is mixed. Its dtsi hunk (`mediatek,larb` on ovl0/rdma0) is common, and its board hunk only enables `smi_common_disp`/larb0/larb1, which every no-IOMMU board needs.
- **0111/0112** are not just SoC data. They replay register values captured from the Q25 bootloader and drop the bus-1/IOMMU routing for all MT6789 users of `mtk-smi`.
- **0122** (CRTC latency QoS) and **0135** (I2C latency QoS) apply to every MediaTek SoC, not only MT6789. They are fine in a MT6789 series but need gating before going upstream.
- **0061** is a driver patch, but it carries Q25 amplifier register lists under `zinwa,q25-amp`, so it is classed q25-board. Only the chip-ID acceptance is reusable.
- **0057/0058** (BBQ keyboard) are a generic BBQ10/BBQ20 driver, but the binding is named `zinwa,q25-keyboard`.
- **0011** is the only unsafe-to-generalize patch. It ties ECCCI to `q25-md1-owner`, whose module hardcodes the Q25 MD image base (`SA_IMG_BASE 0xdc000000`) and does LK's modem-load job because the Q25 boots through U-Boot. Its phandles are also pinned to 0x90/0x91.
- **0005** is board DTS, but it carries a reserved-memory map whose comment calls it "SoC-level and not board-specific". It is not: 0095 had to move `tee_sec`, and CONSYS EMI moved in 0007. Never lift it into a common dtsi.

What each soc-common-with-q25-assumption patch assumes:

| Patch | Assumption | Guarded? |
|---|---|---|
| 0040 | LK scans out a logo through OVL0..DSI0, so simpledrm must hold the DISP domain and 13 MM clocks | Board DT only |
| 0046 | LK left the DSI engine running in video mode | Unconditional, but benign on an idle engine |
| 0083 | LK left the DSI link streaming (lanes configured, clock lane in HS) | **Yes**: only when `DSI_TXRX_CTRL != 0` |
| 0076 | The bootloader started the SCP firmware and nothing in Linux owns `scp_sel` | No: clock is always critical (costs power if SCP is off) |
| 0105 | The bootloader loaded the SPM and DPM firmware (Q25 U-Boot `0006`) | Firmware falls back to cluster-off, per the commit |
| 0111/0112 | LK programs the display SMI the way the Q25 LK did, and the display runs untranslated (no M4U) | No |
| 0122 | Under SPM firmware, the "dram" idle constraint glitches a scanning panel | No: applies to all mediatek CRTCs |
| 0123 | Vendor BL31 SYSTEM_OFF does not drop PWRHOLD | Yes: `system-power-controller` in DT |
| 0125 | No LK in the boot chain to clear the STRUP_CON4 latches | Yes: `system-power-controller`. Repeating LK's clear is presumably harmless **(inferred)** |

## 2. Proposed common series order

The common series is the 62 soc-common, soc-common-with-q25-assumption and donor-compat patches in their **existing numeric order**. That order already applies cleanly once the board-DTS hunks are dropped (verified with `git apply`), and keeping it keeps the textual dependencies intact: 0046 → 0047 → 0048 → 0083 → 0108 on `mtk_dsi.c`, 0082 → 0108 → 0122 on `mtk_crtc.c`, and 0066 → 0070 → 0123 → 0125 on `mt6397-core.c`. Grouped for review:

1. **Hygiene**: 0003 0026
2. **Clocks**: 0032, 0045, 0076*, 0098, 0099, 0100. 0119 is moved into `mt6789.dtsi` as `&topckgen` assigned-clocks.
3. **Power domains and reset**: 0033 0034 0035 0036 0037
4. **PMIC (MT6358/MT6366)**: 0004 0009 0063 0064 0065 0066 0067 0128 0129 0069 0070 0071 0123* 0125*
5. **UFS**: 0101 0102 0103 0104
6. **SoC dtsi**: 0085 0086 0097 0105* 0118, plus the 0110 dtsi hunk
7. **Display**: 0044 0047 0001 0077 0078 0081 0082 0046* 0048 0083* 0111* 0112* 0115 0107 0108 0109 0122*
8. **Buses, USB, idle**: 0117 0135 0113 0126
9. **CONNSYS GNSS binding**: 0027
10. **Separate "generic/donor" bucket** (not SoC, but carry for now): 0137 (donor-compat), 0120 (PSI policy), and 0012-0021 (ICM-42607 backports, droppable once the base passes v7.3).

`*` marks the assumption patches. Before sharing, each should either stay guarded on observable state (as 0083 is) or carry a board opt-in DT property.

0040's framebuffer `power-domains`/`clocks` list should become a documented snippet that every board DTS copies, not a common patch. The 0110 board hunk (enable `smi_common_disp`, `larb0`, `larb1`) is likewise a per-board line.

**Missing from the common series and needed by the MP01** (not in any Q25 patch):

- DSI lane swap / lane mapping in `mtk_dsi` or `phy-mtk-mipi-dsi`. The base tree has no swap support (checked; the only PHY DT knob is `drive-strength-microamp`).
- A mainline driver for the MT6375 charger, TCPC and ADC. Its absence from mainline is **inferred**. Without it, 0113's VBUS-based USB suspend and 0067's end-of-charge anchoring have no power_supply to follow.

## 3. Q25 patches the MP01 needs, with the rewrite each one needs

| Area | Q25 patches | MP01 rewrite |
|---|---|---|
| Display / DSI | 0001 0077 0078 0081 0082 0115 0107 0108 0109 0110 0118 (as is). 0046 0083 0040 (if MP01 LK leaves DSI streaming). 0048 (if the e-ink link needs a fixed HS rate). 0111 0112 (if MP01 LK programs the same SMI) | New panel driver for `z10,eink,vdo` plus a safe-read Pango CPLD driver (i2c7 0x4b). Panel power: pm-enable GPIO12, reset GPIO85, v12 GPIO158, v33 GPIO159, v18 GPIO43; TE on GPIO83. Lane count unknown; lane 2/3 swap (handoff) needs a new DSI/PHY patch. The framebuffer node needs MP01's LK fb address and pitch. Frontlight via disp-pwm plus the warm-light PWM, not bias voltage. Check 0108's "no DCS while the pipeline is off" against the Pango sequence. Check 0122 (system idle blocked while the CRTC runs) against an e-ink refresh policy that could stop the CRTC when idle. |
| UFS | 0101-0104 (as is), 0042 (board, same VEMC rail) | Port the 0042 hunk verbatim: MP01 UFS VCC is VEMC and the boot device is `11270000.ufshci`. |
| Clocks / power domains | 0032 0033 0034 0045 0076 0098 0099 0100 0117 0119 0135 0097 0105; GPU: 0039 0084 0106 | GPU supply hunks port verbatim: same MT6366 vgpu/vsram_gpu, same SoC OPPs **(inferred)**. Factory idle-state parameters are identical to 0097/0105, so those are confirmed. |
| PMIC base | 0009 0004 0096 0041 0043 0123/0124 0125 | MT6366 PMIC on the same pwrap, IRQ also GPIO137. Codec node values match (dmic-mode 0, VAUD28). vbif28 is always-on in the factory DT too. Whether MP01 BL31's SYSTEM_OFF works is unknown, so 0124 is optional. |
| MT6358 gauge | 0063 0064-0067 0128 0129 (as is); 0068 0127 (rewrite) | New battery node. The factory gauge config says R_FG_VALUE 5 mOhm and CAR_TUNE 101 (Q25: 1 mOhm, 1.01). It also gives FG_METER_RESISTANCE 70 mOhm and CV 4.465 V (stock reads 4.46 V on a USB charge). OCV has to come from the factory `battery0_profile_t*` tables, and the pack capacity is unconfirmed. `power-supplies` must point at an MT6375 charger power_supply, which has no driver yet. |
| CONNSYS / WMT / GNSS / FM | 0027 0035-0037 (as is); 0007 CONNSYS/BTIF/Wi-Fi nodes, 0038, 0028 (board) | The factory CONSYS reg/irq set is identical to the Q25 node, so the nodes can move to `mt6789.dtsi`. `emi-addr` must come from MP01's LK (`mblock-31-consys_emi_reserved`; the factory static DT has 0). The GNSS L1 LNA is GPIO25 func 2 on both boards, so 0028 ports nearly verbatim; the MP01 also has an L5 LNA on GPIO26. Stock MP01 loads `wmt_drv`, `wlan_drv_gen4m_6789`, `bt_drv_connac1x`, `gps_drv_stp` and `fmradio_drv_mt6631_6635`, which is the same donor family. The A-die (MT6631 vs MT6635) is unknown. |
| CCCI / modem | 0043 (rails); the ECCCI node shapes in 0011; out-of-tree `modules/modem` | Do not reuse `q25-md1-owner` or the 0011 phandle/carve-out hardcoding. MP01 factory `mddriver` adds `md_sub_version=1` and vmodem/vsram supplies. The MD1 image, the four md_mem regions, ap_md_c/nc_smem and ccci_tag addresses all come from MP01's LK. Whether the MP01 boot path keeps LK, which loads MD1 itself on stock, decides whether an owner module is needed at all. |
| Keys | 0085 0086 (as is), 0087 0094 (board) | The MP01 keypad uses the same block and the same KPCOL0/1 pins 66/67. Stock reports KEY_VOLUMEDOWN plus keycode 0xfc, so the 0087/0094 hunks port with a keycode check. |
| USB | 0113 0126 | 0126 as is (same MUSB). 0113 needs an MT6375 power_supply; consider USB-C role switching through the MT6375 TCPC instead of fixed peripheral mode. |
| Amp | 0060, and the chip-ID part of 0061 | MP01 has `ocs,oca72xxx_pa` at **i2c6** 0x58, plus an RT5512 smart amp at 0x5c (loaded on stock). Whether it is an OCA72390 (ID 0x11) and its register list need checking on hardware. |

## 4. Irrelevant to the MP01

- **Q25 panel and bias**: 0049 0050 0051 0052 0053 0080 0088 (and 0008)
- **Q25 keyboard and trackpad**: 0057 0058 0059 0089 0090 0092 0093
- **NFC**: the MP01 chip is NXP (`nxp,nxpnfc` at i2c3 0x28, stock module `nxpnfc_i2c`), not ST. 0072 0073 0074 0075 are irrelevant. 0069-0071 (PMIC clock buffers) stay relevant only if the NXP part runs from XO_NFC.
- **Touch**: MP01 uses FocalTech at i2c0 0x38. 0030 0031 (Synaptics RMI4 reset) are irrelevant.
- **Charger**: MP01 uses MT6375 as primary and ETA6937 as secondary, not BQ256xx. 0002 0121 0130 0131 0132 0114 are irrelevant.
- **Q25 cameras**: 0022 0023 0024 0133 0134 0136 0010 0029. MP01 sensors are S5K3P3SP and BF2553L, plus a third main_two. 0138 (DW9714) is unknown: there is an AF at MP01 i2c2 0x0c.
- **Q25 sensors**: 0054 0055 0056 (HX32062SE), 0025 (MMC5633), 0012-0021 (ICM-42607). The MP01 AP DT has no sensors; stock runs them on the SCP sensorhub, and the parts are unknown.
- **Q25 board one-offs**: 0005 0006 0091 (SGM3140 flash; MP01 uses LM3643/OCP81375 on I2C), 0095, 0116 0079 0124 0127 0062

## 5. Open questions that need hardware

1. **GPIO12.** The Z10 DT gives it to four consumers: the panel `pm-enable-gpios`, the mtkfb `lcm_led_en` pin states, NFC `nxp,nxpnfc-ven`, and `gate_ic@11` `gate-power-gpios` on i2c6 (base DT). Mainline lets only one consumer request a GPIO. A schematic or live trace is needed to tell whether this is one shared enable rail. (On the Q25, GPIO12 is the keyboard IRQ.)
2. **GPIO5.** It is both the AW9523B `irq-gpio` (dtbo) and the RT5133 `interrupts-extended` (base, i2c5 0x18). `rt5133_regulator` is loaded on stock; whether the RT5133 is populated and how the IRQ is wired are unknown.
3. **DSI.** Lane count, the lane 2/3 swap claimed by the handoff (in the vendor panel driver, not the DT), HS rate, video timing, and whether LK leaves the link streaming at handoff. That last point decides whether 0040/0046/0083 are needed.
4. **SMI.** Does MP01's LK program the display SMI to the same values 0111/0112 replay? Dump larb0/larb1/smi_common registers at handoff and compare.
5. **Reserved memory.** The live DT lists the same mblock set as the Q25 stock map (BL31, SSPM, MCUPM, tee-secmem, tee-reserved, SCP, scp_share, ccci_tag, md_mem_usage ×4, ap_md_nc/c_smem, sspm_ap, consys_emi, wifi DMA pool). It also has GenieZone (`gz`, `gz-log`, `unmap2`), `log_store`, `pstore`, `minirdump` and others that the Q25 DTS does not describe. The inventory has only property names, so no addresses or sizes. Needed: `xxd /proc/device-tree/reserved-memory/*/reg` or `/proc/iomem` from stock. Also, if MP01 keeps LK, LK probably injects these mblock nodes into whatever DTB it boots **(inferred)**.
6. **Boot chain.** vendor_boot v4, A/B, dynamic partitions. Will the MP01 boot through stock LK with an Android boot image, or through a U-Boot/EFI chain like the Q25? This decides 0123, 0125, 0105 (SPM/DPM firmware), the MD1 owner, and the framebuffer handoff.
7. **Charger and TCPC.** MT6375 at i2c5 0x34 has no mainline driver **(inferred)**. Is the ETA6937 (i2c5 0x6b) populated? No eta driver shows in stock lsmod. Is the CPS4021 wireless charger populated?
8. **Gauge.** Shunt value (factory says 5 mOhm), pack capacity, OCV profile choice (`ACTIVE_TABLE=6`, multi-temperature), and thermistor pull-up (RBAT_PULL_UP_VOLT 2800 mV).
9. **Amp.** Chip ID of the OCA72xxx at i2c6 0x58 and whether the RT5512 at 0x5c is the real speaker amp. Stock also loads `snd_soc_tfa98xx`.
10. **Pango CPLD.** Register map, and how to guarantee the bring-up driver never takes the vendor's firmware-update path (handoff).
11. **Display power.** Does BL31's SYSTEM_OFF reach the PMIC (0123/0124)? Does the e-ink controller tolerate the DISP domain power-cycling under 0108? And with 0122, are e-ink refresh and idle compatible?
12. **CONNSYS.** A-die part number (MT6631/MT6635), CONSYS EMI address, and Wi-Fi pool address.
