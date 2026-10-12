import QtQuick
import Sailfish.Silica.private as P
import "Activation.js" as Activation

P.TabButton {
    id: root

    function _select(index) {
        if (root._tabView && root.tabCount > 0)
            root._tabView.moveTo((index + root.tabCount) % root.tabCount);
    }

    objectName: "tabButton"
    activeFocusOnTab: true
    Accessible.role: Accessible.PageTab
    Accessible.name: title
    Accessible.selected: isCurrentTab
    Accessible.onPressAction: root.clicked(null)
    Keys.onPressed: function (event) {
        if (Activation.isActivationKey(event))
            root.clicked(null);
        else if (event.key === Qt.Key_Right)
            root._select(root.tabIndex + 1);
        else if (event.key === Qt.Key_Left)
            root._select(root.tabIndex - 1);
        else
            return;
        event.accepted = true;
    }

    FocusFrame {
        parent: root
    }
}
