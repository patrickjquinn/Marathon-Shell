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

    function test_noWallpaperDrawsNothingButTheBase() {
        bg.wallpaper = "";
        verify(!bg.ready);
        verify(!findChild(bg, "tone").visible);
        bg.wallpaper = Qt.resolvedUrl("../../shell/resources/wallpapers/dawn.svg");
    }
}
