import QtQuick
import Sailfish.Silica as S

S.ApplicationWindow {
    id: root

    property string appId: ""

    signal minimizeRequested

    // Called by the app runner for the system back gesture.
    function handleBack() {
        if (root.pageStack.depth > 1) {
            root.pageStack.pop();
            return true;
        }
        root.minimizeRequested();
        return true;
    }

}
