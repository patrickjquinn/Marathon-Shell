import QtQuick
import Sailfish.Silica as S
import Sailfish.Silica.private as P

P.TabBar {
    id: root

    // Arrow keys move the selection; focus follows it.
    on_CurrentTabButtonChanged: {
        for (let p = root.Window.activeFocusItem; p; p = p.parent) {
            if (p === root) {
                if (root._currentTabButton)
                    root._currentTabButton.forceActiveFocus();
                return;
            }
        }
    }

    Accessible.role: Accessible.PageTabList
    Accessible.name: _currentTabButton ? _currentTabButton.title : ""

    // A tab's content scrolls up under the pinned bar, which is see-through
    // over a transparent app window.
    Rectangle {
        objectName: "tabBarBackdrop"
        anchors.fill: parent
        z: -1
        color: Qt.rgba(S.Theme.overlayBackgroundColor.r, S.Theme.overlayBackgroundColor.g, S.Theme.overlayBackgroundColor.b, 1)
        visible: root._tabView !== null && root._tabView.yOffset > 0
    }

    delegate: TabButton {
        required property var model

        _tabView: root._tabView
        title: model[root.titleRole] || ""
        icon.source: model[root.iconRole] || ""
        count: model[root.countRole] || 0
    }
}
