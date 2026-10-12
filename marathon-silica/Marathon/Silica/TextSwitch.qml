import QtQuick
import Sailfish.Silica as S
import "Activation.js" as Activation

// Silica's TextSwitch with a pill toggle at the row's end in place of the
// glass dot before its label.
S.TextSwitch {
    id: root

    // Silica's toggle column, the first child of the base type.
    readonly property Item _glassToggle: children[0]

    leftMargin: S.Theme.horizontalPageMargin + S.Theme.paddingLarge - S.Theme.itemSizeExtraSmall
                - (palette.colorScheme === S.Theme.DarkOnLight ? S.Theme.paddingMedium : 0)
    _rightPadding: toggle.width + S.Theme.paddingMedium - S.Theme.paddingLarge

    activeFocusOnTab: true
    Accessible.role: Accessible.CheckBox
    Accessible.name: text
    Accessible.description: description
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

    Component.onCompleted: {
        _glassToggle.objectName = "glass";
        _glassToggle.visible = false;
    }

    SwitchPill {
        id: toggle

        control: root
        anchors.right: parent.right
        anchors.rightMargin: root.rightMargin
        anchors.verticalCenter: root._glassToggle.verticalCenter
    }

    FocusFrame {
        parent: root
    }
}
