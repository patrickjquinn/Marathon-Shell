import QtQuick
import Sailfish.Silica as S
import Sailfish.Silica.private as P

S.ContextMenu {
    id: root

    property Item _keyboardReturnFocus

    Accessible.role: Accessible.PopupMenu

    // Called by the opener after open(): keys now move through the menu,
    // and focus goes back to returnFocus when it closes.
    function takeKeyboardFocus(returnFocus, highlighted) {
        _keyboardReturnFocus = returnFocus;
        root.forceActiveFocus();
        root._setHighlightedItem(highlighted || null);
    }

    function _menuItems() {
        const items = [];
        root._foreachMenuItem(function (item) {
            if (item.visible && item.enabled)
                items.push(item);
            return true;
        });
        return items;
    }

    function _step(delta) {
        const items = _menuItems();
        if (items.length === 0)
            return;
        const at = items.indexOf(root._highlightedItem);
        const next = at < 0 ? (delta > 0 ? 0 : items.length - 1) : Math.max(0, Math.min(items.length - 1, at + delta));
        root._setHighlightedItem(items[next]);
    }

    // Keel's outside-press handler closes the menu while filtering the press,
    // which disables it and lets the press reach the control underneath.
    // This one outlives the close until the event loop turns.
    property bool _guarding
    property Item _outsideGuard: P.InverseMouseArea {
        parent: root
        anchors.fill: parent
        enabled: root._guarding && root._closeOnOutsideClick
        stealPress: true
        onPressedOutside: root.close()
    }

    onActiveChanged: {
        if (active)
            _guarding = true;
        else
            Qt.callLater(() => _guarding = active);
        if (!active && _keyboardReturnFocus) {
            const back = _keyboardReturnFocus;
            _keyboardReturnFocus = null;
            if (root.activeFocus)
                back.forceActiveFocus();
        }
    }
    // A menu opened from the keyboard closes when focus moves elsewhere.
    onActiveFocusChanged: if (!activeFocus && active && _keyboardReturnFocus) close()

    Keys.onPressed: function (event) {
        switch (event.key) {
        case Qt.Key_Down: root._step(1); break;
        case Qt.Key_Up: root._step(-1); break;
        case Qt.Key_Home: root._step(-1000); break;
        case Qt.Key_End: root._step(1000); break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            if (root._highlightedItem)
                root._activatedMenuItem(root._highlightedItem);
            break;
        case Qt.Key_Escape: root.close(); break;
        default: return;
        }
        event.accepted = true;
    }
}
