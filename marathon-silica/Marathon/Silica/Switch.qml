import QtQuick
import Sailfish.Silica as S
import "Activation.js" as Activation

S.Switch {
    id: root

    activeFocusOnTab: true
    Accessible.role: Accessible.CheckBox
    Accessible.name: Activation.iconName(icon.source)
    Accessible.checkable: true
    Accessible.checked: checked
    Accessible.onPressAction: root.clicked(null)
    Accessible.onToggleAction: root.clicked(null)
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
