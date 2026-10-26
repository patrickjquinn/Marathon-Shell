import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    property var grid: null

    name: "AppGridEntrance"
    when: windowShown

    Window {
        id: window

        width: 360
        height: 1140
        visible: true
    }

    Component {
        id: gridComponent

        MarathonAppGrid {
            anchors.fill: parent
            appModel: QtObject {
                readonly property var apps: [{
                        "id": "phone",
                        "name": "Phone",
                        "icon": ""
                    }, {
                        "id": "mail",
                        "name": "Mail",
                        "icon": ""
                    }, {
                        "id": "clock",
                        "name": "Clock",
                        "icon": ""
                    }, {
                        "id": "maps",
                        "name": "Maps",
                        "icon": ""
                    }]
                readonly property int count: apps.length
                function getAppAtIndex(i) {
                    return apps[i] || null;
                }
            }
        }
    }

    function icon(i) {
        const item = findChild(grid, "appIcon-" + i);
        verify(item, "appIcon-" + i);
        return item;
    }

    function init() {
        grid = createTemporaryObject(gridComponent, window.contentItem);
        verify(grid);
    }

    function cleanup() {
        MMotion.reduceMotion = false;
    }

    function test_iconsShowWithoutAnEntrance() {
        for (let i = 0; i < 4; ++i)
            compare(icon(i).contentColumn.opacity, 1);
    }

    function test_heldIconsWaitHidden() {
        grid.entranceHeld = true;
        for (let i = 0; i < 4; ++i)
            compare(icon(i).contentColumn.opacity, 0);
    }

    function test_entranceBuildsInOneIconAfterAnother() {
        grid.entranceHeld = true;
        grid.playEntrance();
        tryVerify(() => icon(0).contentColumn.opacity === 1 && icon(3).contentColumn.opacity === 0, 1000, "first in while the last waits");
        tryCompare(icon(3).contentColumn, "opacity", 1, 1000);
        compare(icon(3).contentColumn.anchors.verticalCenterOffset, 0);
        grid.entranceHeld = false;
        compare(icon(3).contentColumn.opacity, 1);
    }

    function test_reduceMotionFadesTogetherWithoutRising() {
        MMotion.reduceMotion = true;
        grid.entranceHeld = true;
        grid.playEntrance();
        compare(icon(3).contentColumn.anchors.verticalCenterOffset, 0);
        tryCompare(icon(3).contentColumn, "opacity", 1, 1000);
    }
}
