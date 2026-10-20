import MarathonOS.Shell
import QtQuick
import Sailfish.Silica 1.0 as Silica

// A round button in the glass-ring style: a thin ring with a light
// digit or icon, filled with the ambience highlight when pressed. "primary"
// is the lit, emphasised one (play/pause, confirm).
Item {
    id: root

    property string iconName: ""
    property string text: ""
    property int iconSize: 28
    property color iconColor: Silica.Theme.highlightColor
    property color textColor: Silica.Theme.primaryColor
    property bool disabled: false
    property string variant: "primary"
    property int buttonSize: 62
    property string a11yName: text.length > 0 ? text : iconName
    property bool down: mouseArea.pressed
    readonly property real scaleFactor: Constants.scaleFactor || 1
    readonly property real diameter: Math.round(buttonSize * scaleFactor)
    readonly property bool hasText: text !== ""
    readonly property bool lit: variant === "primary" || down

    signal clicked

    Accessible.role: Accessible.Button
    Accessible.name: a11yName
    Accessible.onPressAction: {
        if (!disabled)
            clicked();
    }
    implicitWidth: diameter
    implicitHeight: diameter
    opacity: disabled ? Silica.Theme.opacityLow : 1

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(root.width, root.height)
        height: width
        radius: width / 2
        scale: root.down ? 0.94 : 1
        color: root.lit ? Silica.Theme.rgba(Silica.Theme.highlightBackgroundColor, Silica.Theme.highlightBackgroundOpacity) : "transparent"
        border.width: Math.max(1, Math.round(Silica.Theme.paddingSmall / 4))
        border.color: root.lit ? Silica.Theme.highlightColor : Silica.Theme.rgba(Silica.Theme.primaryColor, 0.35)

        Behavior on scale {
            NumberAnimation { duration: MMotion.quick; easing.type: Easing.OutCubic }
        }

        GlyphIcon {
            visible: !root.hasText
            anchors.centerIn: parent
            name: root.iconName
            size: Math.min(Math.round(root.iconSize * root.scaleFactor), Math.floor(parent.width * 0.45))
            color: root.lit ? root.iconColor : Silica.Theme.primaryColor
        }

        Text {
            visible: root.hasText
            anchors.centerIn: parent
            text: root.text
            color: root.down ? Silica.Theme.highlightColor : root.textColor
            font.family: Silica.Theme.fontFamilyHeading
            font.pixelSize: Math.min(Silica.Theme.fontSizeExtraLarge, Math.floor(parent.width * 0.45))
            font.weight: Font.Light
        }
    }

    MouseArea {
        id: mouseArea

        anchors.fill: parent
        enabled: !root.disabled
        onPressed: MHaptics.lightImpact()
        onClicked: root.clicked()
    }
}
