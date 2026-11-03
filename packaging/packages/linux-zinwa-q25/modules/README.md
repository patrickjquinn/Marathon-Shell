Sources of the out-of-tree modules that `linux-zinwa-q25` builds against its own
tree (`build.sh`, run from its APKBUILD) and ships as `q25-kernel-modules`.

| Directory | Modules | Origin |
|---|---|---|
| `md1` | `q25-md1-owner` | Marathon |
| `bt` | `q25-btmtk-stp` | Marathon |
| `audio` | `snd-soc-mt6358`, `snd-soc-mtk-common`, `snd-soc-mt6789-afe`, `q25-mt6366-card`, `q25-mt6358-accdet` | the kernel's `sound/soc/codecs/mt6358.c` plus patches `0002`–`0006` and `sound/soc/mediatek/common`, linux-mediatek/linux `996ec481` (`adomerle/mt6789-sound`) `sound/soc/mediatek/mt6789` plus `0001`, Marathon's `q25/` drivers, and `q25accdet/`, a port of `sound/soc/codecs/mt6358-accdet.c` from LineageOS/android_kernel_xelex_mt6789 `2a873a35` |
| `gnss` | `mtk-connsys-gnss` | Marathon: boots the CONNSYS GNSS DSP, `/dev/gnssN` (feat/q25-gnss-open `bd570bc8`) |
| `haptic` | `q25-haptic` | Marathon's glue for the kernel's `regulator-haptic` |
| `cam-dt` | `q25-cam-dt` | Marathon: applies `camera/q25-camera.dtbo` at runtime |
| `cam-pmic` | `wl2868c-regulator` | Qianhui Xu's "[PATCH v4 2/4] regulator: willsemi,wl2868c" (LKML, 2026-10-31), unmodified |
| `modem` | `ccci_util_lib`, `ccmni`, `ccci_md_all`, `ccci_ccif`, `ccci_dpmaif` | iasnezhkov/android_kernel_ikko_mindone `9cd73c15` `mindone/modules`, the files in `eccci-files.txt`, plus `0001` and `0002` |
| `camera` | `mtk-seninf6s`, `mtk-camsv6s`, `phy-mtk-mipi-csi-2-1`, `videobuf2-*` (the kernel's `drivers/media/common/videobuf2`, which no configured driver selects), and `q25-camera.dtbo`, a runtime overlay for the WL2868C, the front IMX111 on CSI0, the rear S5KJN1 on CSI1, SENINF, CAMSV2 and the CSI PHYs (written to `OUT/firmware`); CAMSV2 takes frames over 4 MiB from the board DT's camera pool (`linux-zinwa-q25`'s `0010`) | gitlab.com/mediatek/aiot/bsp/linux `a246e0c6` (`mtk-v6.6`, Genio 720/MT8189): `drivers/media/platform/mediatek/isp/isp_6s/{seninf,camsv}` and `drivers/phy/mediatek/phy-mtk-mipi-csi-2-1*`, unmodified, plus `0001-mt6789-port.patch`; built as the `media` set; `bindings/` holds Genio's MT8189 DT bindings for reference |
| `wifi` | `connadp`, `btif_drv`, `wmt_drv`, `wmt_chrdev_wifi`, `wlan_drv_gen4m_6789` | iasnezhkov/android_kernel_ikko_mindone `9cd73c15` `mindone/modules`, plus the patches |

`wifi/wmt-files.txt` lists the donor files that form the WMT/BTIF/connadp
tree before `0001`, `0003` and `0004`; `0002` applies to the donor's
`wlan_drv_gen4m_6789` and `wmt_chrdev_wifi` directories.

`MT6789_SOUND=DIR build.sh KSRC KOBJ DONOR OUT` builds all of them; the
kernel APKBUILD fetches the two donor trees (mindone `9cd73c15` and the
mt6789-sound files at `996ec481`) and installs the result under
`/usr/lib/modules/7.0.0-q25/extra/`. Every module carries the kernel's
vermagic because it is built in the same package build.

Everything else the Q25 loads (networking for Deckard, ALSA and ASoC core,
the V4L2 core and the IMX111/S5KJN1 sensors, cfg80211, Bluetooth, rfkill,
SPI, the ICM-42607, MMC5633 and regulator-haptic) is built by
`linux-zinwa-q25` itself.
