Sources of the modules that `packaging/packages/q25-kernel-modules` ships.

| Directory | Modules | Origin |
|---|---|---|
| `keyboard` | `q25-bbq-keys`, `q25-keyboard-led` | Marathon |
| `md1` | `q25-md1-owner` | Marathon |
| `conn-pd` | `q25-conn-pd` | Marathon |
| `imu` | `inv-icm42607`, `inv-icm42607-spi` | torvalds/linux `abf8c334` `drivers/iio/imu/inv_icm42607`, unmodified |
| `bt` | `q25-btmtk-stp` | Marathon |
| `audio` | `snd-timer`, `snd-pcm`, `snd-jack`, `snd-soc-core`, `snd-soc-mt6358`, `snd-soc-mtk-common`, `snd-soc-mt6789-afe`, `q25-audio-pd`, `q25-oca72390`, `q25-mt6366-card`, `q25-mt6366-irqfix`, `q25-mt6358-accdet` | the kernel's `sound/` files (`mt6358` plus patches `0002`–`0006`), linux-mediatek/linux `996ec481` (`adomerle/mt6789-sound`) `sound/soc/mediatek/mt6789` plus `0001`, Marathon's `q25/` and `q25irqfix/` drivers, and `q25accdet/`, a port of `sound/soc/codecs/mt6358-accdet.c` from LineageOS/android_kernel_xelex_mt6789 `2a873a35` |
| `panel` | `q25-panel-doze` | Marathon |
| `display` | `q25-vsyncdrm` | the kernel's `drivers/gpu/drm/sysfb/simpledrm.c` plus Marathon's scan-locked vblank |
| `clk` | `q25-i2c-clk` | Marathon |
| `mag` | `mmc5633` | the kernel's `drivers/iio/magnetometer/mmc5633.c` plus `mmc5633-q25.patch` |
| `light` | `hx32062se` | Marathon |
| (kernel tree) | `spi-mt65xx`, `rfkill`, `cfg80211`, `bluetooth` | the kernel's own source; the APK's config leaves them unbuilt or unshipped |
| `modem` | `ccci_util_lib`, `ccmni`, `ccci_md_all`, `ccci_ccif`, `ccci_dpmaif` (shipped by `q25-modem`) | iasnezhkov/android_kernel_ikko_mindone `9cd73c15` `mindone/modules`, the files in `eccci-files.txt`, plus `0001` and `0002` |
| `wifi` | `connadp`, `btif_drv`, `wmt_drv`, `wmt_chrdev_wifi`, `wlan_drv_gen4m_6789` | iasnezhkov/android_kernel_ikko_mindone `9cd73c15` `mindone/modules`, plus the two patches |

`wifi/wmt-files.txt` lists the donor files that form the WMT/BTIF/connadp
tree before `0001`; `0002` applies to the donor's `wlan_drv_gen4m_6789` and
`wmt_chrdev_wifi` directories.

`MT6789_SOUND=DIR build.sh KSRC KOBJ DONOR OUT [SHIPPED]` builds all of them
against the prepared kernel tree and, given the shipped modules, compares
each. ThinLTO derives promoted symbol names from the build path, so
the bytes differ from the shipped ones; `kocmp.py` checks that code, data
and symbols are otherwise identical (compare debug-stripped copies).
