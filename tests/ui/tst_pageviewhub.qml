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

    // As on the panel: nothing redraws during an e-paper swipe, so Qt can
    // deliver the whole movement as one update at release; and the press
    // lands on an app icon, whose MouseArea takes it first.
    function test_epaperSwipeOnAnIconInOneUpdate_data() {
        return [
            {
                tag: "short",
                dx: 40,
                turns: 0
            },
            {
                tag: "past a tenth",
                dx: 300,
                turns: 1
            }
        ];
    }

    function test_epaperSwipeOnAnIconInOneUpdate(data) {
        MMotion.instant = true;
        const apps = pages.data.find(o => o && o.pinnedMode !== undefined);
        for (let i = 0; i < 40; ++i)
            apps.append({
                "id": "app" + i,
                "name": "App " + i,
                "icon": ""
            });
        const list = pageView();
        tryVerify(() => list.count > 3);
        pages.jumpToIndex(2);
        tryCompare(list, "currentIndex", 2);
        let icon = null;
        tryVerify(() => (icon = findChild(list.currentItem, "appIcon-2")) !== null);
        const p = icon.mapToItem(pages, icon.width / 2, icon.height / 2);
        const x0 = list.contentX;
        indexSpy.target = list;
        indexSpy.clear();
        const touch = touchEvent(pages);
        touch.press(0, pages, p.x, p.y).commit();
        wait(400);
        touch.move(0, pages, p.x - data.dx, p.y).commit();
        touch.release(0, pages, p.x - data.dx, p.y).commit();
        compare(indexSpy.count, data.turns);
        compare(list.contentX, x0 + data.turns * list.width);
        apps.clear();
        MMotion.instant = false;
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
