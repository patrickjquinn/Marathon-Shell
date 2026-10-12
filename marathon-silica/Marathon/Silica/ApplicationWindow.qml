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

    // Marathon's pill is the back control; Silica's back glow on the page
    // edge would only duplicate it.
    Binding {
        target: root.pageStack ? root.pageStack._pageStackIndicator : null
        property: "visible"
        value: false
        when: root.pageStack !== null && root.pageStack._pageStackIndicator !== null
    }
}
