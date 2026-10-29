import QtQuick
import Sailfish.Silica as S
import "Activation.js" as Activation

S.ComboBox {
    id: root

    function _itemCount() {
        let n = 0;
        if (root.menu)
            root.menu._foreachMenuItem(function () {
                n++;
                return true;
            });
        return n;
    }

    function _openFromKeyboard() {
        root._controller.openMenu();
        if (root.menu && root.menu.active && root.menu.takeKeyboardFocus)
            root.menu.takeKeyboardFocus(root, root.currentItem);
    }

    activeFocusOnTab: true
    Accessible.role: Accessible.ComboBox
    Accessible.name: value !== "" ? label + ": " + value : label
    Accessible.description: description
    Accessible.onPressAction: root._openFromKeyboard()
    Keys.onPressed: function (event) {
        if (!root.enabled)
            return;
        if (Activation.isActivationKey(event)) {
            root._openFromKeyboard();
        } else if (event.key === Qt.Key_Down) {
            root.currentIndex = Math.min(root._itemCount() - 1, root.currentIndex + 1);
        } else if (event.key === Qt.Key_Up) {
            root.currentIndex = Math.max(0, root.currentIndex - 1);
        } else {
            return;
        }
        event.accepted = true;
    }

    FocusFrame {
        parent: root
    }
}
