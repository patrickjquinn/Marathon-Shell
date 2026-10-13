import QtQuick
import QtTest
import Keel 1.0
import "../../shell/qml/core"

TestCase {
    name: "AmbienceController"

    QtObject {
        id: fakeService
        property color baseColor: "#1040a0"
        property bool light: false
        property string wallpaperUrl: "file:///usr/share/marathon-shell/wallpapers/dawn.svg"
        property real pixelRatio: 1.25
        property var published: null
        signal seedChanged
        function publish(map) { published = map; }
    }

    QtObject {
        id: fakeSettings
        property real userScaleFactor: 1.25
    }

    AmbienceController {
        id: controller
        service: fakeService
        settings: fakeSettings
    }

    function test_publishesKeelKeys() {
        fakeService.seedChanged();
        const m = fakeService.published;
        verify(m);
        compare(m["/desktop/jolla/theme/color/highlight"], Ambience.highlightFromColor("#1040a0", 0));
        compare(m["/desktop/jolla/theme/color_scheme"], "lightondark");
        compare(m["/desktop/jolla/theme/wallpaper"], fakeService.wallpaperUrl);
    }

    function test_lightScheme() {
        fakeService.light = true;
        fakeService.seedChanged();
        compare(fakeService.published["/desktop/jolla/theme/color_scheme"], "darkonlight");
        fakeService.light = false;
    }

    function test_appliesPixelRatioToTheShell() {
        fakeService.seedChanged();
        compare(fakeService.published["/desktop/sailfish/silica/theme_pixel_ratio"], 1.25);
        compare(Ambience.pixelRatio, 1.25);
        fakeService.pixelRatio = 1.5;
        compare(Ambience.pixelRatio, 1.5);
        fakeService.pixelRatio = 1.25;
    }

    function test_textFollowsInterfaceSize() {
        fakeService.seedChanged();
        compare(fakeService.published["/desktop/jolla/theme/font/sizeMultiplier"], 1.25);
        fakeSettings.userScaleFactor = 1.5;
        compare(fakeService.published["/desktop/jolla/theme/font/sizeMultiplier"], 1.5);
        fakeSettings.userScaleFactor = 1.25;
    }

    function test_timeFormatForKeel() {
        compare(controller.keelTimeFormat("24h"), "24");
        compare(controller.keelTimeFormat("12h"), "12");
    }
}
