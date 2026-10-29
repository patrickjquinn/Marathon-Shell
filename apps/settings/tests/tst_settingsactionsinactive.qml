import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Keel.Actions 1.0
import ".."

// app.show for a Settings that is still starting: a page pushed before the
// first one sat under it. It waits for the first page, and no longer for
// the app to be active, which an app started in the background never was.
TestCase {
    id: testCase

    name: "SettingsActionsInactive"
    when: windowShown

    QtObject {
        id: app

        property QtObject pageStack: QtObject {
            property int depth: 0
        }
        property var opened: []

        function openPage(name, operation, replace) {
            opened = opened.concat([[name, operation, replace]]);
            return true;
        }
    }

    SettingsActions {
        app: app
    }

    function show(page) {
        const call = KeelActions.invoke("app.show", {
            page: page
        });
        tryCompare(call, "finished", true);
        verify(call.succeeded, call.errorMessage);
    }

    function test_pageWaitsForTheFirstPage() {
        show("wifi");
        show("battery");
        compare(app.opened, []);
        app.pageStack.depth = 1;
        compare(app.opened, [["battery", PageStackAction.Immediate, true]]);
        show("updates");
        compare(app.opened.length, 2);
        compare(app.opened[1][0], "updates");
        app.pageStack.depth = 2;
        compare(app.opened.length, 2);
    }
}
