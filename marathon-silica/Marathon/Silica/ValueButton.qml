import QtQuick
import Sailfish.Silica as S
import "Activation.js" as Activation

S.ValueButton {
    id: root

    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: value !== "" ? label + ": " + value : label
    Accessible.description: description
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
