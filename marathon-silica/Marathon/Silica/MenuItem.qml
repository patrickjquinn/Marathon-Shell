import QtQuick
import Sailfish.Silica as S
import "Activation.js" as Activation

S.MenuItem {
    id: root

    Accessible.role: Accessible.MenuItem
    Accessible.name: text
    Accessible.onPressAction: root.clicked()
    Keys.onPressed: function (event) {
        if (root.enabled && Activation.isActivationKey(event)) {
            event.accepted = true;
            root.clicked();
        }
    }
}
