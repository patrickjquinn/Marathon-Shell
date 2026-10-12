import QtQuick
import Sailfish.Silica 1.0

ApplicationWindow {
    id: app

    property string appId: ""

    signal minimizeRequested

    function handleBack() {
        if (pageStack.depth > 1) {
            pageStack.pop();
            return true;
        }
        minimizeRequested();
        return true;
    }
}
