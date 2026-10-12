import QtQuick
import Sailfish.Silica as S
import "Activation.js" as Activation

S.BackgroundItem {
    id: root

    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.onPressAction: root.clicked(null)
    Keys.onPressed: function (event) {
        if (root.enabled && Activation.isActivationKey(event)) {
            event.accepted = true;
            root.clicked(null);
        }
    }

    FocusFrame {
        parent: root
    }
}
