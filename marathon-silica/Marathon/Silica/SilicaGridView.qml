import QtQuick
import Sailfish.Silica as S
import "ViewKeys.js" as ViewKeys

S.SilicaGridView {
    id: root

    // Silica declares these views against QtQuick 2.0, which predates
    // these properties, so they can only be set by name.
    Binding { target: root; property: "activeFocusOnTab"; value: true }
    Binding { target: root; property: "keyNavigationEnabled"; value: true }

    Accessible.role: Accessible.List
    // As SilicaListView: keep focus in a header search field while it filters.
    property Item _headerFocus

    function _inHeaderOrFooter(item) {
        for (let p = item; p && p !== root; p = p.parent) {
            if (p === root.headerItem || p === root.footerItem)
                return true;
        }
        return false;
    }

    Connections {
        target: root.Window.window
        function onActiveFocusItemChanged() {
            if (!root)
                return;
            const item = root.Window.activeFocusItem;
            if (root._inHeaderOrFooter(item))
                root._headerFocus = item;
            else if (item !== root.currentItem)
                root._headerFocus = null;
        }
    }

    onActiveFocusChanged: if (activeFocus && currentItem && !_inHeaderOrFooter(Window.activeFocusItem)) currentItem.forceActiveFocus()
    onCurrentItemChanged: {
        if (_headerFocus && _headerFocus.visible && Window.activeFocusItem === currentItem)
            _headerFocus.forceActiveFocus();
        else if (activeFocus && currentItem && !_inHeaderOrFooter(Window.activeFocusItem))
            currentItem.forceActiveFocus();
    }
    Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Up || event.key === Qt.Key_Down || event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown)
            root._headerFocus = null;
        if (ViewKeys.openPulley(root, event))
            return;
        switch (event.key) {
        case Qt.Key_Home: root.currentIndex = 0; root.positionViewAtBeginning(); break;
        case Qt.Key_End: root.currentIndex = root.count - 1; root.positionViewAtEnd(); break;
        default: return;
        }
        event.accepted = true;
    }
}
