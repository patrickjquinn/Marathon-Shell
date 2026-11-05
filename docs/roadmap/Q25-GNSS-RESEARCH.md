# Q25 GNSS research notes

Status: research only, 2026-11-02. Nothing here is built or shipped. How GNSS
is done is decided in `Q25-UPSTREAM-PLAN.md`; this file records the facts that
decision needs.

Option 1 has since been taken up: the DSP boot protocol, firmware layout and
message catalogue are in `docs/hardware/mt6789-gnss.md`, with a driver,
firmware extractor and bring-up plan; the positioning engine is still open.

## Today

- ModemManager reports only `3gpp-lac-ci` location; the MD1 modem has no GNSS
  role on MT6789.
- No GNSS kernel driver is loaded: no `/dev/stpgps*`, `/dev/gps_emi`,
  `/dev/gnss*`; `lsmod` shows only the Wi-Fi/BT CONNSYS set (`connadp`,
  `btif_drv`, `wmt_drv`, `wmt_chrdev_wifi`, `wlan_drv_gen4m_6789`,
  `q25_btmtk_stp`, `q25_conn_pd`).
- The running DT has no `gps` node. It does have `consys_emi@7e000000`
  (5 MiB) in `reserved-memory`, which covers the stock GPS window below.
- GeoClue gets Wi-Fi/IP/cell positions only.

## Hardware

The receiver is the GNSS function of the MT6789 CONNSYS (the same block as
Wi-Fi and Bluetooth, "SOC2_2" in the firmware names), reached through
MediaTek's WMT/STP/BTIF stack. It is not a UART receiver like the MT333x
parts that mainline `drivers/gnss/mtk.c` handles.

Stock DT (`~/zinwa-q25-port/dumps/base-vendor.dts`, `dtb/dtbo_00.dts`):

- `gps@18c00000 { compatible = "mediatek,gps"; emi-region = <0x1d>;
  emi-offset = <0x400000>; emi-size = <0xfffff>; emi-domain-ap = <0>;
  emi-domain-conn = <2>; }`: the GPS shared-memory window is
  consys EMI + 4 MiB, 1 MiB long.
- LNA pinctrl (dtbo fragments 16/17): states `gps_l1_lna_{disable,dsp_ctrl,
  enable}` on GPIO25 and `gps_l5_lna_*` on GPIO87; `dsp_ctrl` is pin function
  2 (the CONNSYS DSP drives the LNA enable), `disable`/`enable` are GPIO
  output low/high. Without the `dsp_ctrl` state the LNA is likely unpowered.

## Stock kernel side

Q25 vendor kernel: LineageOS/android_kernel_xelex_mt6789 `2a873a35`,
`drivers/misc/mediatek/connectivity/gps/gps_stp` (`ro.vendor.gps.chrdev=
gps_drv_stp` in the stock vendor `build.prop`). The donor tree we port Wi-Fi
from (iasnezhkov/android_kernel_ikko_mindone `9cd73c15`, `mindone/modules/
gps_drv_stp`, `gps_pwr`) carries the same code and flags (`MTK_GENERIC_HAL`,
`CONFIG_GPSL5_SUPPORT`, `CONFIG_MTK_GPS_EMI`).

What `gps_drv_stp` does:

- `/dev/stpgps` (L1) and `/dev/stpgps2` (L5): `open` calls
  `mtk_wcn_wmt_func_on(WMTDRV_TYPE_GPS)` and sets the LNA to `dsp_ctrl`;
  `read`/`write` are raw `mtk_wcn_stp_{receive,send}_data(…, GPS_TASK_INDX)`;
  ioctls give chip/firmware versions, co-clock flag, wakelock, WMT assert,
  HW suspend/resume, reset events.
- `/dev/gps_emi`: `ioctl(IOCTL_EMI_MEMORY_INIT)` ioremaps the EMI window above;
  `read` returns up to 0x50000 bytes from it (ADC capture).
- A platform driver on `mediatek,gps` reads the EMI and LNA properties.
- It is a thin pipe: it does not load firmware and does not produce NMEA.

`gps_pwr` (`/dev/gps_pwr`) only relays low-battery throttling events from
connadp's `conn_pwr_*` power-throttling core, which our connadp build leaves
out.

`wmt_drv` as we already build it has `CONFIG_MTK_COMBO_GPS=1` and
`gps_drv_init.o`, so WMT's GPS function on/off path is present.

## Stock userspace

Stock vendor (`q25/audio-bringup/ref/stock-super/vendor_a.img`, inspected
read-only):

- `/vendor/bin/mnld` (needs `libmnl.so`, `libnvram`, `libhidlbase`, sensors
  HIDL, `libcurl`, `libssl`, …), `/vendor/lib64/mt6789/libmnl.so` (7 MB),
  `mtk_agpsd`, `lbs_hidl_service`, AIDL `android.hardware.gnss-service.mediatek`.
- `/vendor/firmware` has no GPS file; only the Wi-Fi/BT/MCU `soc2_2_*` images.
- `mnld` opens `/dev/stpgps`, `/dev/stpgps2`, `/dev/gps_emi`, `/dev/gps_pwr`,
  and keeps state in `/data/vendor/gps/` (EPO/QEPO almanacs, `mtkgps.dat`
  NVRAM-like data); the AIDL HAL talks to it over its own `mnl2hal`/`hal2mnl`
  socket protocol.
- `libmnl.so` exports `mtk_gps_dsp_init`, `mtk_gps_data_input{,2}`,
  `mtk_gps_mnl_run` and embeds DSP images for many chips
  (`BINFO(): MT6877_E1 L5 DSP`, `MT6983_E1 L1 DSP`, …) with a
  `_BootDSP_UART_V2` boot routine.

So on this generation the GNSS is host-based: `libmnl` downloads the DSP
firmware over `/dev/stpgps` itself, the DSP then streams MediaTek's
proprietary binary measurement data, and the positioning engine runs on the
AP inside `libmnl`, which emits NMEA. `/dev/stpgps` never yields NMEA on its
own. (Older public MediaTek trees show the same split: a closed `libmnl`
fed through `mtk_gps_data_input()` with a `mtk_gps_sys_*` porting layer.)

## Prior art

- Mainline `drivers/gnss/mtk.c`: serial MT333x receivers that speak NMEA/PMTK
  themselves. Not applicable to CONNSYS GNSS.
- No open or reverse-engineered MediaTek CONNSYS GNSS (DSP boot or
  measurement protocol) work found, and no mainline/postmarketOS GNSS on
  MT6765/MT6768/MT6789/MT8183-class phones; postmarketOS MediaTek kernels
  (mt6763, mt6768 forks) don't list GNSS.
- Halium-based systems (Ubuntu Touch, Droidian/FuriOS, Sailfish) run the
  vendor `mnld` and GNSS HAL in the Android container and read the HAL over
  binder: Droidian's GeoClue fork has a `hybris-source` built on libgbinder
  (`android.hardware.gnss@1.0` HIDL), Sailfish has
  mer-hybris/geoclue-providers-hybris (GeoClue 1). Out of scope: GNSS must
  work natively with Android never started.
- GeoClue 2 ingests NMEA natively: `[network-nmea] nmea-socket=PATH` reads
  NMEA from a Unix socket without Avahi (the established route for an NMEA
  producer such as gps-share or gpsd's output); `[modem-gps]` is
  ModemManager-only.

## Options

1. Fully open, native. Kernel: a GNSS function on whatever upstream CONNSYS
   driver MT6789 gets, exposed as a mainline `gnss` device (`/dev/gnssN`)
   rather than `/dev/stpgps`; LNA via pinctrl states in the board DT.
   Userspace: reverse-engineer the DSP boot and measurement protocol, source
   the DSP image from the phone's own `libmnl.so` at install time, and compute
   positions with an open engine (e.g. RTKLIB single-point positioning from
   raw measurements plus broadcast ephemeris), feeding GeoClue through
   `nmea-socket`. Most upstreamable; largest and least certain effort, and
   it depends on whether the DSP stream carries navigation-message data.
2. Vendor kernel modules + closed `mnld` run natively (no container).
   `gps_drv_stp` would port like `wmt_drv` (it only needs `wmt_drv`'s STP/WMT
   exports and a `mediatek,gps` DT node; `gps_pwr` needs connadp's
   power-throttling core or a stub). `mnld` is bionic-linked and needs a
   bionic linker plus stock `/system` libs (libhybris-style or a minimal
   chroot), `libnvram`, HIDL sensor libs, and a native replacement for the
   HAL's side of `mnl2hal` to turn its output into NMEA. Proprietary blobs
   would be read from the stock vendor partition at install time, never
   redistributed (as `q25-connsys-firmware` already does). Adds exactly the
   vendor code and userspace hardware workarounds the upstream review
   objects to; a decision for the user, not built.
3. Keep Wi-Fi/cell/IP positioning only until option 1 is feasible.

## Licensing

- `gps_drv_stp`, `gps_pwr`: GPL-2.0 (MediaTek headers), same as the WMT tree.
- `mnld`, `libmnl.so`, `mtk_agpsd`, the GNSS HAL and the DSP images inside
  `libmnl`: MediaTek proprietary; not redistributable. Any use must copy them
  from the user's own stock partitions.
- GeoClue: LGPL-2.1+; Droidian's hybris source: LGPL-2.1.
