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
	upower
	polkit
	bluez
	geoclue
	xdg-desktop-portal
	"
makedepends="
	cmake
	samurai
	qt6-qtbase-dev
	qt6-qtdeclarative-dev
	qt6-qtwayland-dev
	qt6-qtwebengine-dev
	qt6-qtmultimedia-dev
	qt6-qtsvg-dev
	wayland-dev
	wayland-protocols
	mesa-dev
	dbus-dev
	"
install=""
subpackages="$pkgname-doc"
source="
	$pkgname-$pkgver.tar.gz
	"
builddir="$srcdir/$pkgname-$pkgver"

build() {
	cd "$builddir"
	
	# CRITICAL: Build everything together in ONE build directory
	# The shell binary embeds MarathonUI modules as Qt resources (qrc:/qt/qml/MarathonUI/)
	# and needs them in build/MarathonUI/ during the build process.
	# Building MarathonUI separately will cause "No such file or directory" errors at runtime.
	cmake -B build -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DQt6_DIR=/usr/lib/cmake/Qt6
	cmake --build build
}

check() {
	cd "$builddir"
	# Add tests when available
	true
}

package() {
	cd "$builddir"
	
	# Install everything (MarathonUI, Shell, Apps)
	DESTDIR="$pkgdir" cmake --install build
}

sha512sums="
"

