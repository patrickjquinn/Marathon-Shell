import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    name: "PageViewHub"
    when: windowShown

    Window {
        width: 720
        height: 720
        visible: true

        MarathonPageView {
            id: pages

            anchors.fill: parent
        }
    }

    function pageView() {
        return findChild(pages, "pageList");
    }

    // E-paper: a release lands on its page in the same frame, flick or not.
    function test_releaseLandsAtOnceOnEpaper_data() {
        return [
            {
                tag: "flick",
                steps: 10,
                stepMs: 5,
                next: true
            },
            {
                tag: "slow",
                steps: 20,
                stepMs: 30,
                next: false
            }
        ];
    }

    function test_releaseLandsAtOnceOnEpaper(data) {
        MMotion.instant = true;
        pages.jumpToIndex(1);
        const list = pageView();
        tryCompare(list, "currentIndex", 1);
        const x0 = list.contentX;
        const y = pages.height / 2;
        // From Frames toward home.
        mousePress(pages, 600, y);
        for (let i = 1; i <= data.steps; ++i)
            mouseMove(pages, 600 - 240 * i / data.steps, y, data.stepMs);
        mouseRelease(pages, 360, y);
        compare(list.currentIndex, data.next ? 2 : 1);
        compare(list.contentX, x0 + (data.next ? list.width : 0));
        verify(!list.moving);
        MMotion.instant = false;
    }

    function test_leavingTheHubClosesTheWeather() {
        pages.jumpToIndex(0);
        const list = findChild(pages, "weatherFlick");
        tryVerify(() => list !== null);
        const sheet = list.parent;
        sheet.open = true;
        verify(pages.hubOverlayOpen);
        pages.navigateToPage(-1);
        verify(!sheet.open);
        verify(!pages.hubOverlayOpen);
    }
}
