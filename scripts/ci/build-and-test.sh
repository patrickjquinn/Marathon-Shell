#!/bin/sh
# Build and test the shell inside alpine:edge, the base the marathon-shell
# apk is built on. .github/workflows/ci.yml runs this; to reproduce locally:
#
#   podman run --rm -v "$PWD:/src:ro" docker.io/library/alpine:edge /src/scripts/ci/build-and-test.sh
#
# keel-silica-dev comes from Marathon's own aports, not Alpine, so the Keel
# Silica QML suites are left out (see ci.yml).
set -eu

apk add --no-cache \
	build-base cmake samurai pkgconf git python3 py3-jsonschema cargo rust-clippy rustfmt \
	qt6-qtbase-dev qt6-qtdeclarative-dev qt6-qtwayland-dev qt6-qtwebengine-dev \
	qt6-qtwebchannel-dev qt6-qtmultimedia-dev qt6-qtsensors-dev qt6-qtsvg-dev qt6-qttools-dev \
	qt6-qtlocation-dev qt6-qtpositioning-dev qt6-qtspeech-dev qt6-qtwebsockets-dev \
	hunspell-dev hunspell-en-us pulseaudio-dev pipewire-dev wayland-dev wayland-protocols \
	mesa-dev libdrm-dev dbus dbus-dev eudev-dev libinput-dev linux-pam-dev sqlite-dev \
	rpm findutils coreutils cryptsetup pipewire wireplumber pipewire-tools zstd

# Tests that check file permissions pass trivially as root, so build and test
# as an ordinary user from a private copy of the tree.
adduser -D ci
cp -a /src /home/ci/src
chown -R ci:ci /home/ci/src

exec su ci -c 'set -eu
cd /home/ci/src
unset KEEL_QML
export QT_QPA_PLATFORM=offscreen
export MARATHON_TEST_STRICT=1
cargo fmt --manifest-path crates/Cargo.toml --all -- --check
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON
cmake --build build
ctest --test-dir build --output-on-failure
sh scripts/ci/count-skips.sh build/Testing/Temporary/LastTest.log tests/expected-skips.txt
cargo clippy --manifest-path crates/Cargo.toml --workspace --all-targets --locked -- -D warnings'
