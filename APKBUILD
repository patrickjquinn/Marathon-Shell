# Contributor: Patrick Quinn <patrick@example.com>
# Maintainer: Patrick Quinn <patrick@example.com>
pkgname=marathon-shell
pkgver=1.0.0
pkgrel=0
pkgdesc="Marathon Shell - Modern Wayland compositor with Qt6/QML"
url="https://github.com/patrickjquinn/Marathon-Shell"
arch="aarch64 x86_64"
license="MIT"
depends="
	qt6-qtbase
	qt6-qtdeclarative
	qt6-qtwayland
	qt6-qtwebengine
	qt6-qtmultimedia
	qt6-qtsvg
	qt6-qtsql
	qt6-qtsensors
	wayland
	wayland-protocols
	mesa
	mesa-gbm
	mesa-egl
	mesa-dri-gallium
	mesa-gles
	pipewire
	pipewire-pulse
	wireplumber
	pulseaudio-utils
	greetd
	dbus
	networkmanager
	modemmanager
	mmsd-tng
	mobile-broadband-provider-info
	upower
	power-profiles-daemon
	polkit
	bluez
	geoclue
	xdg-desktop-portal
	hunspell
	hunspell-en
	at-spi2-core
	"
makedepends="
	cmake
	samurai
	qt6-qtbase-dev
	qt6-qtbase-private-dev
	qt6-qtdeclarative-dev
	qt6-qtwayland-dev
	qt6-qtwebengine-dev
	qt6-qtmultimedia-dev
	qt6-qtsvg-dev
	qt6-qtlocation-dev
	qt6-qtpositioning-dev
	qt6-qtsensors-dev
	wayland-dev
	wayland-protocols
	mesa-dev
	dbus-dev
	eudev-dev
	libinput-dev
	git
	linux-pam-dev
	hunspell-dev
	pulseaudio-dev
	"
install=""
subpackages="$pkgname-doc"
source="
	$pkgname-$pkgver.tar.gz
	"
builddir="$srcdir/$pkgname-$pkgver"

prepare() {
	default_prepare
}

build() {
	cd "$builddir"
	
	# Clean any existing build directories
	rm -rf build build-apps
	
	# Disable QML cache to reduce memory usage during build
	export QML_DISABLE_DISK_CACHE=1
	export QT_DISABLE_QML_CACHE=1
	
	# Build main shell
	cmake -B build -G Ninja \
		-DCMAKE_BUILD_TYPE=MinSizeRel \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DCMAKE_SKIP_BUILD_RPATH=TRUE \
		-DCMAKE_BUILD_WITH_INSTALL_RPATH=TRUE \
		-DCMAKE_INSTALL_RPATH=\$ORIGIN \
		-DQt6_DIR=/usr/lib/cmake/Qt6
	
	cmake --build build
	
	# Build apps
	cmake -B build-apps -S apps -G Ninja \
		-DCMAKE_BUILD_TYPE=MinSizeRel \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DMARATHON_APPS_DIR=/usr/share/marathon-apps \
		-DCMAKE_SKIP_BUILD_RPATH=TRUE \
		-DCMAKE_BUILD_WITH_INSTALL_RPATH=TRUE \
		-DCMAKE_INSTALL_RPATH=\$ORIGIN \
		-DQt6_DIR=/usr/lib/cmake/Qt6
	cmake --build build-apps
}

check() {
	cd "$builddir"
	# Add tests when available
	true
}

package() {
	cd "$builddir"

	# Install main shell
	DESTDIR="$pkgdir" cmake --install build

	# Install apps
	DESTDIR="$pkgdir" cmake --install build-apps

	# Install marathon-config.json
	install -Dm644 "$builddir/marathon-config.json" \
		"$pkgdir/usr/share/marathon-shell/marathon-config.json"

	# Platform integration: systemd unit, greetd config, session script, .desktop
	install -Dm644 "$builddir/platforms/generic/marathon-shell.service" \
		"$pkgdir/usr/lib/systemd/system/marathon-shell.service"
	install -Dm755 "$builddir/platforms/generic/marathon-shell-session" \
		"$pkgdir/usr/bin/marathon-shell-session"
	install -Dm644 "$builddir/platforms/generic/marathon-shell.toml" \
		"$pkgdir/etc/greetd/marathon-shell.toml"
	install -Dm644 "$builddir/platforms/generic/marathon.desktop" \
		"$pkgdir/usr/share/wayland-sessions/marathon.desktop"

	# PAM, udev, limits — required for password auth, brightness, RT scheduling
	install -Dm644 "$builddir/pam.d/marathon-shell" \
		"$pkgdir/etc/pam.d/marathon-shell"
	install -Dm644 "$builddir/scripts/90-backlight.rules" \
		"$pkgdir/usr/lib/udev/rules.d/90-backlight.rules"
	install -Dm644 /dev/stdin "$pkgdir/etc/security/limits.d/99-marathon.conf" <<-EOF
		# Marathon Shell — non-root processes need this for SCHED_RR render threads
		*       hard    rtprio  10
		*       soft    rtprio  10
		EOF
}

sha512sums=""
