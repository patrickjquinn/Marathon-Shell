import QtQuick
import Sailfish.Silica as S
import "Activation.js" as Activation
import "Fling.js" as Fling

S.ListItem {
    id: root

    activeFocusOnTab: true

    // Android's tap timeout: the press shows once it hasn't become a scroll
    // (the view steals and cancels it first); a quick tap still flashes.
    highlighted: (down && !tapTimeout.running) || menuOpen
    _showPress: highlighted || tapFlash.running
    onClicked: tapFlash.restart()

    Timer {
        id: tapTimeout

        interval: Fling.tapTimeout
        running: root.pressed
    }

    Timer {
        id: tapFlash

        interval: S.Theme.minimumPressHighlightTime
    }

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
