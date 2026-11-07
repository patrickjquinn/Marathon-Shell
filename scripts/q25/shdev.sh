#!/bin/sh
# Q25 shell dev loop: an incremental marathon-shell-bin build and a run of it
# on the phone, without packaging or an image.
#
#   shdev.sh build     incremental build in a persistent container
#   shdev.sh deploy    run the build on the phone (bind mount, greetd restart)
#   shdev.sh revert    back to the installed shell
#
# The container image has the phone's exact Qt (the shell uses Qt private
# API). The deploy lasts until revert or a reboot.
#
# Env: SHDEV (build dir), SHDEV_IMAGE, PODMAN, Q25_HOST, SSHPASS.
set -eu
REPO=$(cd "$(dirname "$0")/../.." && pwd)
SHDEV=${SHDEV:-/run/media/patrickquinn/marathon-build/q25/shdev}
IMAGE=${SHDEV_IMAGE:-localhost/marathon-q25-shdev:qt6.11.1}
PODMAN=${PODMAN:-podman}
NAME=marathon-q25-shdev
BIN=$SHDEV/build/shell/marathon-shell-bin

ssh_() {
	sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
		-o LogLevel=ERROR -o ConnectTimeout=20 -o PubkeyAuthentication=no "user@$Q25_HOST" "$@"
}
sudo_() { ssh_ "printf '%s\n' '$SSHPASS' | sudo -S -p '' sh -c '$1'"; }

case "${1:-}" in
build)
	mkdir -p "$SHDEV"
	if ! $PODMAN container exists "$NAME"; then
		# The project writes shell/.qmlls.ini into the source tree.
		touch "$SHDEV/qmlls.ini"
		$PODMAN run -d --name "$NAME" --security-opt label=disable -v "$REPO:/src:ro" \
			-v "$SHDEV/qmlls.ini:/src/shell/.qmlls.ini" -v "$SHDEV:/dev-root" "$IMAGE" sleep infinity >/dev/null
	fi
	[ "$($PODMAN inspect -f '{{.State.Running}}' "$NAME")" = true ] || $PODMAN start "$NAME" >/dev/null
	version=$(sed -n 's/^pkgver=//p' "$REPO/packaging/packages/marathon-shell/APKBUILD")-r$(sed -n 's/^pkgrel=//p' "$REPO/packaging/packages/marathon-shell/APKBUILD")
	# The APKBUILD's build() flags.
	$PODMAN exec "$NAME" sh -c "
		set -e
		o='-O3 -DNDEBUG -ftree-vectorize -ffp-contract=fast'
		[ -f /dev-root/build/build.ninja ] || cmake -S /src -B /dev-root/build -G Ninja \
			-DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS_RELEASE=\"\$o\" -DCMAKE_CXX_FLAGS_RELEASE=\"\$o\" \
			-DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib \
			-DCMAKE_SKIP_BUILD_RPATH=TRUE -DCMAKE_BUILD_WITH_INSTALL_RPATH=TRUE \
			-DCMAKE_INSTALL_RPATH='\$ORIGIN' -DQt6_DIR=/usr/lib/cmake/Qt6 \
			-DMARATHON_REQUIRE_INPUT_SUPPORT=ON -DQT_QML_GENERATE_QMLLS_INI=OFF
		cmake -S /src -B /dev-root/build -DMARATHON_VERSION=$version -DMARATHON_CARGO_PROFILE=dev-fast >/dev/null
		cmake --build /dev-root/build --target marathon-shell-bin"
	ls -l "$BIN"
	;;
deploy)
	: "${Q25_HOST:?set Q25_HOST}" "${SSHPASS:?set SSHPASS}"
	zstd -q -c "$BIN" | ssh_ 'zstd -q -d -c > /tmp/marathon-shell-bin.dev'
	sudo_ 'set -e; d=/var/lib/marathon/dev; install -d -m 755 $d
		install -m 755 /tmp/marathon-shell-bin.dev $d/marathon-shell-bin
		mountpoint -q /usr/bin/marathon-shell-bin || mount --bind $d/marathon-shell-bin /usr/bin/marathon-shell-bin
		systemctl restart greetd'
	echo "shdev: $Q25_HOST runs the dev shell until revert or reboot"
	;;
revert)
	: "${Q25_HOST:?set Q25_HOST}" "${SSHPASS:?set SSHPASS}"
	sudo_ 'umount /usr/bin/marathon-shell-bin 2>/dev/null; systemctl restart greetd'
	echo "shdev: $Q25_HOST runs the installed shell"
	;;
*)
	sed -n '2,13s/^# \{0,1\}//p' "$0"
	exit 1
	;;
esac
