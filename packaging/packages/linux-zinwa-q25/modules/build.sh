#!/bin/sh
# Build the Q25 out-of-tree modules against the linux-zinwa-q25 tree; its
# APKBUILD runs this after the kernel.
#
#   MT6789_SOUND=DIR build.sh KSRC KOBJ DONOR OUT
#
# KSRC/KOBJ: the kernel source and object trees (make -C KSRC O=KOBJ).
# DONOR: github.com/iasnezhkov/android_kernel_ikko_mindone at
# 9cd73c15f312cfd1e40a22d871de65a2fb2c5791 (only mindone/modules is read).
# MT6789_SOUND: a tree holding sound/soc/mediatek/mt6789 of
# github.com/linux-mediatek/linux 996ec48145f6746ecc664e92c6e5892b6978e3ae
# (branch adomerle/mt6789-sound).
# OUT is created: OUT/modules holds the modules, OUT/firmware the camera
# overlay; nothing else is written.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
ksrc=$1 kobj=$2 donor=$3/mindone/modules out=$4
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
for d in keyboard md1 conn-pd cam-pd cam-dt cam-pmic bt audio panel display clk light haptic gauge gpu-mfg gnss; do
	rm -rf "$out/src/$d"
	cp -r "$here/$d" "$out/src/$d"
done

a=$out/src/audio
mkdir -p "$a/codecs" "$a/mediatek/common" "$a/mediatek/mt6789"
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
cp -r "$ksrc/drivers/media/common/videobuf2" "$m/"
mkdir -p "$m/mediatek"
cp "$here/camera/Kbuild" "$m/mediatek/"
cp -r "$here/camera/seninf" "$here/camera/camsv" "$here/camera/phy" "$m/mediatek/"
cp "$ksrc/drivers/phy/mediatek/phy-mtk-io.h" "$m/mediatek/phy/"
(cd "$m/mediatek" && patch -p1 -s < "$here/camera/0001-mt6789-port.patch")

rm -rf "$out/src/modem"
mkdir -p "$out/src/modem"
(cd "$donor" && tar cf - -T "$here/modem/eccci-files.txt") | tar xf - -C "$out/src/modem"
for p in "$here"/modem/*.patch; do
	(cd "$out/src/modem" && patch -p1 -s < "$p")
done

for d in keyboard md1 conn-pd cam-pd cam-dt cam-pmic audio panel display clk light haptic gauge gpu-mfg; do
	kmake "$out/src/$d" "$out/obj/$d"
done
kmake "$out/src/wmt" "$out/obj/wmt"
kmake "$out/src/wlan" "$out/obj/wlan" JOINT="$out/src/wmt" \
	KBUILD_EXTRA_SYMBOLS="$out/obj/wmt/Module.symvers"
kmake "$out/src/bt" "$out/obj/bt" WMTSRC="$out/src/wmt" \
	KBUILD_EXTRA_SYMBOLS="$out/obj/wmt/Module.symvers"
kmake "$out/src/gnss" "$out/obj/gnss" WMTSRC="$out/src/wmt" \
	KBUILD_EXTRA_SYMBOLS="$out/obj/wmt/Module.symvers"
# videobuf2, which no in-tree driver selects, and the camera receive
# drivers that use it, as one set (media/Kbuild).
kmake "$out/src/media" "$out/obj/media" \
	CONFIG_VIDEOBUF2_CORE=m CONFIG_VIDEOBUF2_V4L2=m CONFIG_VIDEOBUF2_MEMOPS=m \
	CONFIG_VIDEOBUF2_DMA_CONTIG=m \
	CONFIG_MTK_SENINF6S=m CONFIG_MTK_CAMSV6S=m CONFIG_PHY_MTK_MIPI_CSI_2_1=m
syms=""
for m in ccci_util_lib ccmni ccci_md_all ccci_ccif ccci_dpmaif; do
	kmake "$out/src/modem/$m" "$out/obj/modem/$m" KBUILD_EXTRA_SYMBOLS="$syms"
	syms="$syms $out/obj/modem/$m/Module.symvers"
done

# The first set ships as built; everything else without debug info.
mkdir -p "$out/modules"
find "$out/obj" -name '*.ko' |
while read -r ko; do
	case "$(basename "$ko")" in
	q25-bbq-keys.ko | q25-keyboard-led.ko | q25-md1-owner.ko)
		cp "$ko" "$out/modules/" ;;
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
