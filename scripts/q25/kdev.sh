#!/bin/sh
# Q25 kernel dev loop: an incremental build of the Q25 series and a one-shot
# boot of it on the phone, without packaging or an image.
#
#   kdev.sh init            full tree at $KDEV/src: base tarball + the package's patches
#   kdev.sh build           incremental build into $KDEV/out (no debug info)
#   kdev.sh deploy          one-shot boot of the build on the phone, then reboot
#   kdev.sh export N        format-patch the last N commits into the package
#
# The phone keeps its installed kernel; the build boots once from
# /q25-oneshot and the next boot is the installed one. Modules in the
# initramfs come from the build; modules loaded later from the root image
# stay the installed ones.
#
# Env: KDEV (default ~/q25-build/kdev), Q25_HOST, SSHPASS (user's password;
# also used for sudo), CCACHE_DIR.
set -eu
KDEV=${KDEV:-$HOME/q25-build/kdev}
REPO=$(cd "$(dirname "$0")/../.." && pwd)
PKG=$REPO/packaging/packages/linux-zinwa-q25
DTB=mediatek/mt8781-zinwa-q25.dtb
SRC=$KDEV/src OUT=$KDEV/out
# LOCALVERSION= keeps "+" off the release in a git tree, so the build
# matches the installed modules' vermagic.
MAKE="make -C $SRC O=$OUT ARCH=arm64 LLVM=1 CC=ccache\ clang LOCALVERSION= -j$(nproc)"

patches() { grep -oE '^[[:space:]]+0[0-9]{3}-[^ ]+\.patch' "$PKG/APKBUILD" | tr -d '\t ' | sed "s#^#$PKG/#"; }
git_() { git -C "$SRC" -c user.name="$(git -C "$REPO" config user.name)" -c user.email="$(git -C "$REPO" config user.email)" "$@"; }

ssh_() {
	sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		-o LogLevel=ERROR -o ConnectTimeout=20 -o PubkeyAuthentication=no "user@$Q25_HOST" "$@"
}
sudo_() { ssh_ "printf '%s\n' '$SUDO_PW' | sudo -S -p '' sh -c '$1'"; }

case "${1:-}" in
init)
	commit=$(sed -n 's/^_commit=//p' "$PKG/APKBUILD")
	tarball=${2:?usage: kdev.sh init <mtk_g99-mainline-$commit.tar.gz>}
	mkdir -p "$KDEV"
	tar -xzf "$tarball" -C "$KDEV"
	mv "$KDEV/mtk_g99-mainline-$commit" "$SRC"
	git -C "$SRC" init -q
	git_ add -A
	git_ commit -q -m "ellyq mtk_g99-mainline $commit"
	# shellcheck disable=SC2046
	git_ am -q $(patches)
	;;
build)
	mkdir -p "$OUT"
	if [ ! -f "$OUT/.config" ] || [ "$PKG/config-zinwa-q25.aarch64" -nt "$OUT/.config.pkg" ]; then
		cp "$PKG/config-zinwa-q25.aarch64" "$OUT/.config"
		cp "$PKG/config-zinwa-q25.aarch64" "$OUT/.config.pkg"
		"$SRC/scripts/config" --file "$OUT/.config" --disable DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT --enable DEBUG_INFO_NONE \
			--disable LOCALVERSION_AUTO
		eval "$MAKE olddefconfig"
	fi
	eval "$MAKE vmlinuz.efi modules $DTB"
	;;
deploy)
	: "${Q25_HOST:?set Q25_HOST}" "${SSHPASS:?set SSHPASS}"
	export SUDO_PW="$SSHPASS"
	stage=$KDEV/stage
	rm -rf "$stage" && mkdir -p "$stage/root"
	entry=$(sudo_ 'ls /boot/loader/entries/marathon-q25-b-*.conf /boot/loader/entries/marathon-q25-*.conf 2>/dev/null | head -1')
	sudo_ "cat $entry" > "$stage/installed.conf"
	initrd=$(sed -n 's/^initrd //p' "$stage/installed.conf")
	sudo_ "cat /boot$initrd" > "$stage/initramfs.installed"
	# The build's copy of each module the installed initramfs carries.
	zstd -dc "$stage/initramfs.installed" | cpio -t 2>/dev/null |
		sed -n 's#^usr/lib/modules/[^/]*/\(.*\)\.ko\.zst$#\1#p' > "$stage/modules"
	(cd "$stage/root" && while read -r m; do
		src=$OUT/${m#kernel/}.ko
		[ -f "$src" ] || continue
		dst=usr/lib/modules/$(cat "$OUT/include/config/kernel.release")/$m.ko.zst
		mkdir -p "$(dirname "$dst")"
		llvm-strip --strip-debug -o - "$src" | zstd -q -19 -o "$dst"
		echo "$dst"
	done < "$stage/modules" | cpio -o -H newc --owner=0:0 2>/dev/null | zstd -q -19 > "$stage/overlay.cpio.zst")
	cat "$stage/initramfs.installed" "$stage/overlay.cpio.zst" > "$stage/initramfs"
	cp "$OUT/arch/arm64/boot/vmlinuz.efi" "$stage/linux.efi"
	cp "$OUT/arch/arm64/boot/dts/$DTB" "$stage/q25.dtb"
	sed -e 's#^title .*#title Kernel dev build#' -e 's#^linux .*#linux /q25-oneshot/kdev.efi#' \
		-e 's#^initrd .*#initrd /q25-oneshot/kdev-initramfs#' \
		-e 's#^devicetree .*#devicetree /q25-oneshot/kdev.dtb#' -e '/^sort-key/d' -e '/^version/d' \
		"$stage/installed.conf" > "$stage/q25test-kdev.conf"
	python3 -c "import sys; open(sys.argv[1],'wb').write('q25test-kdev.conf\0'.encode('utf-16-le'))" "$stage/entry-kdev.utf16"
	cat > "$stage/env.txt" <<-'EOF'
	oneshot_boot=if mtk_sip 0xc200040b; then part start scsi 2 misc misc_lba && setexpr oneshot_lba ${misc_lba} + 7f && mw.b ${oneshot_buf} 0 0x1000 && mw.l ${oneshot_buf} 0x4f353251 && setexpr q25_m2 ${oneshot_buf} + 4 && mw.l ${q25_m2} 0x3145434e && scsi write ${oneshot_buf} ${oneshot_lba} 1 && run handoff; else load blkmap 0:1 0x40000000 /q25-oneshot/entry-kdev.utf16 && setenv -e -bs -rt -guid 4a67b082-0a4c-41cf-b6c7-440b29bb8c4f -i 0x40000000:${filesize} LoaderEntryOneShot && bootefi bootmgr; fi
	EOF
	tar -C "$stage" -cf - linux.efi initramfs q25.dtb entry-kdev.utf16 env.txt q25test-kdev.conf |
		ssh_ 'rm -rf /tmp/kdev && mkdir /tmp/kdev && tar -C /tmp/kdev -xf -'
	sudo_ 'set -e; mount -o remount,rw /boot; d=/boot/q25-oneshot; install -d -m 700 $d
		install -m 600 /tmp/kdev/linux.efi $d/kdev.efi; install -m 600 /tmp/kdev/initramfs $d/kdev-initramfs
		install -m 600 /tmp/kdev/q25.dtb $d/kdev.dtb; install -m 600 /tmp/kdev/entry-kdev.utf16 /tmp/kdev/env.txt $d/
		install -m 600 /tmp/kdev/q25test-kdev.conf /boot/loader/entries/
		sync; cmp /tmp/kdev/linux.efi $d/kdev.efi; mount -o remount,ro /boot
		printf Q25ONCE1 | dd of=/dev/sdc1 bs=4096 seek=127 conv=notrunc,fsync status=none
		systemd-run --on-active=2 systemctl reboot >/dev/null'
	echo "kdev: rebooting $Q25_HOST into the dev build ($(wc -l < "$stage/modules") initramfs modules from the build)"
	;;
export)
	n=${2:?usage: kdev.sh export N}
	last=$(patches | tail -1 | sed 's#.*/0*\([0-9]*\)-.*#\1#')
	git_ format-patch -"$n" --start-number "$((last + 1))" -o "$PKG"
	echo "kdev: add the new patches to $PKG/APKBUILD (source + sha512sums) and bump pkgrel"
	;;
*)
	sed -n '2,17s/^# \{0,1\}//p' "$0"
	exit 1
	;;
esac
