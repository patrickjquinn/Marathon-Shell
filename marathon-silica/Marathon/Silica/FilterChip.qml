import QtQuick
import Sailfish.Silica as S
import "Activation.js" as Activation

// A toggle that narrows a list: "Unread", "Today", a category.
S.BackgroundItem {
    id: root

    property alias text: label.text
    property bool checked
    property bool automaticCheck: true

    width: label.implicitWidth + 2 * S.Theme.paddingLarge
    height: Math.max(44, S.Theme.itemSizeExtraSmall * 0.75)
    _backgroundColor: "transparent"
    activeFocusOnTab: true
    onClicked: if (automaticCheck) checked = !checked
    Accessible.role: Accessible.CheckBox
    Accessible.name: text
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

    Rectangle {
        anchors.fill: parent
        anchors.margins: S.Theme.paddingSmall / 2
        radius: height / 2
        color: root.checked ? S.Theme.rgba(S.Theme.highlightBackgroundColor, S.Theme.highlightBackgroundOpacity)
                            : root.highlighted ? S.Theme.rgba(S.Theme.highlightBackgroundColor, S.Theme.opacityFaint) : "transparent"
        border.width: root.checked ? 0 : Math.max(1, Math.round(S.Theme.pixelRatio))
        border.color: S.Theme.rgba(S.Theme.primaryColor, S.Theme.opacityLow)
    }

    S.Label {
        id: label

        anchors.centerIn: parent
        font.pixelSize: S.Theme.fontSizeSmall
        color: root.checked || root.highlighted ? S.Theme.highlightColor : S.Theme.primaryColor
    }

    FocusFrame {
        parent: root
        radius: height / 2
    }
}
