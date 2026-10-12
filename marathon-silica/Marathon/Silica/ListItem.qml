import QtQuick
import Sailfish.Silica as S
import "Activation.js" as Activation

S.ListItem {
    id: root

    activeFocusOnTab: true
    Accessible.role: Accessible.ListItem
    Accessible.onPressAction: root.clicked(null)
    Keys.onPressed: function (event) {
        if (!root.enabled)
            return;
        if (Activation.isMenuKey(event) && root.menu) {
            event.accepted = true;
            root._openMenuFromKeyboard();
        } else if (Activation.isActivationKey(event)) {
            event.accepted = true;
            root.clicked(null);
        }
    }

    function _openMenuFromKeyboard() {
        const menu = root.openMenu();
        if (menu && menu.takeKeyboardFocus)
            menu.takeKeyboardFocus(root, null);
    }

    FocusFrame {
        parent: root
    }
}
