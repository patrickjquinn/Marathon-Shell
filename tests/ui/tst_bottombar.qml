import QtQuick
import QtQuick.Window
import QtTest
import Sailfish.Silica 1.0 as Silica
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    name: "BottomBar"
    when: windowShown

    Window {
        width: 540
        height: 200
        visible: true

        MarathonBottomBar {
            id: bar
            y: 100
            width: 540
            currentPage: 0
            totalPages: 3
        }
    }

    SignalSpy { id: launchSpy; target: bar; signalName: "appLaunched" }
    SignalSpy { id: pageSpy; target: bar; signalName: "pageNavigationRequested" }

    function init() {
        launchSpy.clear();
        pageSpy.clear();
    }

    function test_noRingsAroundTheDock() {
        for (const name of ["dockPhone", "dockCamera"]) {
            const button = findChild(bar, name);
            verify(button, name);
            for (const child of button.children)
                verify(!(child instanceof Rectangle), name + " draws no ring");
        }
    }

    function test_rowClearsTheNavBar() {
        const gap = Silica.Theme.paddingMedium;
        const row = findChild(bar, "pageIndicatorRow");
        verify(row.y + row.height <= bar.height - gap, "indicators sit a gap above the nav bar");
        for (const name of ["dockPhone", "dockCamera", "pageScrub"]) {
            const area = findChild(bar, name);
            verify(area.y + area.height <= bar.height, name + " stays inside the bar");
            verify(area.height >= Silica.Theme.itemSizeExtraSmall, name + " is a full touch target");
        }
    }

    function test_dockTapLaunches() {
        const phone = findChild(bar, "dockPhone");
        mouseClick(phone);
        compare(launchSpy.count, 1);
        compare(launchSpy.signalArguments[0][0].id, "phone");
    }

    function test_dockDragDoesNotLaunch() {
        const camera = findChild(bar, "dockCamera");
        mousePress(camera, camera.width / 2, camera.height / 2);
        mouseMove(camera, camera.width / 2, camera.height / 2 - Silica.Theme.itemSizeLarge);
        mouseRelease(camera, camera.width / 2, camera.height / 2 - Silica.Theme.itemSizeLarge);
        compare(launchSpy.count, 0);
    }

    function test_tapPicksTheNearestIndicator() {
        const scrub = findChild(bar, "pageScrub");
        mouseClick(scrub, 1, scrub.height / 2);
        compare(pageSpy.signalArguments[0][0], -2);
        mouseClick(scrub, scrub.width - 1, scrub.height / 2);
        compare(pageSpy.signalArguments[1][0], 2);
    }

    function test_indicatorsTakeTheBackdropsTone() {
        const tone = findChild(bar, "indicatorTone");
        tone.light = true;
        verify(tone.secondary.r < 0.1, "dark over a light backdrop");
        tone.light = false;
        verify(tone.secondary.r > 0.9, "light over a dark one");
    }
}
