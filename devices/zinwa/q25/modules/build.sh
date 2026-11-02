#!/bin/sh
# Build the Q25 out-of-tree modules against a prepared 7.0.0-q25-cfi-test
# kernel tree and, given SHIPPED (a directory of the packaged .ko files),
# check each against it with kocmp.py.
#
#   MT6789_SOUND=DIR build.sh KSRC KOBJ DONOR OUT [SHIPPED]
#
# KSRC/KOBJ: the kernel source and object trees the kernel APK was built
# from (make -C KSRC O=KOBJ). DONOR: a checkout of
# github.com/iasnezhkov/android_kernel_ikko_mindone at
# 9cd73c15f312cfd1e40a22d871de65a2fb2c5791 (only mindone/modules is read).
# MT6789_SOUND: a checkout of github.com/linux-mediatek/linux at
# 996ec48145f6746ecc664e92c6e5892b6978e3ae (branch adomerle/mt6789-sound;
# only sound/soc/mediatek/mt6789 is read).
# The modem modules (modem/) ship in q25-modem, so SHIPPED must hold them too.
# OUT is created; nothing else is written.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
ksrc=$1 kobj=$2 donor=$3/mindone/modules out=$4 shipped=${5:-}
mt6789=${MT6789_SOUND:?set MT6789_SOUND to the linux-mediatek checkout}/sound/soc/mediatek/mt6789
mkdir -p "$out"
out=$(cd "$out" && pwd)

printf '#!/bin/sh\nexec ld.lld --thinlto-jobs=1 "$@"\n' > "$out/ld"
chmod +x "$out/ld"

kmake() {
	src=$1 obj=$2
	shift 2
	mkdir -p "$obj"
	make -C "$ksrc" O="$kobj" M="$src" MO="$obj" ARCH=arm64 LLVM=1 \
		LD="$out/ld" W=1 -j"${JOBS:-2}" "$@" modules
}

mkdir -p "$out/src"
for d in keyboard md1 conn-pd cam-pd cam-dt cam-pmic imu bt gnss audio panel display clk mag light haptic net; do
	rm -rf "$out/src/$d"
	cp -r "$here/$d" "$out/src/$d"
done
cp "$ksrc/drivers/spi/spi-mt65xx.c" "$out/src/imu/"
cp "$ksrc/drivers/iio/magnetometer/mmc5633.c" "$out/src/mag/"
(cd "$out/src/mag" && patch -p1 -s < mmc5633-q25.patch)
cp "$ksrc/drivers/input/misc/regulator-haptic.c" "$out/src/haptic/"
cp "$ksrc/drivers/net/tun.c" "$ksrc/drivers/net/tun_vnet.h" "$ksrc/drivers/net/veth.c" \
	"$ksrc/drivers/net/dummy.c" "$out/src/net/"
cp -r "$ksrc/net/netfilter" "$out/src/net/netfilter"
mkdir -p "$out/src/net/ipv4" "$out/src/net/ipv6" "$out/src/net/bridge"
cp "$ksrc/net/bridge/br_private.h" "$out/src/net/bridge/"
cp -r "$ksrc/net/ipv4/netfilter" "$out/src/net/ipv4/netfilter"
cp -r "$ksrc/net/ipv6/netfilter" "$out/src/net/ipv6/netfilter"

a=$out/src/audio
mkdir -p "$a/core" "$a/soc" "$a/codecs" "$a/mediatek/common" "$a/mediatek/mt6789"
for f in timer.c timer_compat.c pcm.c pcm_native.c pcm_lib.c pcm_misc.c pcm_memory.c \
	memalloc.c pcm_timer.c pcm_compat.c pcm_local.h pcm_param_trace.h pcm_trace.h \
	jack.c ctljack.c; do
	cp "$ksrc/sound/core/$f" "$a/core/"
done
for f in soc-core.c soc-dapm.c soc-jack.c soc-utils.c soc-dai.c soc-component.c soc-pcm.c \
	soc-devres.c soc-ops.c soc-link.c soc-card.c; do
	cp "$ksrc/sound/soc/$f" "$a/soc/"
done
cp "$ksrc/sound/soc/codecs/mt6358.c" "$ksrc/sound/soc/codecs/mt6358.h" "$a/codecs/"
for f in mtk-afe-fe-dai.c mtk-afe-fe-dai.h mtk-afe-platform-driver.c mtk-afe-platform-driver.h \
	mtk-base-afe.h mtk-dai-adda-common.c mtk-dai-adda-common.h mtk-soc-card.h \
	mtk-soundcard-driver.c mtk-soundcard-driver.h mtk-dsp-sof-common.c mtk-dsp-sof-common.h; do
	cp "$ksrc/sound/soc/mediatek/common/$f" "$a/mediatek/common/"
done
cp "$mt6789"/*.c "$mt6789"/*.h "$a/mediatek/mt6789/"
rm "$a/mediatek/mt6789/mt6789-mt6366.c"
(cd "$a/mediatek/mt6789" && patch -p5 -s < "$a/patches/0001-mt6789-afe-q25-fixups.patch")
for p in "$a"/patches/000[2-6]-*.patch; do
	(cd "$a/codecs" && patch -p4 -s < "$p")
done

rm -rf "$out/src/wmt" "$out/src/wlan"
mkdir -p "$out/src/wmt" "$out/src/wlan"
while read -r f; do
	mkdir -p "$out/src/wmt/$(dirname "$f")"
	cp -P "$donor/$f" "$out/src/wmt/$f"
done < "$here/wifi/wmt-files.txt"
cp -r "$donor/wlan_drv_gen4m_6789" "$donor/wmt_chrdev_wifi" "$out/src/wlan/"
(cd "$out/src/wmt" && patch -p1 -s < "$here/wifi/0001-wmt-btif-connadp-q25.patch")
(cd "$out/src/wlan" && patch -p1 -s < "$here/wifi/0002-wlan-gen4m-q25.patch")

m=$out/src/media
rm -rf "$m"
mkdir -p "$m"
cp "$here/media/Kbuild" "$m/"
cp -r "$ksrc/drivers/media/mc" "$ksrc/drivers/media/v4l2-core" "$m/"
cp -r "$ksrc/drivers/media/common/videobuf2" "$m/"
mkdir -p "$m/mediatek"
cp "$here/camera/Kbuild" "$m/mediatek/"
cp -r "$here/camera/seninf" "$here/camera/camsv" "$here/camera/phy" "$m/mediatek/"
cp "$ksrc/drivers/phy/mediatek/phy-mtk-io.h" "$m/mediatek/phy/"
mkdir -p "$m/i2c"
cp "$here/camera/i2c/Kbuild" "$ksrc/drivers/media/i2c/imx111.c" \
	"$ksrc/drivers/media/i2c/s5kjn1.c" "$m/i2c/"
for p in "$here"/camera/i2c/*.patch; do
	(cd "$m/i2c" && patch -p1 -s < "$p")
done
(cd "$m/mediatek" && patch -p1 -s < "$here/camera/0001-mt6789-port.patch")

rm -rf "$out/src/modem"
mkdir -p "$out/src/modem"
(cd "$donor" && tar cf - -T "$here/modem/eccci-files.txt") | tar xf - -C "$out/src/modem"
for p in "$here"/modem/*.patch; do
	(cd "$out/src/modem" && patch -p1 -s < "$p")
done

for d in keyboard md1 conn-pd cam-pd cam-dt cam-pmic imu audio panel display clk mag light haptic; do
	kmake "$out/src/$d" "$out/obj/$d"
done
# Android netd's matches and targets, unset in the kernel config.
kmake "$out/src/net" "$out/obj/net/core" \
	CONFIG_NETFILTER_XT_CONNMARK=m CONFIG_NETFILTER_XT_MATCH_BPF=m \
	CONFIG_NETFILTER_XT_MATCH_OWNER=m CONFIG_NETFILTER_XT_MATCH_U32=m \
	CONFIG_NETFILTER_XT_MATCH_STATE=m CONFIG_NETFILTER_XT_MATCH_PKTTYPE=m \
	CONFIG_NETFILTER_XT_MATCH_LIMIT=m CONFIG_NETFILTER_XT_MATCH_QUOTA=m \
	CONFIG_NETFILTER_XT_MATCH_HASHLIMIT=m CONFIG_NETFILTER_XT_MATCH_IPRANGE=m \
	CONFIG_NETFILTER_XT_MATCH_LENGTH=m CONFIG_NETFILTER_XT_TARGET_IDLETIMER=m \
	CONFIG_NETFILTER_XT_TARGET_NFLOG=m CONFIG_NETFILTER_NETLINK_LOG=m \
	CONFIG_NETFILTER_XT_TARGET_CT=m
kmake "$ksrc/net/llc" "$out/obj/net/llc"
kmake "$ksrc/net/802" "$out/obj/net/802" \
	KBUILD_EXTRA_SYMBOLS="$out/obj/net/llc/Module.symvers"
kmake "$ksrc/net/bridge" "$out/obj/net/bridge" \
	KBUILD_EXTRA_SYMBOLS="$out/obj/net/core/Module.symvers $out/obj/net/llc/Module.symvers $out/obj/net/802/Module.symvers"
kmake "$ksrc/net/rfkill" "$out/obj/rfkill"
kmake "$ksrc/net/wireless" "$out/obj/cfg80211" \
	KBUILD_EXTRA_SYMBOLS="$out/obj/rfkill/Module.symvers"
kmake "$ksrc/net/bluetooth" "$out/obj/bluetooth" \
	KBUILD_EXTRA_SYMBOLS="$out/obj/rfkill/Module.symvers"
kmake "$out/src/wmt" "$out/obj/wmt"
kmake "$out/src/wlan" "$out/obj/wlan" JOINT="$out/src/wmt" \
	KBUILD_EXTRA_SYMBOLS="$out/obj/wmt/Module.symvers $out/obj/rfkill/Module.symvers $out/obj/cfg80211/Module.symvers"
kmake "$out/src/bt" "$out/obj/bt" WMTSRC="$out/src/wmt" \
	KBUILD_EXTRA_SYMBOLS="$out/obj/wmt/Module.symvers $out/obj/rfkill/Module.symvers $out/obj/bluetooth/Module.symvers"
kmake "$out/src/gnss" "$out/obj/gnss" WMTSRC="$out/src/wmt" \
	KBUILD_EXTRA_SYMBOLS="$out/obj/wmt/Module.symvers"
# The V4L2 media core, unset in the kernel config, and the camera drivers
# that use it, as one set (media/Kbuild).
kmake "$out/src/media" "$out/obj/media" \
	CONFIG_MEDIA_SUPPORT=m CONFIG_MEDIA_CONTROLLER=y CONFIG_VIDEO_DEV=m \
	CONFIG_VIDEO_V4L2_I2C=y CONFIG_V4L2_ASYNC=m CONFIG_V4L2_FWNODE=m \
	CONFIG_V4L2_CCI=m CONFIG_V4L2_CCI_I2C=m CONFIG_VIDEOBUF2_CORE=m \
	CONFIG_VIDEOBUF2_V4L2=m CONFIG_VIDEOBUF2_MEMOPS=m CONFIG_VIDEOBUF2_DMA_CONTIG=m \
	CONFIG_MTK_SENINF6S=m CONFIG_MTK_CAMSV6S=m CONFIG_PHY_MTK_MIPI_CSI_2_1=m \
	CONFIG_VIDEO_IMX111=m CONFIG_VIDEO_S5KJN1=m
syms=""
for m in ccci_util_lib ccmni ccci_md_all ccci_ccif ccci_dpmaif; do
	kmake "$out/src/modem/$m" "$out/obj/modem/$m" KBUILD_EXTRA_SYMBOLS="$syms"
	syms="$syms $out/obj/modem/$m/Module.symvers"
done

# The first set ships as built; everything else without debug info. Of
# net/bluetooth only the core is shipped, and of the networking builds what
# Deckard's bridge, veth and iptables-nft NAT and Android's legacy iptables need.
# The camera modules are loaded by hand and stay in obj/ until they ship, as
# does gnss until the Q25 has booted its DSP.
mkdir -p "$out/modules"
net="llc stp bridge veth tun nfnetlink x_tables xt_tcpudp xt_CHECKSUM xt_MASQUERADE
	nf_defrag_ipv4 nf_defrag_ipv6 nf_conntrack nf_nat nf_tables nft_compat nft_chain_nat
	nft_masq nft_ct
	nf_reject_ipv4 nf_reject_ipv6 ip_tables ip6_tables iptable_filter iptable_nat
	iptable_mangle iptable_raw ip6table_filter ip6table_nat ip6table_mangle ip6table_raw
	ipt_REJECT ip6t_REJECT xt_mark xt_conntrack xt_comment xt_multiport xt_tcpmss
	xt_TCPMSS xt_addrtype xt_REDIRECT
	xt_connmark xt_bpf xt_owner xt_u32 xt_state xt_pkttype xt_limit xt_quota
	xt_hashlimit xt_iprange xt_length xt_IDLETIMER xt_NFLOG nfnetlink_log xt_CT dummy"
for m in $net; do
	llvm-strip --strip-debug -o "$out/modules/$m.ko" "$(find "$out/obj/net" -name "$m.ko")"
done
find "$out/obj" -name '*.ko' ! -path "$out/obj/bluetooth/*" ! -path "$out/obj/net/*" \
	! -path "$out/obj/gnss/*" \
	-o -path "$out/obj/bluetooth/bluetooth.ko" |
while read -r ko; do
	case "$(basename "$ko")" in
	q25-bbq-keys.ko | q25-keyboard-led.ko | q25-md1-owner.ko | inv-icm42607*.ko | spi-mt65xx.ko)
		cp "$ko" "$out/modules/" ;;
	v4l2-dv-timings.ko) ;;
	*)
		llvm-strip --strip-debug -o "$out/modules/$(basename "$ko")" "$ko" ;;
	esac
done
mkdir -p "$out/firmware"
cpp -nostdinc -undef -x assembler-with-cpp -P -I "$ksrc/include" \
	"$here/camera/q25-camera.dtso" > "$out/obj/q25-camera.dts"
# Its providers are base phandles dtc cannot see.
"$kobj/scripts/dtc/dtc" -@ -Wno-clocks_property -Wno-power_domains_property \
	-Wno-interrupts_property -Wno-gpios_property -I dts -O dtb -o "$out/firmware/q25-camera.dtbo" "$out/obj/q25-camera.dts"
[ -n "$shipped" ] || exit 0
mkdir -p "$out/cmp"
status=0
for ko in "$out"/modules/*.ko; do
	m=$(basename "$ko")
	if [ ! -f "$shipped/$m" ]; then
		echo "$m: new"
		continue
	fi
	llvm-strip --strip-debug -o "$out/cmp/new-$m" "$ko"
	llvm-strip --strip-debug -o "$out/cmp/shipped-$m" "$shipped/$m"
	printf '%s: ' "$m"
	python3 "$here/kocmp.py" "$out/cmp/shipped-$m" "$out/cmp/new-$m" || status=1
done
exit $status
