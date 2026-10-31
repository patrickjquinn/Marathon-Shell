Sources of the modules that `packaging/packages/q25-kernel-modules` ships.

| Directory | Modules | Origin |
|---|---|---|
| `keyboard` | `q25-bbq-keys`, `q25-keyboard-led` | Marathon |
| `md1` | `q25-md1-owner` | Marathon |
| `conn-pd` | `q25-conn-pd` | Marathon |
| `imu` | `inv-icm42607`, `inv-icm42607-spi` | torvalds/linux `abf8c334` `drivers/iio/imu/inv_icm42607`, unmodified |
| `bt` | `q25-btmtk-stp` | Marathon |
| (kernel tree) | `spi-mt65xx`, `rfkill`, `cfg80211`, `bluetooth` | the kernel's own source; the APK's config leaves them unbuilt or unshipped |
| `wifi` | `connadp`, `btif_drv`, `wmt_drv`, `wmt_chrdev_wifi`, `wlan_drv_gen4m_6789` | iasnezhkov/android_kernel_ikko_mindone `9cd73c15` `mindone/modules`, plus the two patches |

`wifi/wmt-files.txt` lists the donor files that form the WMT/BTIF/connadp
tree before `0001`; `0002` applies to the donor's `wlan_drv_gen4m_6789` and
`wmt_chrdev_wifi` directories.

`build.sh KSRC KOBJ DONOR OUT [SHIPPED]` builds all of them
against the prepared kernel tree and, given the shipped modules, compares
each. ThinLTO derives promoted symbol names from the build path, so
the bytes differ from the shipped ones; `kocmp.py` checks that code, data
and symbols are otherwise identical (compare debug-stripped copies).
