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
        bg.darkest = 0.6;
        tryVerify(() => bg.ready, 5000);
        const tone = findChild(bg, "tone");
        compare(tone.color, Qt.color("white"));
        compare(tone.opacity, 0.45);
        verify(!findChild(bg, "dimmer").visible);
        bg.light = false;
        bg.darkest = 0;
    }

    // WCAG relative luminance of an sRGB grey.
    function luminance(v) {
        return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
    }

    function contrast(a, b) {
        return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
    }

    function test_aBrightWallpaperDeepensTheTone_data() {
        return [0.2, 0.5, 0.8, 1].map(b => ({
                    "tag": "brightest " + b,
                    "brightest": b
                }));
    }

    // The scheme's text over the brightest spot, toned: primary 4.5:1,
    // secondary (#bababa) 3:1.
    function test_aBrightWallpaperDeepensTheTone(data) {
        bg.light = false;
        bg.toneOpacity = 0.4;
        bg.brightest = data.brightest;
        const v = Math.pow(data.brightest, 1 / 2.4) * 1.055 - 0.055;
        const under = luminance(v * (1 - findChild(bg, "tone").opacity));
        verify(contrast(1, under) >= 4.5);
        verify(contrast(luminance(0xba / 255), under) >= 3);
        verify(findChild(bg, "tone").opacity >= 0.4);
        bg.brightest = 1;
        bg.toneOpacity = Qt.binding(() => bg.light ? 0.45 : 0.62);
    }

    function test_aDarkWallpaperWashesHarder_data() {
        return [0, 0.01, 0.1, 0.3].map(d => ({
                    "tag": "darkest " + d,
                    "darkest": d
                }));
    }

    function test_aDarkWallpaperWashesHarder(data) {
        bg.light = true;
        bg.darkest = data.darkest;
        const v = data.darkest <= 0.0031308 ? 12.92 * data.darkest : Math.pow(data.darkest, 1 / 2.4) * 1.055 - 0.055;
        const a = findChild(bg, "tone").opacity;
        const under = luminance(v * (1 - a) + a);
        verify(contrast(0, under) >= 4.5);
        verify(contrast(luminance(0x45 / 255), under) >= 3);
        bg.light = false;
        bg.darkest = 0;
    }

    function test_aDimWallpaperKeepsItsTone() {
        bg.light = false;
        bg.toneOpacity = 0.4;
        bg.brightest = 0.1;
        compare(findChild(bg, "tone").opacity, 0.4);
        bg.brightest = 1;
        bg.toneOpacity = Qt.binding(() => bg.light ? 0.45 : 0.62);
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
