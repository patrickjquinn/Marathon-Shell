import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    id: tc
    name: "AppGridHold"
    when: windowShown
    Window {
        id: win
        width: 360
        height: 1140
        visible: true
        MarathonAppGrid {
            id: grid
            anchors.fill: parent
            appModel: QtObject {
                readonly property var apps: [
                    {
                        "id": "phone",
                        "name": "Phone",
                        "icon": ""
                    },
                    {
                        "id": "mail",
                        "name": "Mail",
                        "icon": ""
                    }
                ]
                readonly property int count: apps.length
                function getAppAtIndex(i) {
                    return apps[i] || null;
                }
            }
        }
    }
    SignalSpy {
        id: edits
        target: grid
        signalName: "editRequested"
    }

    function cell() {
        let area = null;
        const walk = item => {
            for (let i = 0; i < item.children.length && !area; ++i) {
                const c = item.children[i];
                if (c.hasOwnProperty("isSearchGesture") && c.hasOwnProperty("held"))
                    area = c;
                else
                    walk(c);
            }
        };
        walk(grid);
        return area;
    }

    function test_holdStillEdits() {
        edits.clear();
        const a = cell();
        verify(a);
        mousePress(a, 20, 20);
        wait(Qt.styleHints.mousePressAndHoldInterval + 200);
        mouseRelease(a, 20, 20);
        compare(edits.count, 1);
    }

    function test_slowPullDoesNotEdit() {
        edits.clear();
        const a = cell();
        mousePress(a, 20, 20);
        for (let y = 22; y <= 60; y += 2) {
            mouseMove(a, 20, y);
            wait(Qt.styleHints.mousePressAndHoldInterval / 15);
        }
        wait(200);
        mouseRelease(a, 20, 60);
        compare(edits.count, 0);
    }
}
