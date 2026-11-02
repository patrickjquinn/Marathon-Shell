Sources of the modules that `packaging/packages/q25-kernel-modules` ships.

| Directory | Modules | Origin |
|---|---|---|
| `keyboard` | `q25-bbq-keys`, `q25-keyboard-led` | Marathon |
| `md1` | `q25-md1-owner` | Marathon |
| `conn-pd` | `q25-conn-pd` | Marathon |
| `cam-pd` | `q25-cam-pd` | Marathon: the CAM power domain provider |
| `imu` | `inv-icm42607`, `inv-icm42607-spi` | torvalds/linux `abf8c334` `drivers/iio/imu/inv_icm42607`, unmodified |
| `bt` | `q25-btmtk-stp` | Marathon |
| `audio` | `snd-timer`, `snd-pcm`, `snd-jack`, `snd-soc-core`, `snd-soc-mt6358`, `snd-soc-mtk-common`, `snd-soc-mt6789-afe`, `q25-audio-pd`, `q25-oca72390`, `q25-mt6366-card`, `q25-mt6366-irqfix`, `q25-mt6358-accdet` | the kernel's `sound/` files (`mt6358` plus patches `0002`–`0006`), linux-mediatek/linux `996ec481` (`adomerle/mt6789-sound`) `sound/soc/mediatek/mt6789` plus `0001`, Marathon's `q25/` and `q25irqfix/` drivers, and `q25accdet/`, a port of `sound/soc/codecs/mt6358-accdet.c` from LineageOS/android_kernel_xelex_mt6789 `2a873a35` |
| `panel` | `q25-panel-doze` | Marathon |
| `display` | `q25-vsyncdrm` | the kernel's `drivers/gpu/drm/sysfb/simpledrm.c` plus Marathon's scan-locked vblank |
| `clk` | `q25-i2c-clk` | Marathon |
| `mag` | `mmc5633` | the kernel's `drivers/iio/magnetometer/mmc5633.c` plus `mmc5633-q25.patch` |
| `light` | `hx32062se` | Marathon |
| `gauge` | `q25-mt6358-live` | Marathon |
| `haptic` | `q25-haptic`, `regulator-haptic` | Marathon's glue, and the kernel's `drivers/input/misc/regulator-haptic.c`, unmodified |
| `cam-dt` | `q25-cam-dt` | Marathon: applies `camera/q25-camera.dtbo` at runtime |
| `cam-pmic` | `wl2868c-regulator` | Qianhui Xu's "[PATCH v4 2/4] regulator: willsemi,wl2868c" (LKML, 2026-10-31), unmodified |
| (kernel tree) | `spi-mt65xx`, `rfkill`, `cfg80211`, `bluetooth`, `llc`, `stp`, `bridge` | the kernel's own source; the APK's config leaves them unbuilt or unshipped |
| `net` | `tun`, `veth`, `nfnetlink`, `x_tables`, `xt_tcpudp`, `xt_CHECKSUM`, `xt_MASQUERADE`, `nf_defrag_ipv4`, `nf_defrag_ipv6`, `nf_conntrack`, `nf_nat`, `nf_tables`, `nft_compat`, `nft_chain_nat`, `nft_masq`, `nft_ct`, `nf_reject_ipv4`, `nf_reject_ipv6`, `ip_tables`, `ip6_tables`, `iptable_{filter,nat,mangle,raw}`, `ip6table_{filter,nat,mangle,raw}`, `ipt_REJECT`, `ip6t_REJECT`, `xt_mark`, `xt_conntrack`, `xt_comment`, `xt_multiport`, `xt_tcpmss`, `xt_TCPMSS`, `xt_addrtype`, `xt_REDIRECT`, `xt_connmark`, `xt_bpf`, `xt_owner`, `xt_u32`, `xt_state`, `xt_pkttype`, `xt_limit`, `xt_quota`, `xt_hashlimit`, `xt_iprange`, `xt_length`, `xt_IDLETIMER`, `xt_NFLOG`, `nfnetlink_log`, `xt_CT`, `dummy` | the kernel's `drivers/net/tun.c`, `veth.c` and `dummy.c` and its `net/netfilter`, `net/ipv4/netfilter` and `net/ipv6/netfilter`, built as one set with the matches and targets Android's netd needs forced to `m`; only what Deckard's bridge and iptables-nft NAT and Android's legacy iptables need ships |
| `modem` | `ccci_util_lib`, `ccmni`, `ccci_md_all`, `ccci_ccif`, `ccci_dpmaif` (shipped by `q25-modem`) | iasnezhkov/android_kernel_ikko_mindone `9cd73c15` `mindone/modules`, the files in `eccci-files.txt`, plus `0001` and `0002` |
| `media` | `mc`, `videodev`, `v4l2-dv-timings`, `v4l2-async`, `v4l2-fwnode`, `v4l2-cci`, `videobuf2-common`, `videobuf2-v4l2`, `videobuf2-memops`, `videobuf2-dma-contig` (`v4l2-dv-timings` is built but not shipped) | the kernel's `drivers/media/mc`, `v4l2-core` and `common/videobuf2`, built as one set with the media symbols forced on and `media/Kbuild`'s matching `-D` flags |
| `camera` | `mtk-seninf6s`, `mtk-camsv6s`, `phy-mtk-mipi-csi-2-1`, `imx111`, `s5kjn1`, and `q25-camera.dtbo`, a runtime overlay for the WL2868C, the front IMX111 on CSI0, the rear S5KJN1 on CSI1, SENINF, CAMSV2 and the CSI PHYs (written to `OUT/firmware`); CAMSV2 takes frames over 4 MiB from the board DT's camera pool (`linux-zinwa-q25`'s `0010`) | gitlab.com/mediatek/aiot/bsp/linux `a246e0c6` (`mtk-v6.6`, Genio 720/MT8189): `drivers/media/platform/mediatek/isp/isp_6s/{seninf,camsv}` and `drivers/phy/mediatek/phy-mtk-mipi-csi-2-1*`, unmodified, plus `0001-mt6789-port.patch`; the kernel's `drivers/media/i2c/{imx111,s5kjn1}.c` plus the patches in `i2c/`; built in the `media` set; `bindings/` holds Genio's MT8189 DT bindings for reference |
| `wifi` | `connadp`, `btif_drv`, `wmt_drv`, `wmt_chrdev_wifi`, `wlan_drv_gen4m_6789` | iasnezhkov/android_kernel_ikko_mindone `9cd73c15` `mindone/modules`, plus the two patches |

`wifi/wmt-files.txt` lists the donor files that form the WMT/BTIF/connadp
tree before `0001`; `0002` applies to the donor's `wlan_drv_gen4m_6789` and
`wmt_chrdev_wifi` directories.

`MT6789_SOUND=DIR build.sh KSRC KOBJ DONOR OUT [SHIPPED]` builds all of them
against the prepared kernel tree and, given the shipped modules, compares
each. ThinLTO derives promoted symbol names from the build path, so
the bytes differ from the shipped ones; `kocmp.py` checks that code, data
and symbols are otherwise identical (compare debug-stripped copies).

All of them carry the vermagic `7.0.0-q25-cfi-test SMP preempt aarch64` of
`packaging/packages/linux-zinwa-q25`, which has `CONFIG_MODVERSIONS` and
`CONFIG_MODULE_SIG` off, so they load into any build of it with the same
release, config and headers; `q25-kernel-modules`, `q25-modem` and
`q25-gpu-render` pin its exact version. A change to its config, its release
or a header these modules use needs them rebuilt: build the kernel with
`abuild -K`, which keeps the tree, pass `src/mtk_g99-mainline-<commit>` as
both KSRC and KOBJ, then replace the `.ko.zst` files and `SHA256SUMS` in
`q25-kernel-modules` and `q25-modem` (and `q25-gpu-render`'s, see its
`GPU-SOURCE-PROVENANCE.json`) and move the pins to the new kernel version.
