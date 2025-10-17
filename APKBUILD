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
	greetd
	dbus
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
	marathon.desktop
	marathon-shell.toml
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
	
	# Install main shell
	DESTDIR="$pkgdir" cmake --install build
	
	# Install apps
	DESTDIR="$pkgdir" cmake --install build-apps
	
	# Install launcher script
	install -Dm755 run.sh "$pkgdir"/usr/bin/marathon-shell
	
	# Install Wayland session file
	install -Dm644 "$srcdir"/marathon.desktop \
		"$pkgdir"/usr/share/wayland-sessions/marathon.desktop
	
	# Install greetd configuration example
	install -Dm644 "$srcdir"/marathon-shell.toml \
		"$pkgdir"/usr/share/greetd/marathon-shell.toml
	
	# Install documentation
	install -Dm644 README.md \
		"$pkgdir"/usr/share/doc/$pkgname/README.md
	install -Dm644 docs/*.md \
		"$pkgdir"/usr/share/doc/$pkgname/
}

sha512sums="
"

