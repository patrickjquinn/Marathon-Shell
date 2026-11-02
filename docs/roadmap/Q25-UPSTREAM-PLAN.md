# Q25 upstream plan

Status: plan, 2026-11-02. Nothing here is built. It is the list CODING_RULES H1/H2 point to:
every Q25 hardware workaround, why it exists, what replaces it upstream, and in what order.

## Why

The MT6789 mainline porters reviewed the Q25 kernel work. Jami Kettunen (Deathmist):

> it needs more userspace hacks than the android kernel and I'm afraid it's never going to meet
> upstream quality standards if the hacks keep piling on; it's in a weird halfway point between
> slowly more outdated original kernel and proper latest upstream base, but there's the twist of
> weird userspace hacks

The evidence agrees. On the phone today (7.0.0-q25-cfi-test, booted 2026-11-01):

- `/proc/sys/kernel/tainted` is 4608 (out-of-tree module + a kernel warning); 99 of 115 loaded
  modules are out-of-tree.
- The packages ship 118 out-of-tree modules: 110 in `q25-kernel-modules`, 5 in `q25-modem`, 3 in
  `q25-gpu-render`. Of those, 84 are mainline code built outside the kernel only because the
  kernel config leaves them out (or ships them privately); 12 are Marathon shims that do a missing
  driver's job; 7 are Marathon drivers for real devices; 5 are ports of out-of-tree drivers; 10 are
  MediaTek vendor drivers.
- Thirteen boot services and scripts poke hardware from userspace, the command line carries a driver
  blacklist and three `*_ignore_unused` flags, and CPU0 is taken offline at every boot.
- Mainline Linux (v7.4-rc1, `6628e7d4c6b2`, 2026-11-01) has no MT6789 support at all. Everything
  sits on ellyq's v7.0 fork, which has not moved since June.

The goal: the Q25 runs a kernel that is the upstream MT6789 tree plus a board DTS and config, with
every hardware fix in that tree or on its way to mainline. Vendor drivers stay only where no
mainline path exists yet, in their own packages, with no userspace hardware poking around them.

## 1. The upstream landscape

| Tree | Head | What it is |
|---|---|---|
| [torvalds/linux](https://github.com/torvalds/linux) | `6628e7d4c6b2` (v7.4-rc1) | No MT6789 clk, pinctrl, pmdomain, pwrap or DTS. Has the same-IP drivers we reuse: MT8186/MT8188 clk, pmdomain, drm, AFE; `mt6358` PMIC MFD/regulator/codec; `mt6359-accdet`; `bq256xx`; `aw87390`; `tps65132-regulator`; `regulator-haptic`; `inv_icm42607`; `mmc5633`; `imx111`; `s5kjn1`; `t7xx`; `btmtkuart`; mt76 SoC wmac (`mt7915/soc.c`). |
| [ellyq/mtk_g99-mainline](https://gitlab.nura.eco/ellyq/mtk_g99-mainline) `master` | `978b8b672d68` (2026-06-06) | v7.0 + 23 commits: Arseniy Velikanov's MT6789 SoC series (clk, FHCTL, pinctrl, pwrap, i2c, smi, cmdq, cpufreq-hw, dvfsrc, EMI icc, regulator coupler, panfrost, pwm, tphy fix) and Alicja Michalska's DTS (`mt6789.dtsi`, `mt6789-motorola-vicky.dts`, `mt8781-zinwa-q25.dts`). **This is our base, unchanged since we forked it.** |
| [pmaports MR !8365](https://gitlab.nura.eco/nura/pmaports/-/merge_requests/8365) | `7bc121d5` (open, updated 2026-10-13) | `linux-postmarketos-mediatek-g99` 7.0 (ellyq master tarball, no extra patches) + `device-mediatek-g99`. |
| [linux-mediatek/linux](https://github.com/linux-mediatek/linux) `mt6789-next` | `2ed59e432779` (2025-08-25, next-20250711) | Arseniy's working tree. Has MT6789 pieces **ellyq does not**: `a2a96be99f1b` pmdomain (all 15 SPM domains, MD..CAM_RAWB), `2287d270918a`+`bd88ccdbd684` IOMMU, `609b2c598786` LVTS thermal, `880bc1cbf3a3` [WIP] drm/mediatek MT6789 (mmsys routing, mutex, rdma, dsi), `3e6c84ec8051` mtk-mutex defer, `a332e9128dfd` DSI host registration order, `9e9ac6390702` reboot modes, `ec1b71bd3149` simple-framebuffer `power-domains` (the "random simplefb crashes" fix). `adomerle/mt6789-sound` `996ec48145f6` is the AFE we build. |
| [mt6768-mainline/linux](https://github.com/mt6768-mainline/linux) `cleanup` | 2026-11-01, next-20261015 | Roman Vivchar's MT6768 (Helio G85) series, same generation and **same MT6358 PMIC**, written as upstream-ready patches with bindings. Directly reusable: `7aa11fc98409` mt6358 fuel gauge power_supply driver (+ `2ae4ae27856c` MFD cell, `a773719a6954` DT), `ca09cacace6d`/`4d88462dd5ea`/`e39415eeed8b` mt6359-auxadc fixes, `09b70b23458c` mt6358 codec gain fix, `6d3ec2fbb6e7` "mtk_dsi: stop engine on mtk_dsi_poweron" (bootloader left DSI running), `03d385e31d55` DSI HS clock for LPM panels, `63837f7e510e` mt6768 pmdomain, `5bb4c32e098a` regulator coupler, `bed7b693caa3`/`1f83613cb70f` CPU speedbin, auxadc thermal. |
| [JamiKettunen/u-boot-mt6789](https://github.com/JamiKettunen/u-boot-mt6789) `q25` | `11b7b36cf6c2` | The U-Boot the phone runs (DMI: `BIOS 2025.10-rc5-g11b7b36cf6c2-dirty`). |
| [JamiKettunen/android_kernel_zinwa_mt6789](https://github.com/JamiKettunen/android_kernel_zinwa_mt6789) `droidian-new` | 2026-10-29 | Deathmist's Halium/Droidian kernel (fork of LineageOS `android_kernel_xelex_mt6789`). No newer public mainline tree of his was found; the mainline coordination point is ellyq's tree and MR !8365. |

lore.kernel.org refused requests from this environment (HTTP 403), so whether the out-of-tree
series above have been posted is **unverified**; the trees are cited instead. The WL2868C regulator
is the one item known to be on the list (v4, 2026-10-31, per `devices/zinwa/q25/modules/README.md`).
Julien Stephan's MediaTek ISP3.0 seninf/camsv series reached
[v8](https://lkml.iu.edu/hypermail/linux/kernel/2501.2/06543.html) (Jan 2025) and is not in mainline.

## 2. Inventory

`H#` = hack ID, referenced by the work items in section 3. "Where" is relative to the repo unless
absolute. `pkg/` = `packaging/packages/`; `Q/` = the bring-up notes on the build drive,
`/run/media/patrickquinn/marathon-build/q25/`. Kernel patches are on `feat/q25-kernel-package` in
`pkg/linux-zinwa-q25/` and in `devices/zinwa/q25/kernel/`.

### 2.1 Kernel command line (`pkg/device-zinwa-q25/kernel-cmdline.conf`)

| H# | Item | Why it exists | Fixed by |
|---|---|---|---|
| H1 | `modprobe.blacklist=mediatek-drm,panfrost,panel-zinwa-q20-hd720,phy-mtk-mipi-dsi-drv` (and `pkg/q25-gpu-render/q25-render-only-blacklist.conf`, which adds `mtk_mmsys`) | With the display nodes enabled, udev autoloads mediatek-drm in the initramfs; it takes over the DSI that LK left scanning and hangs in the first atomic commit, wedging boot. Panfrost is held back so `q25-gpu-prepare` can load it after its own power-domain shim. | W5, W6 |
| H2 | `pd_ignore_unused` | No complete MT6789 power-domain provider; the shims register single domains, and genpd would otherwise switch off DISP (and others) under the firmware framebuffer. | W3, W4 |
| H3 | `clk_ignore_unused` | simple-framebuffer does not claim the display clocks, and the imp_iic_wrap I2C gates are orphans (H20); the unused-clock sweep would gate live clocks. | W2, W4 |
| H4 | `regulator_ignore_unused` | The display and panel rails LK left on are not claimed by any consumer. HW notes: "iteration-1 PMIC enable bricked the device" (`~/zinwa-q25-port/dumps/HW_MAP.md`): regulators switched under the live panel. | W4, W5 |
| H5 | `nowatchdog` | Added during bring-up so slow initramfs `udevadm settle` could not trip a lockup reset. Hides real lockups. | Drop in phase 0 once boots are reliable (they are). |
| H6 | `earlycon=efifb` | Debug console into the live scanout; with `keep_bootcon` it caused the "screen jump" (`Q/display-corruption/HANDOFF.md`). Harmless now, but it writes into the framebuffer. | Drop with W5. |

### 2.2 Boot services and scripts that touch hardware (`pkg/device-zinwa-q25-marathon/`, `pkg/q25-gpu-render/`)

| H# | Item | What it does | Root cause | Fixed by |
|---|---|---|---|---|
| H7 | `q25-platform-prepare` (+`.service`, sysinit) | Writes `0` to `/sys/devices/system/cpu/cpu0/online` every boot. | Memory corruption seen only with CPU0 online (multi-thread allocator seeds fail; `Q/cpu0-quarantine-20261030/README.txt`). Cause unknown; candidates in W8. | W8 |
| H8 | `q25-user-slice-cpu.conf`, `q25-user-manager-cpu.conf`, `CPUAffinity=4-7` in `50-q25-session.conf` | Pins the whole session and greetd to CPUs 4–7. | Earlier form of the same CPU0 workaround ("bring-up stability policy"). | W8 |
| H9 | `q25-backlight` (+`.service`) | Loads `q25-i2c-clk`, unbinds and rebinds `i2c-mt65xx` on `11f00000.i2c` (i2c7), then writes the bus number to `panel-doze`'s `ocp_attach` so it drives the OCP2131. | i2c7 probed with an orphan 0 Hz clock (H20) so its timing is wrong; nothing in the kernel owns the OCP2131 bias chip, which is the only brightness control. | W2, W5 |
| H10 | `q25-vsyncdrm` (+`.service`) | `driver_override`s the firmware framebuffer from simpledrm to `q25-vsyncdrm` after Plymouth quits. | simpledrm has no vblank; the compositor free-ran at ~160 fps on a 70.98 Hz panel. | W5 |
| H11 | `q25-gpu-prepare` (+`.service`, greetd drop-in `80-q25-gpu-prepare.conf`) | `insmod`s a private `q25-mfg-only-v2.ko`, `gpu-sched.ko`, `panfrost.ko`; forces `power/control=on`; walks devfreq 390→467→390→700 MHz and pins it; checks VGPU/VSRAM readback. | No MT6789 MFG power domains in the kernel; no MFG clock-mux notifier, so devfreq PLL hops are unsafe; GPU kept powered because "a later SRAM first-enable can reset coupling". | W3, W6 |
| H12 | `q25-shell-session` GPU selector, `q25-shell-session.gpu` (`PAN_MESA_DEBUG=noafbc`, `LIBGL_DRIVERS_PATH=/usr/lib/q25-gpu/dri`), `simpledrm_dri.so` shim, `/etc/q25/eglfs-kms.json` | Starts the GPU session only if `q25-gpu-prepare` wrote its ready file (which requires CPU0 offline), runtime PM is forced on and devfreq reads 700 MHz; maps Mesa's `simpledrm` KMSRO lookup onto the `mediatek` render-only driver; disables AFBC. | Display is simpledrm, not mediatek-drm, so Mesa finds no kmsro pairing; AFBC corrupts (cause unresolved). | W5, W6 |
| H13 | `q25-md1-off.service` (+post-install arming file) | `insmod q25-md1-owner standalone=1 md_off_at_boot=1` to switch off the MD1 domain the preloader left on. | No MD power domain in the kernel, so genpd cannot switch it off as unused. | W3 (MD domain) |
| H14 | `q25-usb-gadget` (+`.service`) | Recreates the pmOS USB network gadget in configfs after boot. | The pmOS initramfs only creates it if a UDC exists when it looks (`cat …/g1/UDC: No such file` at 7.8 s in the boot log). Why the musb UDC is late is unverified. | W16 |
| H15 | `q25-bt-address` (+`.service`) | Derives a Bluetooth address from machine-id and sets it with `btmgmt public-addr`. | Controller reports a placeholder; the nvdata copy is multicast. | Section 4.1 |
| H16 | `q25-wifi.system-sleep` | rfkill-blocks Wi-Fi around suspend. | gen4m's AXI suspend/resume are stubs. | Section 4 |
| H17 | `q25-wmt` (`q25-wmt.c`), `q25-connsys`, `q25-wmt-launcher`, `q25-wifi`, `q25-bluetooth` services | Native replacement for Android `wmt_loader`/`wmt_launcher`: ioctls on `/dev/wmtdetect` (SoC init, A-die probe), a resident daemon answering the ROM-patch up-call on `/dev/stpwmt`, writes `S`/`0` to `/dev/wmtWifi`. | Vendor WMT design: firmware selection and function power live in userspace. | Section 4 |
| H18 | `q25-native-gauge` (Python service `q25_gauge_service.py`, `q25_soc.py`, `stock-profile0.json`, `90-q25-battery-model.conf`, `battery-model-experimental`) | Reads current/CAR snapshots from `q25-mt6358-live`, fits the stock battery profile, writes capacity back into the kernel; UPower told to ignore critical levels. | No MT6358 fuel-gauge driver; `fuel-gauge` is `generic-adc-battery` (voltage only). | W9 |
| H19 | `q25-root-dio.service` | `losetup --direct-io=on` on the loop-mounted root. | Root is an ext4 file on the userdata carrier (`q25-carrier.hook`). Storage layout, not hardware; goes with `docs/roadmap/2026-10-31-storage-erofs-f2fs.md`. | Storage roadmap |

### 2.3 Out-of-tree kernel modules: Marathon shims for missing drivers (`devices/zinwa/q25/modules/`, `pkg/q25-gpu-render/`)

| H# | Module | What it does | Root cause | Fixed by |
|---|---|---|---|---|
| H20 | `q25-i2c-clk` (`clk/`) | Registers a critical `top_i2c` alias of `i2c_pseudo_ck`. | `clk-mt6789-imp_iic_wrap.c` names the parent `top_i2c`, which topckgen never registers: every I2C "main" clock is an orphan at 0 Hz. A DT workaround (dt4) gated `i2c_sel` for all buses and boot-looped the phone (`Q/backlight-bringup/HANDOFF.md`, update 6). | W2 |
| H21 | `q25-mfg-only-v2` (`pkg/q25-gpu-render/q25-mfg-only-v2.c`) | A copy of `mtk-pm-domains.c` with linux-mediatek `2ed59e43` MT6789 MFG data, registering only MFG2–5 on the SPM node. Shipped as a prebuilt `.ko`. | ellyq's tree lacks `a2a96be99f1b`; the copy adds fixes (OF child reg lookup, supply resolution, initial-off guard). | W3 |
| H22 | `q25-audio-pd` (`audio/q25/`) | Second genpd provider on the same SPM node, resolving only AUDIO (11). | Same. | W3 |
| H23 | `q25-conn-pd` (`conn-pd/`) | Provider for CONN (1) plus a reset controller on `toprgu` exposing only bit 12. | Same; `mtk-wdt` binds toprgu through the mt6589 fallback without MT6789 reset data. | W3 |
| H24 | `q25-cam-pd` (`cam-pd/`) | Provider for CAM (12). | Same. | W3 |
| H25 | `q25-mt6366-irqfix` (`audio/q25irqfix/`) | Patches the PMIC irq chip's group table at runtime (AUD/MISC bits 7/8). | Mainline `enum mt6358_irq_top_status_shift` has AUD=6, MISC=7 (still wrong in v7.4-rc1): ACCDET storms at ~24000 irq/s. Fixed in-tree by our `0009`. | W10 (and phase 0: the from-source kernel already carries 0009) |
| H26 | `q25-panel-doze` (`panel/`), DT node `zinwa,q25-panel-doze` (patch `0008`) | Binds to the DSI register range and sends DCS sleep/wake as video-mode commands; drives GPIO84 (OCP2131 enable) and GPIO85 (panel reset); `ocp_attach` brightness over I2C. | No DSI/DRM driver owns the pipeline (H1). | W5 |
| H27 | `q25-vsyncdrm` (`display/`, 1261 lines) | A copy of simpledrm that reads RDMA0's line counter to fake a scan-locked vblank; keeps the DRM name `simpledrm` for Mesa. | Same. | W5 |
| H28 | `q25-mt6358-live` (`gauge/`) + kernel `0002` | Root-only snapshot of PMIC current and CAR registers, cache for the userspace model. | No fuel-gauge driver. | W9 |
| H29 | `q25-cam-dt` (`cam-dt/`) | Applies `q25-camera.dtbo` from the firmware path at runtime (`of_overlay_fdt_apply`); leaks on removal (boot log warnings). | Camera nodes are not in the board DTS. | W15 |
| H30 | `q25-haptic` (`haptic/`) | Creates a `regulator-haptic` platform device pointing at the MT6366 `vibr` LDO. | No haptic node in the board DTS. | W14 |
| H31 | `q25-md1-owner` (`md1/`, 1175 lines) | Replaces LK's MD1 work: image placement, bank remap, MD1 MTCMOS, EMI MPU via ATF SiP, boot trigger, HS1 wait. Also used standalone for H13. | U-Boot replaced LK, so nobody boots the modem; vendor CCCI expects LK to have done it. | Section 4 |

### 2.4 Out-of-tree drivers for real devices (Marathon-written or ported)

| H# | Module | Device | Status | Fixed by |
|---|---|---|---|---|
| H32 | `q25-bbq-keys` + `q25-keyboard-led` (`keyboard/`), `q25-keyboard.modprobe.conf` (`client_name=6-001f`), `99-q25-native-keyboard.rules` | RP2040 QWERTY on i2c6 @0x1f, BBQ20-style FIFO protocol, key backlight. LED module attaches to the keyboard's bound client by name. | Marathon driver, `compatible` not upstream; LED is a sidecar instead of part of the driver. | W12 |
| H33 | `hx32062se` (`light/`), `q25-hx.modprobe.conf` (`near_level=600`) | TYHX HX32062SE ALS/proximity on i2c9 @0x2b; registers decoded from the SCP sensor-hub firmware. | No mainline driver; DT carries stock threshold 3800. | W13 |
| H34 | `q25-oca72390` (`audio/q25/`) | Orient-Chip OCA72390 speaker PA (i2c3 @0x58), register lists embedded. | Register-compatible with Awinic AW87390 (mainline `sound/soc/codecs/aw87390.c`) but reports ID 0x11. | W11 |
| H35 | `q25-mt6366-card` (`audio/q25/`), `q25-audio.modprobe.conf` softdeps, `q25-audio.modules-load.conf` | ASoC machine driver (AFE + MT6366 + PA), MTKAIF calibration port. | No MT6789 machine driver; codec binds to an MFD cell without an OF node, so it is loaded by name. | W11 |
| H36 | `q25-mt6358-accdet` (`audio/q25accdet/`, `options standalone=1`) | Headset detection, port of the vendor `mt6358-accdet.c` (LineageOS `2a873a35`). | Mainline has only `mt6359-accdet`. | W10 |
| H37 | `snd-soc-mt6789-afe` + codec patches `0002`–`0006` (`audio/patches/`) | AFE from `adomerle/mt6789-sound` `996ec481` ("sound wip") + `0001` fixups; `0003`/`0005`/`0006` are debug controls. | WIP upstream driver. | W11 |
| H38 | `mtk-seninf6s`, `mtk-camsv6s`, `phy-mtk-mipi-csi-2-1` (`camera/`) | MediaTek Genio BSP `mtk-v6.6` (MT8189 ISP 6s) + `0001-mt6789-port.patch`. | No mainline MediaTek camera receive path. | W15 |
| H39 | `wl2868c-regulator` (`cam-pmic/`) | Camera LDO PMIC. | LKML v4 2026-10-31, unmodified. | W15 (lands upstream) |
| H40 | `q25-btmtk-stp` (`bt/`) | BlueZ HCI over the vendor WMT/STP/BTIF. | Vendor transport. | Section 4 |

### 2.5 Mainline code built out of tree (config gaps, not driver gaps)

| H# | Modules | Why OOT |
|---|---|---|
| H41 | 57 networking modules (`tun`, `veth`, `dummy`, `bridge`, `llc`, `stp`, all `nf_*`/`nft_*`/`xt_*`/`ip*_tables`) | Kernel config leaves them out; Deckard needs them. |
| H42 | 9 media core modules (`mc`, `videodev`, `v4l2-*`, `videobuf2-*`) and `imx111`, `s5kjn1` (+3 patches in `camera/i2c/`) | Same; sensor patches are ours. |
| H43 | `snd-timer`, `snd-pcm`, `snd-jack`, `snd-soc-core`, `snd-soc-mt6358`, `snd-soc-mtk-common` | `CONFIG_SND_SOC` unset in the running kernel. |
| H44 | `cfg80211`, `bluetooth`, `rfkill`, `spi-mt65xx`, `regulator-haptic`, `inv-icm42607`(+`-spi`), `mmc5633` (+`mmc5633-q25.patch`) | Unset or unshipped. `inv_icm42607` is mainline code newer than v7.0 (torvalds `abf8c334`). |
| H45 | `panfrost.ko`, `gpu-sched.ko` in `q25-gpu-render` | Built in-tree but shipped privately and loaded by H11. |
| H46 | `CONFIG_MODULE_UNLOAD=n` (`7.0.0-q25-cfi-test`, `linux-zinwa-q25` config) | Bring-up safety; makes every module test a reboot. |

### 2.6 udev and modprobe policy that encodes hardware facts

| H# | File | What | Fixed by |
|---|---|---|---|
| H47 | `61-q25-charge-voltage.rules` | Writes `constant_charge_voltage=4440000` to bq256xx at add. `bq256xx_hw_init()` programs the chip default (4.208 V) and uses the battery's 4.44 V only as a ceiling: the cell stopped near 80 %. | W9 |
| H48 | `99-q25-upower-duplicate.rules`, `q25-power-supply-ignore`, `upower-q25` (UPower patch for `UPOWER_IGNORE`) | Hides `bq256xx-battery` so UPower sees one battery. | W9 |
| H49 | `61-q25-sensor-local.rules` | `ACCEL_MOUNT_MATRIX` for the ICM-42607. | W13 (DT `mount-matrix`) |
| H50 | `q25-connsys.modprobe.conf` | `softdep wmt_drv pre: q25-conn-pd`. | W3 + section 4 |
| H51 | `q25-camera.modprobe.conf`, `q25-camera.modules-load.conf` | Enables H24/H29 by parameter, loads them at boot. | W3, W15 |
| H52 | `q25-modem.conf.modprobe`, `78-q25-modem.rules` | Blacklists ECCCI until the owner hands off; tags `ttyC0`/`ccmni` for ModemManager with a hard-coded physdev path. | Section 4 |

Not hardware workarounds, so outside H1 (kept): `q25-carrier.hook`, `q25-root-grow`,
`q25-home-crypt`, `q25-boot-bless`, `q25-esp-readonly`, `q25-boot-check`, `90-q25-recovery-console.rules`,
`q25-keyboard-layout.env`/`q25.xkb-symbols` (layout), UCM files (`q25-mt6366.conf`, `HiFi.conf`,
`VoiceCall.conf`: UCM is the upstream mechanism), `q25-deckard.modules-load.conf` (goes with H41).

### 2.7 Kernel patches and DT

| Patch | What | Disposition |
|---|---|---|
| `0001` iio mt6359-auxadc scale | Adds the resolution to BATADC scale. | Same bug as mt6768-mainline `ca09cacace6d` (+`4d88462dd5ea` VBAT bit-15 mask). Agree on one version with Roman Vivchar; send to linux-iio. |
| `0002` private mt6358 CAR snapshot | Diagnostic PMIC child for H28. | **Drop** for the mt6358-gauge driver (W9). |
| `0003` net/wwan RPC metadata validator | Inactive helper, no Kbuild entry. | **Drop** from the kernel series; it belongs with the vendor modem userspace if anywhere. |
| (`0004`) | Numbering gap. | Renumber when rebasing. |
| `0005` add `mt6789-zinwa-q25.dts` | Our own board DTS **beside** upstream's `mt8781-zinwa-q25.dts`. | **Drift**: rebase onto upstream's file (W19). |
| `0006` match the accepted boot | Framebuffer pitch, touch reset, keyboard on i2c6, drops ramoops. | Upstream to ellyq's DTS (real fixes for every Q25). |
| `0007` audio, sensors, CONNSYS | Audio, AP sensor buses, and vendor `mediatek,wifi`/`mediatek,btif`/consys nodes. | Split: audio/sensors upstream when their drivers are (W11, W13); vendor nodes into an overlay owned by the vendor package (section 4). |
| `0008` panel Doze node | `zinwa,q25-panel-doze` takes GPIO84/85. | **Drop** with W5. |
| `0009` mfd mt6358 AUD/MISC bits | Real bug, still in mainline. | **Send now** to Lee Jones / linux-mediatek with `Fixes:`; affects every MT6358/MT6366 board (MT8183/MT8186 Chromebooks). |
| `0010` 256 MiB camera pool | CAMSV's 32-bit `dma_alloc_coherent()` stops at 4 MiB. | **Drop** once the M4U IOMMU is on (W7). |
| `0011` MD1 modem nodes | Vendor ECCCI compatibles, fixed phandles `0x90`/`0x91`. | Vendor overlay (section 4); never upstream. |
| `g99-0001` drm/mediatek MT6789 | Reuses the MT8186 routing table. | Reconcile with linux-mediatek `880bc1cbf3a3` (own `mt6789-mmsys.h`, mutex, rdma, dsi data) and post one series (W5). |
| `g99-0003` bq256xx enable charging at probe | Clears EN_HIZ, sets CHG_CONFIG. | Send to linux-pm (W9). |
| `g99-0004` pinctrl-mt6789 `pm_sleep_ptr` | Build fix. | Fold into ellyq's pinctrl patch. |
| `panel-zinwa-q20-hd720.c` (copied into the tree in `prepare()`) | Mainline-style DSI panel driver (vendor init table is `#if 0`). | Upstream with a binding and a vendor prefix (W5). |

## 3. Replacement work

Effort: S ≤ 2 days, M ≤ 2 weeks, L ≤ 2 months, XL longer or uncertain. Each item lands as
patches against the MT6789 tree (section 5), not as Marathon packages.

**W1. Build mainline code in the kernel** (S, low risk). In the `linux-zinwa-q25` config: `SND_SOC`
and the MT6358 codec, `CFG80211`, `BT`, `RFKILL`, `SPI_MT65XX`, netfilter/bridge/veth/tun as
Deckard needs, media core + `VIDEO_IMX111`/`VIDEO_S5KJN1`, `INPUT_REGULATOR_HAPTIC`, `MMC5633`,
`REGULATOR_TPS65132` (for W5); backport `inv_icm42607` until the base moves past it; ship panfrost
and gpu-sched as normal in-tree modules; `MODULE_UNLOAD=y`. Send the `imx111`/`s5kjn1`/`mmc5633`
patches to linux-media/linux-iio. Eliminates H41–H46 and 84 out-of-tree modules.

**W2. Fix the MT6789 I2C clock parent** (S, high risk). In `clk-mt6789-imp_iic_wrap.c` give the
imp gates the parent that exists (`i2c_pseudo_ck` per the vendor `clk-mt6789-i2c.c`, or the topckgen
clock it feeds from), as `q25-i2c-clk` proves at runtime. Once every I2C clock has a real parent,
CCF refcounts `i2c_sel` correctly and no alias or critical flag is needed. Risk: the dt4 boot loop
gated `i2c_sel` under touch, charger and keyboard; test only from a one-shot boot entry with the
known-good entry as default. Upstream: Arseniy Velikanov's clk series (ellyq `f2d38415`). Eliminates
H20, the rebind in H9, part of H3.

**W3. One MT6789 SPM power-domain provider** (M, high risk). Take linux-mediatek `a2a96be99f1b`
(`mt6789-pm-domains.h`, 15 domains, bus-protect data in `infracfg.h`), fold in the fixes proven in
`q25-mfg-only-v2` (reg lookup, `MTK_SCPD_DOMAIN_SUPPLY` for MFG0/1) and the data cross-checked in
`q25-audio-pd`/`q25-conn-pd`/`q25-cam-pd` against the stock `mtk-scpsys-mt6789.c`; add MT6789 reset
data to `mtk-wdt` (toprgu `WDT_SWSYSRST` bits, as MT8186 has) for the CONN MCU reset; add the
binding (`mediatek,mt6789-power-controller` in `mediatek,power-controller.yaml`). Model the review on
mt6768-mainline `63837f7e510e` (IFR/DPY left out because Linux must never touch them). Risk: the
v1 attempt powered DISP at probe under LK's scanout and the phone lost its panel and USB (2026-07-15); W4 is
what makes that safe. With MD in the provider, genpd powers the unbooted MD1 off as unused, so
`q25-md1-off` goes too. Eliminates H2, H13, H21–H24, H50, H51 (CAM half).

**W4. Let simple-framebuffer hold what it uses** (S, medium risk). List DISP's `power-domains`,
the display clocks and the panel/bias supplies on the `framebuffer@ff97c000` node. simpledrm keeps
them on until a real driver takes over (linux-mediatek `ec1b71bd3149` does exactly this for the
DISP domain). Then remove `pd_ignore_unused`, `clk_ignore_unused` and `regulator_ignore_unused`
one at a time, each verified by a cold boot. Eliminates H2–H4.

**W5. mediatek-drm, the panel and the bias supply** (L, high risk). Display series: reconcile
`g99-0001` with linux-mediatek `880bc1cbf3a3` + `3e6c84ec8051` + `a332e9128dfd`; take mt6768-mainline
`6d3ec2fbb6e7` (stop the engine the bootloader left running before switching DSI mode, the likely
cause of the commit hang in H1) and `03d385e31d55`. Panel: upstream `panel-zinwa-q20-hd720` with a
binding. Bias: the OCP2131 (i2c7 @0x3e, VPOS/VNEG regs 0x00/0x01 at 4.0 V + n×0.1 V, ID 0x0d at
0x04) matches TI TPS65132's register map and address; add an `ocs,ocp2131` compatible to
`tps65132-regulator` (verify reg 0x03/0xff against `Q/backlight-bringup/datasheet/ocp2131.pdf`). The
panel takes `avdd-supply`/`avee-supply`, owns GPIO84/85, and registers its backlight device with
`update_status` setting the bias voltage, which is how this panel's light is controlled (stock
`_gate_ic_backlight_set`; DCS BCTRL is 0). Doze becomes ordinary DRM DPMS; vblank is real.
Mesa's kmsro already pairs `mediatek` with panfrost. Eliminates H1 (display half), H6, H9, H10, H12
(shim, eglfs config), H26, H27, `0008`, the `panel-bias-enable` node.

**W6. Panfrost on MT6789 as a normal driver** (M, medium risk). Needs W3 (MFG0–3 with supplies), the
MT6789 regulator coupler (ellyq `e7b05c2b`, already in tree), and a clock-mux notifier on the MFG
mux so devfreq can hop PLL OPPs (the generic `mtk_clk_mux` notifier MT8183/MT8186 use; FHCTL is in
ellyq `93312811`). Root-cause the AFBC corruption with the IOMMU on (W7) before keeping `noafbc`.
Eliminates H1 (GPU half), H11, H12, H45.

**W7. M4U IOMMU and SMI** (M, medium risk). linux-mediatek `2287d270918a` + `bd88ccdbd684`, SMI
already in ellyq (`55959b22`); drop Arseniy's "Disable iommu for now" (`a3a7d9830e61`). Gives the
display, GPU and camera IOVA space. Eliminates `0010` and the camera pool.

**W8. CPU0** (M–L, unknown cause). Facts: with CPU0 offline every test passes; CPU0 can be taken
off (`psci: CPU0 killed`) but not brought back (CPU_ON fails); all CPUs start at EL1. Secondary
CPUs enter Linux through ATF's PSCI warm-boot path; CPU0 enters through U-Boot's EFI path. Deathmist's
U-Boot has `CONFIG_MTK_SMC_JUMP=y` (`c8e0347069f9`, "needed for newer SoCs running U-Boot in Insecure
World, else … undefined behaviour"), but that SMC (`MTK_SIP_KERNEL_BOOT`) is only issued by `bootm`;
our `bootefi` → systemd-boot → EFI-stub path never makes it. Lead hypothesis: CPU0 misses per-CPU
setup that ATF does on the kernel-boot SiP. Test in order, each from a one-shot entry: (a) boot the
same kernel via `booti`/`bootm` with the SMC jump and run the allocator seeds with CPU0 online; (b)
`ARM64_ERRATUM_2441007=y` (A55 TLBI race, disabled today); (c) compare CPU0's accessible ID/feature
registers with CPU1's (Arseniy carries "HACK: arm64: cpufeature: Ignore capabilities conflict"
`5c5dffbd8def`, so MT6789 already shows CPU feature mismatches). The fix belongs in U-Boot (an EFI
`ExitBootServices` hook that performs the SiP call) or ATF config, not the kernel. Eliminates H7,
H8, the CPU0 check in H11/H12.

**W9. Battery and charging** (M, medium risk). Port mt6768-mainline `7aa11fc98409` (mt6358-gauge:
coulomb counter, SoC, current) + `2ae4ae27856c` + `a773719a6954` to the MT6366, with the stock
profile as `ocv-capacity-table-0` on the `simple-battery` node instead of `stock-profile0.json`.
bq256xx: send `g99-0003`, and a second patch that programs `min(constant_charge_voltage_max,
chip max)` and the battery's charge current at init instead of the chip defaults. Duplicate battery:
the gauge is the battery; ask on linux-pm whether bq256xx should skip registering its own
`bq256xx-battery` when `monitored-battery` points at a gauge-backed cell, rather than patching UPower.
Eliminates H18, H28, H47, H48, `0002`, `upower-q25`.

**W10. PMIC interrupts and ACCDET** (S + M, low risk). Send `0009` now. Then extend
`sound/soc/codecs/mt6359-accdet.c` to the MT6358/MT6366 register layout (the vendor
`mt6358-accdet.c` gives the deltas) instead of shipping a separate port. Eliminates H25, H36.

**W11. Audio** (L, low risk). Finish `adomerle/mt6789-sound` as an MT6789 AFE patch modelled on
`sound/soc/mediatek/mt8186`; an `mt6789-mt6366` machine driver modelled on `mt8186-mt6366.c` (which
already does MTKAIF calibration), with the speaker PA as an `aw87390` aux device: add the OCA72390
ID/compatible to `aw87390.c` and load its register lists as that driver already does. Drop the
debug codec patches `0003`/`0005`/`0006`; upstream `0002` if it is a real fix. Give the MT6366 codec
an OF node so it autoloads. Eliminates H34, H35, H37, the audio softdeps.

**W12. Keyboard** (M, low risk). One I2C input driver with a DT binding for the Q25's RP2040
keyboard firmware, keymap via `linux,keymap`, the backlight as an LED class device of the same
driver. Prior art: wallComputer's BBQX0 and the Beepy (`bbq20kbd`) drivers. Report a plain keyboard
so the default udev rules classify it. Eliminates H32 and `99-q25-native-keyboard.rules`.

**W13. Sensors** (M, low risk). `hx32062se` as an IIO driver with binding (proximity near level is
a hwdb/udev `PROXIMITY_NEAR_LEVEL` for iio-sensor-proxy, not a module option); ICM-42607
`mount-matrix` in DT; `mmc5633`/`inv_icm42607` via W1. Eliminates H33, H49.

**W14. Haptics** (S, low risk). A `regulator-haptic` node with `haptic-supply = <&mt6366_vibr_reg>`
in the board DTS. Eliminates H30.

**W15. Cameras** (L–XL, medium risk). Camera nodes in the board DTS (no runtime overlay); WL2868C
from its LKML series; the receive path rebased on Julien Stephan's ISP3.0 seninf/camsv series
(v8) rather than the Genio 6s BSP, with MT6789 data; IOMMU from W7. Eliminates H29, H38, H39, H51.

**W16. USB gadget in the initramfs** (S–M). Find why the musb UDC is absent at 7.8 s (probe
deferral on the tphy or clocks; boot it with `loglevel=7` once). Fix that in DT/driver; if it is
legitimately late, fix the pmOS initramfs to wait for a UDC (upstream pmaports). Eliminates H14.

**W17. Thermal** (M). No thermal zones exist today. Take LVTS (`609b2c598786`) and the AUXADC
thermal work from mt6768-mainline. Not a hack to remove, but the safety net every other phase needs.

**W18. Command line cleanup** (S). After W2–W5: drop `nowatchdog`, `earlycon=efifb`, the blacklist,
the three `*_ignore_unused` flags. Target cmdline = pmOS defaults + root selection.

**W19. Board DTS convergence** (M). Move our nodes onto upstream's `mt8781-zinwa-q25.dts`, with
labels instead of raw phandles, every compatible either in mainline or in a patch on the list, and
the vendor nodes (CONNSYS, Wi-Fi, BTIF, MD1/ECCCI) in an overlay shipped by the vendor packages.
`make dtbs_check` clean. Eliminates `0005`, `0007` (vendor half), `0011`.

## 4. Vendor drivers: quarantine

No mainline path is realistic soon for three functions. They stay, under H2:

- Own packages: `q25-connsys` (WMT, BTIF, connadp, gen4m, `q25-btmtk-stp`, `q25-wmt`, the
  firmware copy) split out of `q25-kernel-modules`/`device-zinwa-q25-marathon`; `q25-modem` (already
  separate) with `q25-md1-owner` moved into it. Each ships its DT overlay (from `0007`'s vendor
  half and `0011`) and is the only thing that applies it, so the board DTS stays upstreamable.
- They consume standard kernel interfaces, never shims: CONN power domain and CONN MCU reset from
  W3 (H23 goes), regulators by phandle, pinctrl states. The vendor code is not extended with
  Marathon features.
- Userspace helpers allowed only where the vendor design needs them, each listed here.

### 4.1 CONNSYS Wi-Fi and Bluetooth

Today: `connadp`, `btif_drv`, `wmt_drv`, `wmt_chrdev_wifi`, `wlan_drv_gen4m_6789` from
iasnezhkov/android_kernel_ikko_mindone `9cd73c15` + `wifi/0001`/`0002`; `q25-btmtk-stp`; helpers
H15, H16, H17.

Quarantine cleanups (vendor-side, small): do the ROM-patch selection with `request_firmware()` in
`wmt_drv` and the A-die probe at probe time, so `q25-wmt init/launch` and the resident daemon go;
keep `wifi-on` only if gen4m cannot power its function on open. Bluetooth address: have U-Boot fill
`local-bd-address` in the DT (the bluetooth core reads it with `HCI_QUIRK_USE_BDADDR_PROPERTY`),
derived as now, instead of `btmgmt` from userspace.

Long-term path (XL, nobody is on it; searches found no open CONNSYS effort for MT6765/6768/6789):
- Wi-Fi: gen4m on MT6789 is CONNAC2 ("soc2_2"). Mainline already runs SoC-integrated MediaTek Wi-Fi
  in mt76: MT7622 (`mt7615/soc.c`) and MT7986/MT7981 (`mt7915/soc.c`, with consys reset, EMI
  `memory-region` and pinctrl in DT). The upstream shape is an mt76 SoC bus for the CONNAC2 family
  (`mt7921`) plus a CONNSYS power-on/A-die driver. That is the only route that ends the vendor stack.
- Bluetooth: mainline MT7622 runs SoC Bluetooth through BTIF exposed as an 8250 UART
  (`mediatek,mt7622-btif` in `serial/8250.yaml`) and `btmtkuart` with MediaTek STP framing. MT6789's
  BTIF is the same block; the missing piece is the shared CONNSYS MCU bring-up that WMT does.
- Watch mt6768-mainline and the MT6789 trees; if anyone starts CONNSYS, join rather than fork.

### 4.2 MD1 modem (CCCI)

Today: `ccci_util_lib`, `ccmni`, `ccci_md_all`, `ccci_ccif`, `ccci_dpmaif` (eccci from the same
donor + `modem/0001`/`0002`); `q25-md1-owner` (H31); userspace `ccci_fsd`, `ccci_rpcd`,
`ccci_mdinit`, `q25-modem-nv` overlay of nvdata/nvcfg/protect, `q25-modem-init` AT sequence,
`modemmanager-mtk-ccci` patches (from the Moto G06 lagos port).

Quarantine cleanups: H13 goes with W3; the DT nodes move to the modem overlay; `q25-modem-up`
stages become plain unit ordering.

Long-term path (XL): the shape mainline already has for Qualcomm modems. A remoteproc driver for
MD1 (load the image from the `md1img` partition copy, EMI MPU via the ATF SiP, MTCMOS via the W3 MD
domain), a WWAN driver over CCIF + DPMAIF exposing AT/data through `wwan_core` (mainline `t7xx`
already implements DPMAIF and CLDMA for MediaTek's PCIe modem and is the code to reuse), and the
filesystem/RPC services in userspace like Qualcomm's `rmtfs`/`tqftpserv`. `q25-modem-init`'s AT
quirks belong in ModemManager's MediaTek plugin upstream.

### 4.3 GNSS

Facts (`docs/roadmap/Q25-GNSS-RESEARCH.md` on `feat/q25-gnss`, `3fc9f14c`): the receiver is
CONNSYS's GNSS function, not a UART part. `/dev/stpgps` in the vendor `gps_drv_stp` is a raw pipe;
the DSP firmware and the position solver live in MediaTek's closed, bionic-linked `libmnl`/`mnld`;
the vendor partition carries no separate GPS firmware; MD1 has no GNSS role; stock DT has
`gps@18c00000` (`mediatek,gps`, EMI window inside `consys_emi`) and LNA pinctrl on GPIO25/GPIO87.
No open prior art exists for CONNSYS GNSS. GeoClue 2 can take NMEA from a socket
(`[network-nmea] nmea-socket=`).

GNSS must not run through Deckard, and should not be a new vendor-driver port by default. Options:

1. **Open, native (preferred end state, XL, uncertain).** A GNSS function on whatever upstream
   CONNSYS driver exists, exposed as a mainline `gnss` device (`/dev/gnssN`; the subsystem already
   has `GNSS_TYPE_MTK`), LNA through pinctrl states in the board DT. Userspace: reverse-engineer
   the DSP boot and measurement stream, take the DSP image from the phone's own `libmnl.so` at
   install time, solve positions with an open engine (e.g. RTKLIB single-point), feed GeoClue
   through `nmea-socket`. Depends on CONNSYS (4.1) and on whether the stream carries navigation
   data.
2. **Vendor `gps_drv_stp` + closed `mnld` natively (user decision only).** Ports like `wmt_drv`
   (needs only its STP/WMT exports and the `mediatek,gps` node), but `mnld` needs a bionic linker,
   stock `/system` libs, `libnvram`, HIDL sensor libs and a native stand-in for the HAL side of its
   socket protocol. This adds exactly the vendor code and userspace workarounds the review objects
   to. If chosen, it lives in the CONNSYS vendor package, copies blobs from the user's own
   partitions, and is listed here.
3. **Wi-Fi/cell/IP positioning meanwhile (now).** GeoClue with its existing sources; nothing to
   build in the kernel.

Recommendation: 3 now; a time-boxed investigation of 1 (does the `/dev/stpgps` stream after DSP boot
contain navigation-message words?) once CONNSYS is otherwise stable; 2 only if the user decides
GNSS is worth vendor code, and then in quarantine.

## 5. Rebase and convergence

How far we have drifted:

- Base: our `_commit` is ellyq master `978b8b672d68`, and ellyq master is still that commit. The
  drift is not the base moving, it is (a) the base aging: v7.0 vs v7.3 released and v7.4-rc1; (b)
  ellyq lacking MT6789 pieces that exist in linux-mediatek `mt6789-next` (pmdomain, IOMMU, LVTS,
  drm); (c) our own pile: 14 kernel-tree patches/files, 12 shim modules, 7 Marathon drivers, 5
  third-party ports, and a second Q25 DTS.
- ellyq's tree and MR !8365 ship the Q25 with framebuffer only; every display, GPU, power-domain,
  audio and charging change we made is ours alone today.

Plan:

1. **Agree a base with the porters first.** Propose to Alicja Michalska (ellyq) and Deathmist, on MR
   !8365 or the mainlining.org channel they use: rebase `mtk_g99-mainline` onto v7.3 (then v7.4),
   pull in `mt6789-next`'s pmdomain/IOMMU/LVTS/drm with Arseniy Velikanov's agreement, and accept
   MT6789/Q25 patches as merge requests there. We send work there, not to a private fork.
2. **Send now** (no dependency, low risk): `0009` (mainline mfd), `g99-0003` (linux-pm), the
   auxadc fix reconciled with Roman Vivchar's, `0006`'s DTS fixes (to ellyq), `g99-0004` (fold into
   ellyq's pinctrl patch), the `imx111`/`s5kjn1`/`mmc5633` patches (mainline).
3. **Send as each work item lands**: W2 → W3/W4 → W5/W6/W7 → W9–W14 → W15, each as an MR to the
   MT6789 tree, mainline-bound pieces (drivers for IP shared with other SoCs) also to the mailing
   lists.
4. **Drop**: `0002`, `0003`, `0008`, `0010`, `0011` (to overlay), our `mt6789-zinwa-q25.dts`
   (merged into upstream's file), every shim module in 2.3 as its replacement lands.
5. **Our package** `linux-zinwa-q25` becomes: upstream MT6789 tree at a commit + `config` + at
   most the Q25 patches still in review. No files copied into the tree in `prepare()`; the release
   suffix `-q25-cfi-test` goes, and the module packages stop pinning one exact prebuilt kernel.

## 6. Phases

Every phase is tested on the phone from a one-shot boot entry with the current entry kept as
default (a bad default DTB once needed an mtkclient ESP rewrite: never default an untested DTB or kernel); the
orchestrator flips the default only after the checks pass on a cold boot and after a reboot.
Persistent journald (`journalctl --list-boots`) is the ground truth for failed boots.

| Phase | Work | Device verification |
|---|---|---|
| 0. Stop the pile (now) | H1/H2 rules in force (`ad9cb804`). Ship the from-source kernel (`feat/q25-kernel-package`). W1 config. Drop `q25-mt6366-irqfix` (the kernel carries `0009`). Drop `0002`/`0003` from the series. Send the "send now" set. Drop `nowatchdog`. | `grep -c '(O' /proc/modules` falls from 99 to the shim, driver and vendor modules only; no new `WARN` in the kernel log; speaker, earpiece, mic, headset detect (no PMIC irq storm in `/proc/interrupts`); Deckard networking; camera stills; module unload works. |
| 1. Clocks and power domains | W2, W3, W4 (cmdline flags removed one per boot). | `/sys/kernel/debug/clk/clk_summary`: imp_iic gates at 124.8 MHz with no `top_i2c`; `/sys/kernel/debug/pm_genpd/pm_genpd_summary`: one provider, MD1 off after boot, DISP held by the framebuffer; i2c7 OCP2131 answers at boot; touch, keyboard, charger, amp probe on cold boot ×10; Wi-Fi/BT/modem still up through the W3 CONN/MD domains. |
| 2. Display and GPU | W5, W6, W7. | `card0` driver `mediatek-drm`; `modetest -v` page-flip at 70.98 Hz; Doze off/on ×20 with no DSI errors; brightness 1..20 visible; panfrost bound at boot, devfreq scales across OPPs under `glmark2` for 1 h with no faults; AFBC on; camera works without the pool. Shell starts with no `q25-gpu-prepare`. |
| 3. CPU0 | W8. | Allocator seeds pass with all 8 CPUs online; 24 h soak with the session unpinned; `q25-platform-prepare` and the affinity drop-ins removed. |
| 4. Power | W9, W17. | One battery in `upower -d`; SoC tracks a full charge to termination and a discharge to 5 % within the stated margin; charging stops at 4.44 V; thermal zones report and throttle. |
| 5. Peripherals | W10–W14, W16, W18. | Headset plug/unplug events; full audio matrix; keyboard and its light with stock udev rules; ALS/proximity/accel/mag in `monitor-sensor`; haptics; USB network from the initramfs; final cmdline has no hardware flags. |
| 6. Cameras | W15. | Both sensors stream at full resolution through libcamera with the IOMMU. |
| 7. Vendor quarantine | Section 4 cleanups, W19. | Board DTS passes `dtbs_check`; vendor overlays applied only by their packages; Wi-Fi/BT/modem pass their existing checks; no vendor helper outside section 4's list. |

Phases 0–2 come first: they remove most of what the review saw (the blacklist, the
`*_ignore_unused` flags, the rebinds, the private GPU loader, five shim modules).

## 7. Rule text

Section H is in `docs/CODING_RULES.md` on `release/first-images` (`ad9cb804`), H1 and H2 as
proposed. Two additions make the plan enforceable; proposed text:

```markdown
### H3. Every existing workaround has an exit

Each Q25 hardware workaround that predates H1 has an `H#` entry in
docs/roadmap/Q25-UPSTREAM-PLAN.md naming the work item that replaces it. A change that adds a
workaround without an entry is rejected; a change that lands a replacement deletes the
workaround and its entry in the same series. Nothing new is added to a workaround: not a module
parameter, not a retry, not a second consumer.

### H4. The board DT uses upstream bindings

Board device trees use only compatibles and properties that are in mainline or in a patch posted
to the relevant list or the device's upstream tree, and pass `make dtbs_check`. Marathon-only or
vendor compatibles live in overlays shipped by the package that needs them, never in the board DTS,
and nodes refer to each other by label, never by raw phandle.
```

## 8. Open questions

- Do Alicja Michalska, Arseniy Velikanov and Deathmist want the v7.3 rebase in ellyq's tree, or is
  there a newer private tree to target? Ask before W3.
- `mt8781-zinwa-q25.dts` vs `mt6789`: the Q25 Pro's marketing SoC is MT8781; keep upstream's naming.
- The OCP2131-as-TPS65132 assumption needs reg 0x03 and 0xff checked against the datasheet before
  the compatible is posted.
- Is bias-voltage brightness acceptable to drm/panel reviewers as a panel-owned backlight, or do
  they want a generic regulator backlight? Ask on dri-devel with the datasheet facts.
- The ACCDET, auxadc and gauge work overlaps Roman Vivchar's MT6768 series: coordinate to post one
  MT6358 series, not two.
