# Zinwa Q25 — getting Marathon OS fully working (research and plan)

Date: 2026-10-17. This is research only. Nothing was built, flashed or edited, and no device was touched.
Device: Zinwa Q25 — MT6789 / Helio G99, Mali-G57 MC2, 720×720 DSI panel, I²C QWERTY keyboard with trackpad, 12 GB RAM, 256 GB UFS.

---

## 0. TL;DR

- **Upstream (Nura) is still at early bring-up.**
  - Status flags: booting = Y, flashing = Y, storage = Y, U-Boot = Y.
  - screen, touch, keyboard and battery are only "P" (partial).
  - GPU (3D), wifi, BT, audio, modem, GPS, camera and USB-net are blank.
  - The SoC page lists display as "simple-framebuffer only", and wifi, BT, audio, modem, camera and **suspend** as N.
  - The pmaports MR !8365 is still **open and labelled `status::mr-stale`**. Its last real change was 2026-04-26.
  - ellyq's kernel tree was last touched 2026-06-06.
  - The Q25 has **no** MT6789 code in torvalds/linux (checked v7.3-rc7).
  - Upstream is *behind* where Marathon got in July on charging, USB gadget, initramfs UFS and display wiring.
- **Recommendation: stay on mainline.** Halium/GKI cannot run Marathon's architecture:
  - It needs a glibc base with libhybris; Marathon's image is pmOS/duranium on musl.
  - It uses Android gralloc buffers instead of Marathon's dmabuf-v4 compositor.
  - Qt 6 has no hwcomposer QPA.
  - The GPU is the proprietary mali_kbase driver, so there is no Panfrost.
  - It would also mean abandoning `scripts/build-image.sh` for this one device.
- **The decision Patrick has to own:** on mainline, **wifi, BT, modem and cameras have no driver anywhere**. "Fully fully working" in those areas is not reachable on any realistic timeline.
  - Mainline *can* deliver: GPU-accelerated Marathon (Panfrost + mtk-drm), the panel, touch, keyboard/trackpad, charging, battery %, thermal, cpufreq, and USB-NCM networking.
  - Wifi has two options: an out-of-tree port of the MediaTek connsys/gen4m driver (months of work), or accepting USB networking.
- **Biggest single unblock found in this research:** `linux-mediatek/linux` branch `mt6789-next` already has:
  - an **MT6789 SPM power-domain driver** (`a2a96be9` "pmdomains: mediatek: Add MT6789 SPM power controller"). It has a full domain table including disp, mfg0–3, audio and cam, and the Redmi Note 13 Pro 4G ("emerald") board runs **Panfrost with it**.
  - a **WIP mtk-drm MT6789** port: `880bc1cb`, with its own `mt6789-mmsys.h` routing table, mutex changes, `62de3871` "drm: Route testing" and an IOMMU driver.
  - **LVTS thermal**.
  - a **sound WIP** branch.
  
  Marathon's own home-grown `0002-pmdomain` patch hard-crashes boot. It should be **replaced** by the mt6789-next patch, not debugged further.
- **New root cause for "only ~1.7 GB RAM":** it is U-Boot, not the kernel DT.
  - `~/zinwa-q25-port/u-boot-mt6789/arch/arm/mach-mediatek/mt6789/init.c` `dram_init()` clamps memory with `get_ram_size(..., SZ_2G)` ("above that things start to break").
  - The U-Boot DTS already declares 12 GB (`reg = <0x0 0x40000000 0x3 0x0>`).
  - Linux boots through EFI, so it only sees what U-Boot's EFI memory map reports.
- **Keyboard correction:**
  - The keyboard is an RP2040 running i2c_puppet firmware, on **I²C at 0x1f** (`bbqX0kbd`).
  - It is **not USB-HID**. Sources: `~/zinwa-q25-port/dumps/HW_MAP.md`; Droidian wiki "Misc keyboard stuff".
  - This dissolves the "USB is peripheral-only, so the keyboard can't enumerate" tension recorded in `project_zinwa_q25_ufs_module_initramfs.md`.
- **Correction to a memory claim:**
  - Mesa's kmsro display list has **no `simpledrm`** (but does have `mediatek`). Source: mesa `src/gallium/targets/dril/meson.build`.
  - So "Panfrost render + simpledrm scanout via kmsro", as stated in `project_zinwa_q25_live_hw_forensics.md`, does **not** exist.
  - Until mtk-drm works, Marathon can only run on simpledrm with **software GL** (kms_swrast/llvmpipe).
- **Recovery-safety alarm:** none of the recovery blobs that memory references could be found anywhere on disk. I searched `/` for:
  - `scratchpad/brom-recovery/head-r5.img`
  - `userdata-head-fixed.img`
  - `gpt-primary.bin`
  - the stock `lk` dump
  - `gimme-uboot.py`
  
  The old session scratchpads are gone.
  - Both lk slots hold our U-Boot (memory, 2026-07-19), so **no stock LK is on the device**.
  - The only images left are the two U-Boot lk images in `~/zinwa-q25-port/uboot-build/` and the kernel APKs r0–r6 in `~/.local/var/pmbootstrap-work/packages/edge/aarch64/`.
  - The Q25 aports in `~/pmaports-upstream/device/testing/{device,linux-postmarketos}-mediatek-g99/` are **untracked (`??`) in git** and could be lost just as easily.
  - **Step 0 is backups.**

---

## 1. Upstream state (Nura wiki + linked trees)

Sources:
- https://wiki.nura.eco/wiki/Zinwa_Q25_(zinwa-q25). Fetched as raw wikitext with `curl -A curl/8.0 …&action=raw`, because WebFetch hits the Anubis wall. Last content edit was 2026-09-03; the 09-27 edit is only the bot rename postmarketOS→Nura.
- https://wiki.nura.eco/wiki/MediaTek_MT6789_(mediatek-mt6789)
- https://wiki.nura.eco/wiki/MediaTek_Helio_G99_(MT6789/MT8781)

### 1.1 Feature matrix (Q25 page infobox)

| Subsystem | Nura status | Notes |
|---|---|---|
| Booting / flashing / internal storage | Y / Y / Y | UFS |
| Screen | P | simple-framebuffer from U-Boot EFI GOP only (SoC page: "Only simple-framebuffer for now") |
| Touch | P | no touch node in ellyq's public Q25 DTS; the status is unverifiable from code |
| Keyboard | P | no keyboard node in the public DTS. The only keys are `mediatek,mt6358-keys` (power + vol-up) |
| Battery | P | public kernel config has `CHARGER_BQ256XX` and `GENERIC_ADC_BATTERY` off; no charger node |
| 3D / GPU | blank | SoC page: GPU = Y (panfrost "Add MT6789 GPU" + DVFS are in ellyq's tree), but the Q25 DTS doesn't enable `&gpu` |
| Audio, camera, flash, wifi, BT, GPS, NFC, calls, SMS, data, FDE, OTG, USB-net, SD | blank | SoC page: audio N, video N, wifi N, BT N, modem N, GPS N, camera N, **suspend N** |
| SMP / USB | SoC page | "Only 6 cores are working" (our July sweep saw 8). USB device and host each work, **dual-role broken** |
| Thermal / pinctrl / i2c / spi / uart | Y | |
| U-Boot | Y (primary + secondary, mainline P, screen Y, USB host/peripheral P, SD N) | |

### 1.2 Bits it uses

- **pmaports MR !8365.** https://gitlab.postmarketos.org/postmarketOS/pmaports/-/merge_requests/8365
  - Author: ellyq (Alicja Michalska); co-maintainer LongnoseRob. State: opened. Labels: `porting`, `status::mr-stale`.
  - Commits: 2026-04-26 (two) plus a 2026-09-08 merge-from-main. No new content since April.
  - It ships a generic `device-mediatek-g99`:
    - deviceinfo: `deviceinfo_drm="true"`, `rootfs_image_sector_size="4096"`, `boot_filesystem="fat32"`, `flash_method="mtkclient"`
    - depends on `systemd-boot` and `unl0kr-fbforcerefresh`
    - cmdline: `clk_ignore_unused regulator_ignore_unused keep_bootcon earlycon=uart8250,mmio32,0x11002000,921600n1`
  - It ships `linux-postmarketos-mediatek-g99` 7.0, which tracks the **moving** `master` tarball of ellyq's tree, built with LLVM=1 into a ZBOOT `linux.efi`.
  - Its config still has `USB_MUSB_MEDIATEK`, `DRM_MEDIATEK`, `PHY_MTK_MIPI_DSI`, `MFD_RT4831` and `MEDIATEK_MT6359_AUXADC` unset, and `PSTORE_RAM=m`. That means **upstream has no working USB gadget**; our two-symbol fix (`project_zinwa_q25_usb_shell.md`) was never upstreamed.
- **Kernel tree.** https://gitlab.postmarketos.org/ellyq/mtk_g99-mainline (master; last activity 2026-06-06).
  - It is v7.0 plus about 22 MT6789 commits: clk + FHCTL, pinctrl, pwrap, i2c, smi, iommu bindings, cmdq, cpufreq-hw, dvfsrc, EMI interconnect, regulator-coupler, pwm-disp, tphy fix, panfrost MT6789 + DVFS, the mt6789.dtsi, vicky, and `978b8b67` "Add initial devicetree for Zinwa Q25".
  - That Q25 DTS is **`mt8781-zinwa-q25.dts`**. It enables:
    - simplefb @0xff97c000, stride (720+16)*4
    - pwrap + MT6366 regulators, RTC, keys
    - usb2 `dr_mode="peripheral"` + u2phy
    - ufs + ufsphy
    - mmc1 (SD)
    - uart0
  - It has no touch, keyboard, charger, GPU, display or memory/ramoops nodes.
  - It carries **no pm-domain driver and no mtk-drm MT6789 support.**
- **Richer sibling tree.** https://github.com/linux-mediatek/linux branches `mt6789-next` (2025-08-26), `adomerle/mt6789-next`, `adomerle/mt6789-sound` and `adomerle/mt6789-whar`. In addition to the above it contains:
  - `a2a96be9` pmdomains MT6789 SPM: `drivers/pmdomain/mediatek/mt6789-pm-domains.h`, 203 lines. Domains: md, conn, mfg0–3, isp, ipe, vdec, venc, **disp**, audio, cam, cam_rawa/b. mfg uses `KEEP_DEFAULT_OFF | DOMAIN_SUPPLY`.
  - `880bc1cb` [WIP] drm/mediatek MT6789: `mt6789-mmsys.h` (+71), mtk-mutex (+44), mtk_drm_drv, mtk_dsi, mtk_disp_rdma, and +195 lines in the dtsi.
  - `62de3871` "drm: Route testing", `3e6c84ec` "mutex: Defer when is not ready", `a332e912` "dsi: Register DSI host after preparing everything", `2287d270` MT6789 IOMMU, and `a3a7d983` "HACK: Disable iommu for now".
  - `609b2c59` LVTS thermal MT6789 and the cpufreq-hw MT6789 series.
  - `996ec481` "sound wip".
  - emerald DTS: `&gpu` okay with `mfg0/mfg1 domain-supply`, `&dsi0` **still disabled**. So nobody has a confirmed native DSI display on MT6789. Panfrost render-only works there.
- **U-Boot.** https://github.com/JamiKettunen/u-boot-mt6789/tree/q25 (last commit `11b7b36c`, 2026-04-14).
  - The wiki now tells users to add `CONFIG_BLKMAP=y` / `CONFIG_CMD_BLKMAP=y`. That is our finding from `project_zinwa_q25_uboot_blkmap.md`; it is documented but still not in the defconfig.
  - Packaging: byte-patch `lk.img` with xxd/sed, then liblk + `gimme-uboot.py`, then `fastboot flash lk_a/lk_b` from **stock LK fastboot** (Power + Vol+).
- **Install path on the wiki:** `pmbootstrap init` (mediatek / g99, X11 UI recommended), then `pmbootstrap install/export`, then `antumbra --da DA_BR.bin --pl preloader_q20_v12_factory.bin dl userdata mediatek-g99.img`. The rootfs is a nested 4096-byte-sector GPT inside `userdata`, which U-Boot `blkmap`s.
- **Halium alternative.** https://github.com/JamiKettunen/droidian-zinwa-q25 plus its wiki (pushed 2026-01-19). Status as of the 20260117 release:
  - Works: display, touch, trackpad, wifi, cellular data, SMS.
  - Broken or limited:
    - call audio (pulseaudio crash), MMS, hotspot;
    - 3.5 mm needs a replug;
    - backlight on test units (ocp2131 vs production rt4831a);
    - some sym combos eaten by the closed `bbqX0kbd.ko`;
    - USB-MTP;
    - **GPU: Firefox/WebGL software-only** (libhybris libGLESv2 under seccomp);
    - Phosh crashes and slow boot.
  - Kernel: GKI 5.10 (`deathmist/kernel-android-common common-android12-5.10-droidian`), built via `deathmist/halium-gki q25-droidian`; config changes are constrained by the KMI.

---

## 2. Marathon's July 2026 attempt vs upstream: what is resolved

Marathon's July attempt went **further than upstream** on every axis except "nobody has native DSI yet":

| Marathon root cause (memory file) | Upstream status now |
|---|---|
| UFS nodes disabled in DTB → no storage (`project_zinwa_q25_first_boot.md`) | **Resolved upstream**: `978b8b67` enables `&ufs`/`&ufsphy` |
| musb `usb@11200000` disabled / no `dr_mode` (`project_zinwa_q25_usb_dtb_disabled.md`) | **Resolved upstream in DT** (`&usb2` peripheral). **Not resolved** in config: `USB_MUSB_MEDIATEK` + `USB_INVENTRA_DMA` still off in the MR, so upstream images get no gadget |
| U-Boot lacks `CONFIG_BLKMAP` (`project_zinwa_q25_uboot_blkmap.md`) | Documented on the wiki, still missing from defconfig |
| UFS host modules not in initramfs (`project_zinwa_q25_ufs_module_initramfs.md`) | Not resolved: the MR still lists the wrong name `ufshcd-platform` |
| 120 s `udevadm settle` + 31 s mtk-wdt (`project_zinwa_q25_upstream_port.md`) | Not resolved upstream |
| mtk-drm "modeset hang" → really disabled disp nodes (`project_zinwa_q25_mtkdrm_disabled_dtb.md`) | Upstream doesn't attempt mtk-drm at all |
| No MT6789 pm-domains → disp/panfrost −110 (`project_zinwa_q25_mtk_pmdomain_gap.md`); our 0002 hard-crashes (`project_zinwa_q25_ufs_module_initramfs.md`) | **Resolvable now**: cherry-pick `linux-mediatek/linux@a2a96be9` (proven for GPU on emerald) |
| DSI 518→652 Mbit/s roll (`project_zinwa_q25_display_652_fix.md`) | Ours only; keep it (`panel-zinwa-q20-hd720.c`, mode.clock 54334) |
| Charger never enabled: UPM6922 = BQ25601 on i2c5@0x6b (`project_zinwa_q25_battery_blackout.md`) | Ours only (0003 patch + DTS); validated booted-charging on 2026-07-17. **Not a brownout story**: per `feedback_q25_no_brownout.md`, treat crashes as real software faults |
| Fuel gauge garbage (adc-battery uncalibrated) | Open everywhere |
| Touch rmi4 −6 (no power/reset wired) (`project_zinwa_q25_live_hw_forensics.md`) | Upstream has no touch node; still open |
| Keyboard absent | Upstream absent. **Corrected**: I²C bbqX0kbd@0x1f, so no USB host needed |
| RAM shows ~1.7 GB (`project_zinwa_q25_halium_gki_path.md`) | **New root cause**: U-Boot `dram_init()` clamps to 2 GB (§0). Same code upstream |
| Always-fastboot U-Boot falls through (`project_zinwa_q25_uboot_always_fastboot.md`) | Open. U-Boot USB gadget init fails at bootcmd time |
| No ramoops (`project_zinwa_q25_ufs_module_initramfs.md`, r6 staged) | Upstream has `PSTORE_RAM=m` and no region. Ours (r6) is unvalidated |

The local work sits in `~/pmaports-upstream/device/testing/` (untracked):
- the kernel aport is at pkgrel 6, carrying the Q25 DTS, `0001-drm-mediatek-add-mt6789-display-support.patch`, `0003-power-supply-bq256xx…`, `panel-zinwa-q20-hd720.c`, the cmdline blacklist and `nowatchdog`;
- 0002 is dropped;
- the device package is at r1, with `modules-initfs` fixed.

---

## 3. Recommended path: mainline. Halium only as a hardware reference.

What Marathon needs, and how each path delivers it:

| Need | Mainline (ellyq + mt6789-next + Marathon patches) | Halium/GKI (Droidian base) |
|---|---|---|
| GLES2/3 for Qt Quick compositor | Panfrost G57 (Mesa ≥ 23 GLES 3.1; Marathon's Mesa already builds `panfrost`, per pipeline patch 0001). Render-only works on emerald. **Scanout needs mtk-drm** (kmsro has `mediatek`, not `simpledrm`) | libhybris + mali blob. Droidian itself can't get GL into sandboxed apps; Qt 6 has no hwcomposer QPA |
| DRM/KMS display | simpledrm today (KMS atomic, software). mtk-drm MT6789 is WIP upstream; ours plus adomerle's give two independent starts | KMS exists, but the hwcomposer HAL owns DRM master |
| Compositor model (dmabuf v4, in-process) | Native; same as L5/Pi (`project_dmabuf_v4_etnaviv_solved.md`) | Android gralloc buffers; Marathon's dmabuf/QtWayland path doesn't apply |
| Touch | rmi4 (mainline) after DT power/reset fix | works |
| Physical keyboard + trackpad | bbqX0kbd out-of-tree GPL driver (wallComputer/bbqX0kbd_driver) on I²C 0x1f | works (closed driver) |
| Wifi for development | **none** (connsys/gen4m, no mainline driver). Use USB-NCM + host NAT (proven 2026-07-14) | works |
| Battery/charging (critical) | charging proven (bq25601); gauge needs calibration | works |
| Suspend | SoC: N. Marathon Doze (display-off + freezer) without S3/s2idle at first | Android-ish |
| Build pipeline | pmOS/duranium/mkosi, same as other targets | separate Debian distro; out of `build-image.sh` |

**Why mainline:**
1. GPU-accelerated display is "the whole game" (user decision, 2026-07-13, `project_zinwa_q25_lineage_source.md`). Halium doesn't give Marathon the GPU either.
2. Marathon is musl/Mesa/dmabuf-v4 end to end. Halium would mean a second OS base, a new Qt 6 platform plugin and a different buffer model, all for one device. It also contradicts `project_silica_keel_direction.md` and the single-pipeline philosophy.
3. The mainline blockers that ate July now have concrete answers:
   - pm-domains → adomerle's driver;
   - display → his WIP drm plus our panel and DT;
   - flashing → the network-dd loop and fixing U-Boot fastboot/UMS;
   - RAM → the U-Boot clamp.

**What mainline costs:** wifi, BT, modem, GPS, NFC and camera are effectively **out of scope**. Audio is a stretch goal (adomerle sound WIP). If radios matter more than GPU, the only realistic answer is Halium, at the price of everything in the right-hand column. Patrick should make that call explicitly.

---

## 4. Step list to "fully working" (mainline), mapped onto the Marathon pipeline

### Phase 0: Safety and backups (before any flash). Mostly automatable once the device is reachable.

1. **Commit the local aports.** Copy `~/pmaports-upstream/device/testing/{device,linux-postmarketos}-mediatek-g99/` into the repo as the new Marathon aports (Phase 2), so they stop being untracked.
2. **Full partition backup** over the proven network path. Boot to the pmOS initramfs debug shell (172.16.42.1:23), run `modprobe ufs-mediatek`, then `dd if=/dev/disk/by-partlabel/<p> | nc`. Back up every partition **except `userdata`**, with priority on:
   - `nvram`, `nvdata`, `nvcfg`, `protect1`, `protect2`, `persist`, `proinfo` (**IMEI/calibration: irreplaceable**)
   - `seccfg`, `md1img_*`, `vbmeta*`, `boot/vendor_boot/dtbo_*`, `tee*`, `gz*`
   - the preloader (`/dev/block/mapper/pl_a` was the Android path; on Linux it lives in the UFS boot LUNs `sda`/`sdb`)
   - the primary/backup GPT of `sdc`
   
   Then md5 everything and store it outside scratch at `~/zinwa-q25-port/backup/<date>/`.
3. **Recover a stock LK.** Get the Q25 stock firmware: the Zinwa OTA, the LineageOS 23 Q25 build (`android_device_xelex_Q25`), or `asmtronic/Zinwa-Q25-Guide`. It provides a stock `lk.img`, `preloader_q20_v12_factory.bin` and the `DA_BR.bin` the wiki's antumbra command needs. Store them with the backup. Put stock LK back on **one** slot (`lk_b`) so stock fastboot (Power + Vol+) exists as a recovery path again, then retest that `lk_a` U-Boot still boots.
4. Re-create the recovery tooling and keep it in the repo or `~/zinwa-q25-port`, not in scratch: `gimme-uboot.py`, `dbgcmd.py`, `acmrun.sh`, `flash-uboot.sh`.

### Phase 1: Bootloader (U-Boot fork, Marathon-owned)

Package this as `packaging/packages/u-boot-zinwa-q25-marathon`, the same way PinePhone has `u-boot-pinephone-marathon`.

1. Source: JamiKettunen `u-boot-mt6789@q25`, pinned to a SHA. Marathon patches:
   - a. `CONFIG_BLKMAP=y` (+ `CMD_BLKMAP`).
   - b. **RAM fix.** Report the full 12 GB to EFI:
     - remove the `SZ_2G` clamp in `dram_init`, extend `vicky_mem_map` to cover `0x40000000–0x3_40000000`;
     - keep U-Boot's own relocation low with `board_get_usable_ram_top()` (the reason for the "things break" note);
     - verify the bank layout first. The DT says `0x3_0000_0000` bytes from `0x4000_0000`, but carveouts and the preloader-reported DRAM map must agree (see §5).
   - c. Make fastboot or UMS reachable without buttons:
     - first debug why `fastboot usb 0` returns at bootcmd time, using a `serial_gadget` (usbacm) console build, as `project_zinwa_q25_uboot_always_fastboot.md` suggests;
     - then use a **timed** bootcmd ("fastboot for 5 s, then bootefi"), or a flag file on the ESP that selects `ums 0 blkmap 0`. UMS lets the host `dd` the whole nested disk directly, which is the cleanest flash path.
   - d. Disable host signing tools (`TOOLS_KWBIMAGE`, `TOOLS_LIBCRYPTO`) for Fedora OpenSSL 3, per the recipe in memory.
2. Artifact: `u-boot-lk-q25.img` (lk container with certs, via liblk/gimme-uboot from the stock `lk.img`). Flash **lk_a only**; keep lk_b stock (Phase 0.3).

### Phase 2: Kernel and device aports (in-repo, synced into pmaports by pipeline patch 0013)

The pinned duranium pmaports has **no** `mediatek-g99` aport (subagent check of `~/.cache/marathon-build/duranium` pmaports `device/testing`), so everything must be Marathon-owned.

1. **`packaging/packages/linux-postmarketos-mediatek-g99-marathon`.**
   - Fork the local pkgrel-6 aport. Pin `_commit` to an immutable ellyq SHA (`978b8b67`) and use the commit-archive URL; the moving-master sha512 drift is documented in `project_zinwa_q25_port.md`.
   - Patch stack, in order:
     1. **pm-domains**: `linux-mediatek@a2a96be9` (+ its dt-binding header), replacing our 0002. Test boot-inert first: no consumers, `pd_ignore_unused`.
     2. **mtk-drm MT6789**: rebase onto `880bc1cb` + `3e6c84ec` + `a332e912` + `62de3871`, plus the IOMMU `2287d270` (or keep the `a3a7d983` iommu-off hack initially). Merge it with our `0001` (mt8186-routing reuse). Prefer adomerle's dedicated `mt6789-mmsys.h` routing table.
     3. `panel-zinwa-q20-hd720.c` (652 Mbit/s mode, power sequence from HW_MAP).
     4. `0003` bq256xx charge-enable.
     5. **bbqX0kbd** keyboard + trackpad driver (wallComputer/bbqX0kbd_driver, GPL) as an in-tree `drivers/input/keyboard/` patch.
     6. LVTS thermal `609b2c59` + `7df17450`.
     7. Optional: adomerle sound WIP `996ec481` (Phase 5).
   - Config deltas on top of the local config:
     - display/GPU: `DRM_MEDIATEK=m`, `DRM_MEDIATEK_DSI`, `PHY_MTK_MIPI_DSI=m`, `MTK_MMSYS=m` (built-in mmsys wedged PID1 in iteration 2), `DRM_PANFROST=m`, `DRM_PANEL_ZINWA_Q20_HD720=m`;
     - USB gadget: `USB_MUSB_MEDIATEK=y`, `USB_INVENTRA_DMA=y`, `USB_CONFIGFS_NCM/ACM`;
     - power: `CHARGER_BQ256XX=y`, `GENERIC_ADC_BATTERY=y`, `MEDIATEK_MT6359_AUXADC=y`;
     - backlight: `MFD_RT4831=m`, `BACKLIGHT_RT4831=m`, `REGULATOR_RT4831=m` (production units; ocp2131 = bias only);
     - crash capture: `PSTORE_RAM=y`, `PSTORE_CONSOLE=y`;
     - thermal: `MTK_LVTS_THERMAL`;
     - keyboard: `KEYBOARD_BBQX0KBD`;
     - swap: `ZRAM`;
     - Marathon baseline: cgroup freezer and the PSI and other options the L5 kernel uses (diff against `linux-*-marathon` configs).
   - **DTS**: reconcile ours (`mt6789-zinwa-q25.dts`, compatible `"zinwa,q25","mediatek,mt6789"`) with upstream's `mt8781-zinwa-q25.dts`. Pick **one** name and keep compatible `"zinwa,q25"` so it matches U-Boot's DT (needed for UKI `.dtbauto` selection). Keep from ours:
     - ufs/usb okay;
     - charger@6b on i2c5 + simple-battery (4.44 V, 3000 mAh, OCV table from the DTBO battery profile in `dumps/dtb/dtbo_00.dts`);
     - auxadc + adc-battery (fix the channel/scale: currently reads 811 V or −354553472);
     - ramoops in the free gap after `scp@bfa00000`;
     - touch: rmi4 at i2c0@0x67, irq GPIO9, plus a `regulator-fixed` on GPIO27 as `vdd-supply` and a GPIO152 reset hog;
     - keyboard: bbqX0kbd at i2c 0x1f, irq GPIO12, power GPIOs 159/157/158 as fixed regulators;
     - display pipeline nodes + panel@0 + panel-bias (ocp2131 GPIO84 / rt4831) + backlight;
     - `&gpu` with the mt6789-next mfg domain-supply pattern from emerald (`&mfg0 domain-supply=<&mt6366_vgpu_reg>`, `&mfg1 domain-supply=<&mt6366_vsram_gpu_reg>`).
     
     Do **not** add MT6366 regulator `regulator-boot-on`/always-on changes beyond what upstream has. That corrupted the display rail in iteration 1 (`project_zinwa_q25_usb_shell.md` GOTCHA 2); upstream's regulator block boots, so start from it.
2. **`packaging/packages/device-zinwa-q25`.** This is the pmOS device package. The manifest's `id` must equal the pmOS device name; the generic `mediatek-g99` name doesn't fit Marathon's `<vendor>-<codename>` contract.
   - Copy `device-mediatek-g99` and change the codename to `zinwa-q25`.
   - `modules-initfs`: `ufshcd-core ufshcd-pltfrm ufs-mediatek rmi-core rmi-i2c` + bbqX0kbd + panel/drm only once it's stable.
   - `deviceinfo_rootfs_image_sector_size="4096"`.
   - kernel-cmdline: `clk_ignore_unused regulator_ignore_unused pd_ignore_unused nowatchdog`. Keep the `modprobe.blacklist=` for the display stack **until Phase 4 passes**, then drop it.
   - Initramfs fix: `udevadm settle --timeout=10` (`project_zinwa_q25_upstream_port.md` fix #1). Upstream it to postmarketos-initramfs or carry it in the device package.
3. **`packaging/packages/device-zinwa-q25-marathon`** (overlay; template: HackberryPi + PinePhone):
   - `depends`: `device-zinwa-q25 linux-postmarketos-mediatek-g99-marathon marathon-shell marathon-base-config marathon-plymouth-theme mesa-dri-gallium` (panfrost + kmsro) and `keyd` (optional, for layer and sym handling as in Droidian's `q25-qwerty-en.conf`).
   - `device-profile.conf` (generated): see the manifest `[profile]` below.
   - A greetd drop-in (like PinePhone's) or the plain `marathon-shell-session` (like Pi5/HackberryPi, DPI from the profile).
   - logind: `HandlePowerKey=ignore`.
   - A udev rule giving the bbqX0kbd trackpad `ID_INPUT_POINTER`, and keyboard hwdb for the call/end/back keys.
   - The USB gadget service (ncm + acm @172.16.42.1), since there's no wifi. This is the dev lifeline. Model it on the `marathon-usb-gadget.service` that worked on 2026-07-14 (`project_zinwa_q25_display_hang_and_gadget.md`).
   - `modules-load.d` for the charger, adc-battery and rt4831.
   - `.post-install` greetd symlink as on PinePhone.
4. **`devices/zinwa/q25/device.toml`** (schema: `devices/device.schema.json`):
   - `id="zinwa-q25"`, `soc="mt6789"`, `status="bring-up"`, `package="device-zinwa-q25-marathon"`
   - `[build]` target `zinwa-q25`, wrapper `scripts/build-zinwa-q25-image.sh`, flash `scripts/flash/flash-zinwa-q25.sh`, `bootloader="systemd-boot"`
   - `[boot]` `method="uefi"` (U-Boot EFI is BL33, lk_a), `partition_table="gpt"`, loader `u-boot-zinwa-q25-marathon`
   - `[kernel]` package and version from the new aport
   - `[display]` `interface="dsi"`, 720×720, `diagonal_in=3.5`, `depth_bits=8`, `scale_dpi=254` (start equal to HackberryPi, the same 720×720 + keyboard UX; native ≈295 per `docs/NATIVE_APP_SCALE.md:99`, validate visually), `panel="zinwa,q20-hd720"`
   - `[input]` touch "Synaptics S2716B (rmi4-i2c)", keyboard "RP2040 i2c_puppet QWERTY + trackpad (bbqX0kbd, I²C 0x1f)"
   - `[hardware]` modem "none (CCCI, no mainline)", gps "none", wifi "none (connsys, no mainline)", sensors "none", `ram_mb=12288`, battery "3000 mAh BQ25601 + adc-battery"
   - `[runtime]` `runner_pool=1` (12 GB)
   - `[profile]`: `force_dpi=254`, `panel_dpi=254`, `wake_on_key=true`, `screen_timeout_ms` per taste, `doze_dpms=false` until mtk-drm (simpledrm can't DPMS), `wifi_powersave=false`, `cpu_governor="ondemand"` (or schedutil; measure), `brightness_floor` tuned once the backlight class exists
5. **`socs/mt6789.toml`** (schema `socs/soc.schema.json`):
   - `display_controller="mediatek-drm (simpledrm interim)"`
   - `[gpu] name="Mali-G57 MC2"`, `render_node="/dev/dri/renderD128"`
   - `stacks.mesa-panfrost = {driver="panfrost", gles_max="3.1", msaa=false}` (enable later after measuring), plus `stacks.llvmpipe` for the interim
   - `[profile] gpu_stack="llvmpipe"` until Phase 4, then `mesa-panfrost`
   - **Extend the closed `gpu_stack` enum** in `devices/device.schema.json` with `mesa-panfrost`, and check that `shell/src/managers/deviceprofile.cpp` accepts it.
6. **Pipeline patch `0037-zinwa-q25-uefi-4k-sectors.patch`** in `packaging/pipeline-patches/` (+ README index). It changes duranium:
   - `scripts/mkosi-configure.py`: `if device == "zinwa-q25":` set `SectorSize=4096`. The global value is `SectorSize=512` (`mkosi.conf:62`), but U-Boot `blkmap` over 4 KiB UFS needs a 4096-byte nested GPT, as proven by `project_zinwa_q25_uboot_blkmap.md`. Keep `Bootloader=systemd-boot` (the default; no UKI switch like PinePhone's 0022).
   - Keep the stock `mkosi.repart` (vfat ESP `pmOS_boot` + ext4 `pmOS_root`) and grow root on first boot. The Pi has root-grow 0033; check that duranium's grow path works inside the nested GPT (`resize_root_partition` or systemd-repart on a loop device of userdata).
   - DTB delivery: make sure `Devicetrees=` picks only the Q25 DTB, or use `.dtbauto` with compatible `zinwa,q25` (it must match the DT U-Boot passes). Otherwise systemd-stub keeps U-Boot's vicky-derived DT, which is wrong for Linux.
   - `scripts/build-image.sh` post-bake `case`: `zinwa-q25)` emits:
     - `userdata.img` (Android-sparse via `img2simg`, for fastboot/antumbra);
     - the raw `.raw` for UMS/dd;
     - an `esp.raw` / UKI-only artifact for fast kernel-only updates.
7. **Scripts:**
   - `scripts/build-zinwa-q25-image.sh` (wrapper: build the u-boot/kernel/device forks, then `build-image.sh zinwa-q25`).
   - `scripts/flash/flash-zinwa-q25.sh` with modes, in this preference order:
     - `--net-dd` (initramfs debug shell + HTTP + dd + md5 readback, per `project_zinwa_q25_uboot_always_fastboot.md`);
     - `--ums` (U-Boot UMS + host dd);
     - `--fastboot` (once fixed);
     - `--brom` (mtkclient/antumbra last resort; refuses to run unless ModemManager is stopped and backups exist).
8. Run `tools/devices/devices.py check` (Devices_Check ctest) after every manifest or profile change, and bump pkgrel when the `device-profile.conf` sha changes.

### Phase 3: First light (software). Goal: Marathon visible on the panel on simpledrm.

- Boot the image and confirm sshd over NCM. Then:
  - `marathon-shell-session` with eglfs_kms on simpledrm card0 and `kms_swrast`.
  - The panel works under simpledrm: video mode, writes to fb0 show up immediately (`project_zinwa_q25_live_hw_forensics.md`).
  - Upstream's device package pulls `unl0kr-fbforcerefresh`, so watch for stale frames.
- Fix the simplefb geometry/format so Qt gets the right pitch and pixel format.
  - Conflicting data: our memory says 24 bpp at a 2880 stride, panel rotated 90° (`project_zinwa_q25_panel_proven_working.md`). Upstream DTS says a8r8g8b8 with stride (720+16)*4.
  - Validate with test patterns plus a photo (`feedback_visual_validation.md`, `reference_device_snap.md`).
  - If the panel really is rotated, Marathon has **no rotation key**. Add DT `rotation`, which DRM exposes as the panel-orientation property, or add a DeviceProfile key. Note that simplefb can't rotate.

### Phase 4: GPU and native display (the core work)

1. pm-domains boot-inert, then `modprobe panfrost`. Expect `panfrost 13000000.gpu` plus a render node. Run Mesa `eglinfo` / `kmscube --device /dev/dri/renderD128` offscreen (render-only).
2. Unbind fbcon and simpledrm **before** modprobing the display stack. This removes the July "power DISP under live LK scanout" corruption mechanism (`project_zinwa_q25_mtk_pmdomain_gap.md`).
3. Then modprobe `phy-mtk-mipi-dsi`, `mtk-mmsys`, `mtk-mutex`, `mediatek-drm`, the panel and panfrost, with dmesg and pstore watched. Success looks like:
   - `Initialized mediatek`, `DSI-1` connector connected 720×720@60;
   - `kmscube` on card0;
   - `eglinfo` showing the panfrost renderer through the `mediatek` kmsro.
4. Remove the blacklist from the cmdline and let the stack load at boot. Then switch the profile to `gpu_stack=mesa-panfrost`, `gles_level=3.1`, `doze_dpms=true`, and re-run perf and visual checks.

### Phase 5: Platform completeness

- **Battery:** gauge calibration (auxadc scale, OCV table) and upower. Overnight drain test (cable unplugged; read the journald logs afterwards).
- **Thermal and cpufreq:** LVTS zones in `/sys/class/thermal`, cpufreq-hw policies, and CPU supplies (all 8 currently say "dummy regulator").
- **Backlight:** rt4831 `/sys/class/backlight`, Marathon brightness slider, brightness floor.
- **Suspend:**
  - First target is Marathon Doze: display-off via mtk-drm DPMS + cgroup freezer, like L5 (`project_doze_dpms_parked.md`, `project_standby_power_floor.md`).
  - Then try `s2idle` with wake on power key and keyboard IRQ (`WAKE_ON_KEY`). Pass/fail is power draw from the bq256xx/gauge and a clean wake ×50.
- **Audio** (stretch): adomerle sound WIP + MT6366 codec.
- **Vibrator:** `regulator-vibrator` (differs from the L5's evdev).
- **LEDs:** GPIO 46/48/49.
- Wifi, BT, modem, GPS, NFC and camera are out of scope on mainline (§3), unless Patrick funds a connsys driver port.

### Phase 6: Promote to "working"

- Gesture model on 720×720 with the keyboard: `Constants.isSquareScreen` / `compactLayout` already exist; HackberryPi is the reference.
- Hub, OOBE, lock and PIN with the hardware keyboard.
- `marathon` CLI / D-Bus driving over NCM (`reference_dbus_device_driving.md`).
- Change the manifest to `status="working"`.

### Flashing procedure and safety rules (from memory, consolidated)

Preferred: **network dd from the pmOS initramfs debug shell** (`project_zinwa_q25_uboot_always_fastboot.md`):
1. Host: `ip addr add 172.16.42.2/24 dev <enu*>; ip link set up` (the host loses this every session), then `python3 -m http.server 8088 --bind 172.16.42.2` as its own background task.
2. Device, over telnet 172.16.42.1:23:
   - touch telnetd **exactly once** per boot, and use the raw-socket driver;
   - `modprobe ufs-mediatek`;
   - `wget` the image, check its `md5sum`;
   - `dd of=/dev/disk/by-partlabel/<p> bs=1M; sync`, then read back and compare md5;
   - `reboot -f` in the foreground.
   - Long jobs run detached: `setsid sh /tmp/x.sh >log 2>&1 </dev/null &`.
3. Never Ctrl-C/Ctrl-D the ACM shell, and keep `/dev/ttyACM0` open once with `-hupcl clocal` (`project_zinwa_q25_acm_observability.md`).

BROM, the last-resort floor (`project_zinwa_q25_uboot_always_fastboot.md`, `project_zinwa_q25_ufs_module_initramfs.md`, `project_zinwa_q25_mtk_pmdomain_gap.md`):
- `systemctl stop ModemManager` first; it steals the MTK VCOM.
- Kill any stale `mtk` process and clear USB (phone OFF and unplugged, so no 0e8d device is present).
- Start `mtk w …` polling **before** connecting: phone OFF, hold a volume key (Vol-Up+Vol-Dn also works), plug USB, then `0e8d:0003`.
- **Never run `mtk ro`.** This DA doesn't support flash read, and a failed read poisons the session. Use `mtk rs <sector> <count>` if a read is unavoidable.
- Confirm the write reaches **VERIFY 100.0%** (a silent ~1% truncation once cost hours).
- Never write the preloader, nvram, nvdata, protect*, seccfg or md1img.
- Don't reflash the 244 MiB userdata "head" casually: it rewrites the nested GPT and reverts root-partition growth (`project_zinwa_q25_usb_shell.md`). Prefer full-image or ESP-only updates.

General rules:
- Do not attribute crashes to power or brownout. Use pstore/ramoops, `journalctl --list-boots` (journald is persistent) and patch bisection (`feedback_q25_no_brownout.md`).
- Built-in display drivers that hang give a silent brick. Build display and GPU as **modules**, keep them blacklisted until proven, and keep a known-good `linux.efi`/UKI fallback on the ESP.
- Never deploy a freshly compiled DTB without checking that `ufs@11270000`, `ufs-phy` and `usb@11200000` are `okay` (brick guard).

### Validation checklist per subsystem (each check driven over SSH unless marked [photo] or [hands])

| Subsystem | Pass criteria |
|---|---|
| Boot | Unattended cold boot to sshd ×10 with no debug-shell; `systemctl --failed` empty apart from known-benign units; `journalctl -b -1` intact |
| RAM | `free -g` ≈ 11+ GB; memtester pass over the high banks; no EFI memmap warnings |
| Storage | ext4 root grown to ~228 GB; fsck clean after `reboot` ×5 |
| USB gadget | NCM + ACM both up after switch_root; NAT internet working (`apk update`) |
| Display (sw) | Marathon lock screen renders with correct format and orientation [photo]; `device-snap.sh` diff against the HackberryPi 720×720 reference |
| GPU | `/dev/dri/renderD128` panfrost; `eglinfo` renderer "Mali-G57 (Panfrost)"; Marathon `GPU_STACK=mesa-panfrost`; switcher/home at a steady 60 fps (no frame drops, like the etnaviv MSAA trap); app clients on dmabuf v4 HW render |
| KMS | `modetest -M mediatek` shows DSI-1 720×720@60; DPMS off/on ×50 without a wedge [photo] |
| Touch | `libinput debug-events` shows a touch device; taps land at the correct coordinates (720×720, no rotation offset) [hands] |
| Keyboard | every key produces the expected keysym in `libinput debug-events`/`keyd monitor`; sym layer, backlight toggle, call/end keys; typing in a Marathon text field [hands] |
| Trackpad | pointer motion and click; maps to Marathon pointer navigation [hands] |
| Charging | `bq256xx-charger online=1 status=Charging` with cable; `Not charging`/`Discharging` without; no NULL-deref Oops |
| Battery % | `capacity` monotonic and plausible against voltage; upower shows it; Marathon status bar matches |
| Thermal | `/sys/class/thermal/thermal_zone*` present; throttling under a stress test |
| Backlight | `/sys/class/backlight/*` (rt4831) 0..max; Marathon slider |
| Suspend/Doze | display-off draw (measured via gauge `current_now` or a USB meter [hands]); wake via power key and keyboard ×50 |
| Crash forensics | `echo c > /proc/sysrq-trigger` → watchdog warm reset → `/sys/fs/pstore/console-ramoops-0` present |
| Recovery | re-flash from `--net-dd`, and from `--ums` or `--fastboot` once fixed; BROM documented and tested once |

---

## 5. Risks, unknowns, and who does what

**Risks and unknowns:**
1. **No backups on disk** (§0). Losing `nvram`/`nvdata` means losing the IMEI and calibration permanently. This is the highest priority to fix.
2. **Native DSI on MT6789 is unproven by anyone.** emerald also keeps `dsi0` disabled. Possible failure modes:
   - wrong mmsys routing;
   - IOMMU/larb missing, giving black or garbage scanout (`project_zinwa_q25_mtkdrm_disabled_dtb.md`, residual risk 2);
   - DISP domain power-up while LK is scanning out.
   
   Fallback: stay on simpledrm with software GL. Marathon is usable, but this defeats the GPU-first goal.
3. adomerle's pm-domains is proven for **mfg** on emerald, not for **disp**. The disp domain is not `KEEP_DEFAULT_OFF` in his table, so it may be powered at probe under LK scanout: the exact July corruption. Patch the disp domain to `KEEP_DEFAULT_OFF` if needed.
4. The U-Boot 12 GB fix: the "things break above 2 GB" cause is unknown (relocation, or the MMU map not covering DRAM 4). Validate the DRAM bank layout:
   - Option 1: the DRAM info the preloader passes to BL33.
   - Option 2: the Android `/proc/iomem` from the stock or LineageOS ROM.
   - Option 3: U-Boot `mtest` on the high regions.
5. The fastboot/gadget failure in U-Boot is undiagnosed.
6. The keyboard driver: Zinwa's `bbqX0kbd.ko` is modified and closed. The open wallComputer driver plus i2c_puppet v1.1 firmware may differ in keymap or trackpad protocol. A firmware update path exists (`/proc/firmware_upgrade` equivalent; Droidian wiki).
7. Touch power/reset assumptions (GPIO27/152) come from the vendor DTBO. The vendor uses a non-rmi4 driver (`mtk_touchscreen_hodafonehw`), so S2716B may need F-something quirks.
8. Backlight IC: rt4831a on production, ocp2131 on test units. **Which one Patrick's unit has is unknown.** Probe i2c: rt4831 sits at 0x11.
9. Panel orientation and pixel format conflict (§Phase 3).
10. Suspend is "N" upstream: a possible wake failure or wedge (cf. the L5/PinePhone history).
11. Upstream drift: ellyq's MR is stale, and the two trees (ellyq, linux-mediatek) diverge. Marathon will be carrying a patch stack of roughly 10+ patches, so pin SHAs.
12. The pinned duranium pmaports may lack a recent enough `systemd-boot`/`mkinitfs` behaviour for 4K-sector ESPs. Check mkosi's `SectorSize=4096` support with vfat (the 512 comment in mkosi.conf mentions U-Boot sector-mismatch errors).

**What Patrick must do physically:**
- Keep the phone on a **data-capable** USB-C cable to the host port. Use a wall charger for long charging (OFF + plugged charges at the preloader level).
- Power-cycle when it wedges (hold Power until the backlight dies, then press Power).
- BROM cold-connect if it ever comes to that: phone OFF, hold a volume key, plug USB after `mtk` is already polling.
- If stock LK goes back on lk_b: Power + Vol+ for stock fastboot.
- Provide or approve downloading the stock firmware (lk, preloader, DA).
- Photograph the panel for visual validation; type on the keyboard, use the trackpad and touch for input sign-off.
- Unplugged battery-drain runs, and a USB power meter reading if available.
- Approve `sudo` steps on the host: ModemManager stop, udev rules, NAT/iptables, mtkclient.

**What can be automated:** builds (`build-zinwa-q25-image.sh`), the Devices_Check ctest, network-dd flashing with md5 readback and `reboot -f`, all SSH-side validation in the checklist, pstore and journal harvesting, and the device-snap visual diffs once Marathon renders. The only manual items are physical button presses, cable handling, photos and input sign-off.

---

## Sources

**Web:**
- Nura wiki: Q25 page, generic `mediatek-mt6789` page, SoC page (raw wikitext + history API).
- pmaports MR !8365 (API: metadata, commits, diffs).
- `gitlab.postmarketos.org/ellyq/mtk_g99-mainline` (API: commits, `978b8b67` diff).
- `github.com/linux-mediatek/linux` branches `mt6789-next` and `adomerle/*` (`mt6789-pm-domains.h`, `mt6789-xiaomi-emerald.dts`).
- torvalds/linux @ v7.3-rc7 (no mt6789).
- `github.com/JamiKettunen/u-boot-mt6789@q25`.
- `github.com/JamiKettunen/droidian-zinwa-q25` + wiki.
- Mesa `src/gallium/targets/dril/meson.build` (kmsro list).

**Memory:** every `project_zinwa_q25_*.md` (21 files) + `feedback_q25_no_brownout.md`; `project_device_overlay_refactor.md`, `feedback_visual_validation.md`, `reference_device_snap.md`, `project_doze_dpms_parked.md`.

**Local:**
- `~/zinwa-q25-port/{AUDIT.md,SETUP.md,dumps/HW_MAP.md,dumps/GPU_DISPLAY_PORT_PLAN.md,u-boot-mt6789/arch/arm/mach-mediatek/mt6789/init.c,u-boot-mt6789/arch/arm/dts/mt6789-zinwa-q25.dts}`
- `~/pmaports-upstream/device/testing/{device,linux-postmarketos}-mediatek-g99/`
- `~/.cache/marathon-build/duranium/mkosi.conf`

**Repo:** `docs/DEVICE_OVERLAYS.md`, `docs/DEVICE_SUPPORT.md`, `devices/{pine64/pinephone,hackberrypi/cm5,qemu/aarch64}/device.toml`, `socs/*.toml`, `devices/device.schema.json`, `packaging/packages/device-{pine64-pinephone,hackberrypi-cm5}-marathon/`, `packaging/pipeline-patches/{0022,0029,0032-0035}`, `scripts/build-image.sh`, `shell/src/managers/deviceprofile.cpp`, `shell/qml/core/Constants.qml:52`, `docs/NATIVE_APP_SCALE.md:99`.
