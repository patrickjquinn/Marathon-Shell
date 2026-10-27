import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

TestCase {
    id: testCase
    name: "Remorse"
    when: windowShown
    visible: true
    width: 540; height: 960

    property var log: []

    Component {
        id: app
        ApplicationWindow {
            width: 540; height: 960
            initialPage: Component {
                Page {
                    property alias popup: popup
                    property alias button: button
                    RemorsePopup { id: popup }
                    Button { id: button; text: "Delete all" }
                }
            }
        }
    }

    function init() { log = []; }

    function test_escapeCancelsPendingRemorse() {
        const a = createTemporaryObject(app, testCase);
        tryVerify(function () { return a.pageStack.currentPage !== null; });
        const p = a.pageStack.currentPage;
        p.button.forceActiveFocus();
        p.popup.execute("Deleting", function () { testCase.log.push("deleted"); }, 300);
        verify(p.popup.pending);
        keyClick(Qt.Key_Escape);
        verify(!p.popup.pending);
        wait(400);
        compare(log, []);
        verify(p.button.activeFocus);
        compare(a.pageStack.depth, 1);
    }

    function test_remorseRunsWhenNotCancelled() {
        const a = createTemporaryObject(app, testCase);
        tryVerify(function () { return a.pageStack.currentPage !== null; });
        a.pageStack.currentPage.popup.execute("Deleting", function () { testCase.log.push("deleted"); }, 200);
        tryCompare(testCase, "log", ["deleted"], 10000);
    }
}
