import QtQuick
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

    delegate: TabButton {
        required property var model

        _tabView: root._tabView
        title: model[root.titleRole] || ""
        icon.source: model[root.iconRole] || ""
        count: model[root.countRole] || 0
    }
}
