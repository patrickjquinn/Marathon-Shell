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
	hunspell
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
	qt6-qtlocation-dev
	qt6-qtpositioning-dev
	wayland-dev
	wayland-protocols
	mesa-dev
	dbus-dev
	eudev-dev
	libinput-dev
	git
	linux-pam-dev
	hunspell-dev
	"
install=""
subpackages="$pkgname-doc"
source="
	$pkgname-$pkgver.tar.gz
	asyncfuture.tar.gz::https://github.com/vpicaver/asyncfuture/archive/master.tar.gz
	"
builddir="$srcdir/$pkgname-$pkgver"

prepare() {
	default_prepare
	
	# Extract asyncfuture submodule
	mkdir -p "$builddir/third-party/asyncfuture"
	cp -r "$srcdir"/asyncfuture-master/* "$builddir/third-party/asyncfuture/"
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
	
	# Fix session script to use -platform eglfs flag
	sed -i 's|exec /usr/bin/marathon-shell-bin "$@"|exec /usr/bin/marathon-shell-bin -platform eglfs "$@"|' \
		"$pkgdir/usr/bin/marathon-shell-session"
}

sha512sums=""