#!/bin/sh
# Renders the e-ink mockups: the shell's components at the MP01's 600x800
# and MARATHON_FORCE_DPI=160, offscreen: <view>-raw.png in the e-ink
# palette and <view>-lcd.png as today. quantize.py then applies the output
# shader's quantization, which offscreen cannot run. Needs Keel's Silica
# built for the same Qt (KEEL_QML) and the Marathon fonts; the keel-dev:shell
# container has both:
#   podman run --rm --network=none -v $KEEL_DEV:/dev-root:O -v $PWD:/src:ro,z \
#     -v $OUT:/out:z localhost/keel-dev:shell sh /src/docs/design/eink/render-mockups.sh /out
# then, where Pillow is: quantize.py $OUT/<view>-raw.png <view>.png for each
# view, with --binary for home-fast (the fast waveform's two levels).
set -eu
out=${1:?output directory}
src=$(cd "$(dirname "$0")/../../.." && pwd)
if [ -f /dev-root/build/build.ninja ]; then
	cmake --install /dev-root/build >/dev/null
	mkdir -p /usr/share/fonts/marathon
	cp "$src"/marathon-fonts/source-sans-3/*.ttf "$src"/shell/qml/theme/fonts/*.ttf /usr/share/fonts/marathon/
	cp "$src"/marathon-fonts/60-marathon-sail-sans.conf /etc/fonts/conf.d/
	fc-cache -f >/dev/null
	PATH=/usr/lib/qt6/bin:$PATH
fi
# The UI tests' stubs, with the real line icons. Their qmldir reaches the
# shell's QML by relative paths, so the copy sits at the same depth.
tmp=$(mktemp -d)
mkdir -p "$tmp"/tests/ui
cp -r "$src"/tests/ui/stubs "$tmp"/tests/ui/
ln -s "$src"/shell "$tmp"/shell
stubs=$tmp/tests/ui/stubs
sed -i "s#^GlyphIcon 1.0 GlyphIcon.qml#GlyphIcon 1.0 ../../../../../shell/qml/ui/GlyphIcon.qml#" \
	"$stubs"/MarathonOS/Shell/qmldir
# App icons as plain images (the shell's SVG provider is C++).
cat >"$stubs"/MarathonOS/Shell/MAppIcon.qml <<'QML'
import QtQuick
Image {
    property int size
    property bool loadAsync
    width: size
    height: size
    sourceSize: Qt.size(size, size)
}
QML
for mode in eink lcd; do
	MARATHON_FORCE_DPI=160 QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 ${KEEL_QML:+QML_IMPORT_PATH=$KEEL_QML} \
		qml -I "$src"/marathon-silica -I "$stubs" "$src"/docs/design/eink/Mockups.qml -- "$out" "$mode"
	MARATHON_FORCE_DPI=160 QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 ${KEEL_QML:+QML_IMPORT_PATH=$KEEL_QML} \
		qml -I "$src"/marathon-silica -I "$src"/apps/settings/tests/stubs \
		"$src"/docs/design/eink/SettingsMockup.qml -- "$out" "$mode"
done
rm -rf "$tmp"
