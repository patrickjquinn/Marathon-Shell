import QtQuick
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    name: "StatusBar"
    when: windowShown

    width: 1032
    height: 80

    MarathonStatusBar {
        id: bar

        width: 1032
    }

    function cleanup() {
        Constants.displayCutout = Qt.rect(0, 0, 0, 0);
    }

    function test_clockCentredWithoutCutout() {
        const clock = findChild(bar, "statusClock");
        const battery = findChild(bar, "statusBattery");
        verify(!bar.aroundCutout);
        fuzzyCompare(clock.x + clock.width / 2, bar.width / 2, 1);
        verify(battery.x < clock.x);
    }

    function test_clockAndIndicatorsClearTheCutout() {
        Constants.displayCutout = Qt.rect(310, 0, 414, 66);
        verify(bar.aroundCutout);
        const clock = findChild(bar, "statusClock");
        const battery = findChild(bar, "statusBattery");
        const radios = findChild(bar, "statusRadios");
        verify(clock.width > 0);
        verify(clock.x + clock.width <= 310, "clock ends at " + (clock.x + clock.width));
        verify(radios.x >= 724, "radios start at " + radios.x);
        verify(battery.x >= radios.x + radios.width, "battery sits right of the radios");
        verify(battery.x + battery.width <= bar.width);
    }

    function test_offCentreCutoutKeepsTheLayout() {
        Constants.displayCutout = Qt.rect(40, 0, 60, 60);
        verify(!bar.aroundCutout);
        const clock = findChild(bar, "statusClock");
        fuzzyCompare(clock.x + clock.width / 2, bar.width / 2, 1);
    }
}
