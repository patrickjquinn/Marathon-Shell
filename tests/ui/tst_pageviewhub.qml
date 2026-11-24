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

    SignalSpy {
        id: contentXSpy

        signalName: "contentXChanged"
    }

    SignalSpy {
        id: indexSpy

        signalName: "currentIndexChanged"
    }

    // E-paper: the pages never follow the finger. A swipe short of a tenth
    // of the width moves nothing; past it the view cuts once to the next
    // page, however far the finger goes on.
    function test_epaperSwipeTurnsOnce_data() {
        return [
            {
                tag: "short",
                dx: 50,
                turns: 0
            },
            {
                tag: "past a tenth",
                dx: 100,
                turns: 1
            },
            {
                tag: "a long drag",
                dx: 500,
                turns: 1
            }
        ];
    }

    function test_epaperSwipeTurnsOnce(data) {
        MMotion.instant = true;
        pages.jumpToIndex(1);
        const list = pageView();
        tryCompare(list, "currentIndex", 1);
        const x0 = list.contentX;
        contentXSpy.target = list;
        indexSpy.target = list;
        contentXSpy.clear();
        indexSpy.clear();
        const y = pages.height / 2;
        mousePress(pages, 600, y);
        for (let i = 1; i <= 20; ++i)
            mouseMove(pages, 600 - data.dx * i / 20, y, 30);
        mouseRelease(pages, 600 - data.dx, y);
        compare(indexSpy.count, data.turns);
        compare(contentXSpy.count, data.turns);
        compare(list.currentIndex, 1 + data.turns);
        compare(list.contentX, x0 + data.turns * list.width);
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
