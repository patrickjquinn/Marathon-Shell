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
	
	# Build main shell
	cmake -B build -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DQt6_DIR=/usr/lib/cmake/Qt6
	cmake --build build
	
	# Build apps
	cmake -B build-apps -S apps -G Ninja \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr \
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
	
	# Install main shell (includes binary, session files, systemd, polkit, etc.)
	DESTDIR="$pkgdir" cmake --install build
	
	# Install apps
	DESTDIR="$pkgdir" cmake --install build-apps
}

sha512sums="
"

