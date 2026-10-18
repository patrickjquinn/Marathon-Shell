import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Keel.Actions 1.0
import ".."

// app.show for Settings in the background: a page pushed then sat under the
// first page once the app was raised.
TestCase {
    id: testCase

    name: "SettingsActionsInactive"
    when: windowShown

    QtObject {
        id: app

        property bool applicationActive: false
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
        const call = KeelActions.invoke("app.show", { page: page });
        tryCompare(call, "finished", true);
        verify(call.succeeded, call.errorMessage);
    }

    function test_pageWaitsUntilActive() {
        show("wifi");
        show("battery");
        compare(app.opened, []);
        app.applicationActive = true;
        compare(app.opened, [["battery", PageStackAction.Immediate, true]]);
        show("updates");
        compare(app.opened.length, 2);
        compare(app.opened[1][0], "updates");
        app.applicationActive = false;
        app.applicationActive = true;
        compare(app.opened.length, 2);
    }
}
