import QtQuick
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    id: tc

    name: "KeelCoverView"

    // Covers are filed by app id; the view must look its app up again
    // whenever that app's cover changes or the view is given another app.
    QtObject {
        id: compositor

        // Pushed to, never reassigned: the view's binding reads it through
        // coverSurface() and would otherwise loop.
        readonly property var lookups: []
        signal coverChanged(string appId)
        function coverSurface(appId) {
            lookups.push(appId);
            return null;
        }
    }

    KeelCoverView {
        id: view

        compositor: compositor
        appId: "messages"
    }

    function test_relooksUpAfterCoverChangeAndAppSwap() {
        compositor.lookups.length = 0;
        compositor.coverChanged("messages");
        compare(compositor.lookups, ["messages"]);
        compositor.coverChanged("other");
        compare(compositor.lookups, ["messages"]);
        view.appId = "megapixels";
        compare(compositor.lookups, ["messages", "megapixels"]);
    }
}
