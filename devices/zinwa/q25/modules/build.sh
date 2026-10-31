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
for d in keyboard md1 conn-pd imu bt audio panel mag light; do
	rm -rf "$out/src/$d"
	cp -r "$here/$d" "$out/src/$d"
done
cp "$ksrc/drivers/spi/spi-mt65xx.c" "$out/src/imu/"
cp "$ksrc/drivers/iio/magnetometer/mmc5633.c" "$out/src/mag/"
(cd "$out/src/mag" && patch -p1 -s < mmc5633-q25.patch)

a=$out/src/audio
mkdir -p "$a/core" "$a/soc" "$a/codecs" "$a/mediatek/common" "$a/mediatek/mt6789"
for f in timer.c timer_compat.c pcm.c pcm_native.c pcm_lib.c pcm_misc.c pcm_memory.c \
	memalloc.c pcm_timer.c pcm_compat.c pcm_local.h pcm_param_trace.h pcm_trace.h; do
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

for d in keyboard md1 conn-pd imu audio panel mag light; do
	kmake "$out/src/$d" "$out/obj/$d"
done
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

# The first set ships as built; everything else without debug info. Of
# net/bluetooth only the core is shipped.
mkdir -p "$out/modules"
find "$out/obj" -name '*.ko' ! -path "$out/obj/bluetooth/*" -o -path "$out/obj/bluetooth/bluetooth.ko" |
while read -r ko; do
	case "$(basename "$ko")" in
	q25-bbq-keys.ko | q25-keyboard-led.ko | q25-md1-owner.ko | inv-icm42607*.ko | spi-mt65xx.ko)
		cp "$ko" "$out/modules/" ;;
	*)
		llvm-strip --strip-debug -o "$out/modules/$(basename "$ko")" "$ko" ;;
	esac
done
[ -n "$shipped" ] || exit 0
mkdir -p "$out/cmp"
status=0
for ko in "$out"/modules/*.ko; do
	m=$(basename "$ko")
	llvm-strip --strip-debug -o "$out/cmp/new-$m" "$ko"
	llvm-strip --strip-debug -o "$out/cmp/shipped-$m" "$shipped/$m"
	printf '%s: ' "$m"
	python3 "$here/kocmp.py" "$out/cmp/shipped-$m" "$out/cmp/new-$m" || status=1
done
exit $status
