import QtQuick
import QtQuick.Window
import QtTest
import Sailfish.Silica 1.0 as Silica
import MarathonOS.Shell
import "../../shell/qml/components"

// A panel mounted sideways, as the MP01's: the compositor turns the
// window's content item 270 degrees (applySceneRotation), so the scene's
// axes are not the items'. Swipes are sent in the upright items' terms.
TestCase {
    name: "RotatedScene"
    when: windowShown

    Window {
        width: 800
        height: 600
        visible: true

        Item {
            id: upright

            width: 600
            height: 800
            y: 600
            transformOrigin: Item.TopLeft
            rotation: 270

            MarathonPageView {
                id: pages

                anchors.fill: parent
            }

            MarathonQuickSettings {
                id: qs

                width: parent.width
                height: drawnHeight
                maxHeight: 400
            }
        }
    }

    QtObject {
        id: shellStub

        property real maxQuickSettingsHeight: 400
    }

    SignalSpy {
        id: indexSpy

        signalName: "currentIndexChanged"
    }

    function initTestCase() {
        UIStore.shellRef = shellStub;
        const apps = pages.data.find(o => o && o.pinnedMode !== undefined);
        for (let i = 0; i < 40; ++i)
            apps.append({
                "id": "app" + i,
                "name": "App " + i,
                "icon": ""
            });
        // The pager settles on home once the apps load.
        wait(1000);
    }

    function cleanupTestCase() {
        UIStore.shellRef = null;
        UIStore.closeQuickSettings();
    }

    function swipe(item, from, to) {
        const touch = touchEvent(item);
        touch.press(0, item, from.x, from.y).commit();
        for (let i = 1; i <= 10; ++i) {
            wait(16);
            touch.move(0, item, from.x + (to.x - from.x) * i / 10, from.y + (to.y - from.y) * i / 10).commit();
        }
        touch.release(0, item, to.x, to.y).commit();
    }

    function test_epaperPagesTurnOnASidewaysPanel_data() {
        return [
            {
                tag: "left",
                dx: -150,
                to: 3
            },
            {
                tag: "right",
                dx: 150,
                to: 1
            },
            {
                tag: "up the page",
                dx: 0,
                dy: -150,
                to: 2
            }
        ];
    }

    function test_epaperPagesTurnOnASidewaysPanel(data) {
        MMotion.instant = true;
        UIStore.closeQuickSettings();
        const list = findChild(pages, "pageList");
        tryVerify(() => list.count > 3);
        pages.jumpToIndex(2);
        tryCompare(list, "currentIndex", 2);
        let icon = null;
        tryVerify(() => (icon = findChild(list.currentItem, "appIcon-2")) !== null);
        const p = icon.mapToItem(pages, icon.width / 2, icon.height / 2);
        indexSpy.target = list;
        indexSpy.clear();
        swipe(pages, p, Qt.point(p.x + data.dx, p.y + (data.dy || 0)));
        compare(list.currentIndex, data.to);
        compare(indexSpy.count, data.to === 2 ? 0 : 1);
        MMotion.instant = false;
    }

    // At the end of its content, where the shade's own swipe takes over.
    function openAtTheEnd() {
        UIStore.openQuickSettings();
        tryCompare(qs, "drawnHeight", 400);
        const f = findChild(qs, "shadeScroll");
        f.contentY = f.contentHeight - f.height;
        verify(f.atYEnd);
    }

    function test_epaperShadeClosesOnASidewaysPanel() {
        MMotion.instant = true;
        openAtTheEnd();
        swipe(qs, Qt.point(300, 300), Qt.point(300, 180));
        verify(!UIStore.quickSettingsOpen);
        MMotion.instant = false;
    }

    SignalSpy {
        id: scrollSpy

        signalName: "contentYChanged"
    }

    // E-paper: overflowing content moves a page, less a row, in one jump.
    function test_epaperShadePagesOnASidewaysPanel() {
        MMotion.instant = true;
        UIStore.openQuickSettings();
        tryCompare(qs, "drawnHeight", 400);
        const f = findChild(qs, "shadeScroll");
        f.contentY = 0;
        verify(f.overflows);
        verify(!f.interactive);
        scrollSpy.target = f;
        scrollSpy.clear();
        swipe(qs, Qt.point(300, 300), Qt.point(300, 180));
        verify(UIStore.quickSettingsOpen);
        compare(scrollSpy.count, 1);
        const page = 400 - Silica.Theme.itemSizeSmall;
        compare(f.contentY, Math.min(page, f.contentHeight - f.height));
        swipe(qs, Qt.point(300, 180), Qt.point(300, 300));
        compare(f.contentY, 0);
        MMotion.instant = false;
    }

    function test_shadeFollowsUpOnASidewaysPanel() {
        openAtTheEnd();
        swipe(qs, Qt.point(300, 300), Qt.point(300, 100));
        verify(!UIStore.quickSettingsOpen);
    }
}
