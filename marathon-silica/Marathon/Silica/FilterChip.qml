import QtQuick
import Sailfish.Silica as S
import "Activation.js" as Activation

// A toggle that narrows a list: "Unread", "Today", a category. Shown the
// way TextSwitch shows its state, a glass dot that lights when on.
S.BackgroundItem {
    id: root

    property alias text: label.text
    property bool checked
    property bool automaticCheck: true

    width: indicator.width + label.implicitWidth + S.Theme.paddingLarge
    height: S.Theme.itemSizeExtraSmall
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

    S.GlassItem {
        id: indicator

        objectName: "chipIndicator"
        anchors.verticalCenter: parent.verticalCenter
        width: S.Theme.itemSizeExtraSmall * 0.75
        height: width
        opacity: root.enabled ? 1.0 : S.Theme.opacityLow
        dimmed: !root.checked
        falloffRadius: root.checked ? defaultFalloffRadius : (root.palette.colorScheme === S.Theme.LightOnDark ? 0.075 : 0.1)
        color: root.highlighted ? root.palette.highlightColor : dimmed ? root.palette.primaryColor : S.Theme.lightPrimaryColor
        backgroundColor: root.checked ? root.palette.backgroundGlowColor : "transparent"
    }

    S.Label {
        id: label

        anchors.left: indicator.right
        anchors.verticalCenter: parent.verticalCenter
        font.pixelSize: S.Theme.fontSizeSmall
        color: root.checked || root.highlighted ? S.Theme.highlightColor : S.Theme.primaryColor
    }

    FocusFrame {
        parent: root
    }
}
