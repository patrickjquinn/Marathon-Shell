import QtQuick
import QtQuick.Window
import QtTest
import Keel 1.0
import Sailfish.Silica 1.0
import "../../shell/qml/components"

TestCase {
    name: "KeelAmbienceBackground"
    when: windowShown

    Window {
        width: 360
        height: 720
        visible: true

        KeelAmbienceBackground {
            id: bg
            anchors.fill: parent
            wallpaper: Qt.resolvedUrl("../../shell/resources/wallpapers/dawn.svg")
            light: false
        }
    }

    function test_loadsBlurredWallpaperThroughKeel() {
        tryVerify(() => bg.ready, 5000);
        const src = findChild(bg, "wallpaper").source.toString();
        verify(src.startsWith("image://keelambience/" + encodeURIComponent(bg.wallpaper)));
        verify(src.indexOf("w=360") > 0 && src.indexOf("h=720") > 0);
    }

    function test_darkSchemeDimsTowardsBlack() {
        bg.light = false;
        tryVerify(() => bg.ready, 5000);
        const tone = findChild(bg, "tone");
        compare(tone.color, Qt.color("black"));
        compare(tone.opacity, 0.62);
        verify(findChild(bg, "dimmer").visible);
    }

    function test_lightSchemeWashesTowardsWhite() {
        bg.light = true;
        tryVerify(() => bg.ready, 5000);
        const tone = findChild(bg, "tone");
        compare(tone.color, Qt.color("white"));
        compare(tone.opacity, 0.45);
        verify(!findChild(bg, "dimmer").visible);
        bg.light = false;
    }

    function test_loadsOffTheGuiThread() {
        verify(findChild(bg, "wallpaper").asynchronous);
    }

    function test_hiddenBackgroundRequestsNothing() {
        bg.visible = false;
        compare(findChild(bg, "wallpaper").source.toString(), "");
        bg.visible = true;
        tryVerify(() => bg.ready, 5000);
    }

    function test_anotherWallpaperCrossFades() {
        tryVerify(() => bg.ready, 5000);
        const before = findChild(bg, "wallpaper").source;
        const previous = findChild(bg, "previousWallpaper");
        bg.wallpaper = Qt.resolvedUrl("../../shell/resources/wallpapers/carbon.svg");
        compare(previous.source, before);
        tryVerify(() => previous.visible && previous.opacity < 1, 5000);
        verify(bg.ready);
        tryVerify(() => !previous.visible && previous.source.toString() === "", 2000);
        bg.wallpaper = Qt.resolvedUrl("../../shell/resources/wallpapers/dawn.svg");
        tryVerify(() => previous.source.toString() === "", 2000);
    }

    function test_resizeSwapsWithoutFading() {
        tryVerify(() => bg.ready, 5000);
        bg.anchors.fill = undefined;
        bg.width = 300;
        compare(findChild(bg, "previousWallpaper").opacity, 0);
        bg.anchors.fill = bg.parent;
        tryVerify(() => bg.ready, 5000);
    }

    function test_noWallpaperDrawsNothingButTheBase() {
        bg.wallpaper = "";
        verify(!bg.ready);
        verify(!findChild(bg, "tone").visible);
        bg.wallpaper = Qt.resolvedUrl("../../shell/resources/wallpapers/dawn.svg");
    }
}
