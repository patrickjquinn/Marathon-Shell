import MarathonOS.Shell
import QtQuick
import Sailfish.Silica 1.0 as Silica

// A round glass button: a disc lit from above and tinted with the ambience,
// with a white digit or icon. "primary" is the lit, emphasised one
// (play/pause, confirm).
Item {
    id: root

    property string iconName: ""
    property string text: ""
    property int iconSize: 28
    property color iconColor: Silica.Theme.primaryColor
    property color textColor: Silica.Theme.primaryColor
    property bool disabled: false
    property string variant: "primary"
    property int buttonSize: 62
    property string a11yName: text.length > 0 ? text : iconName
    property bool down: mouseArea.pressed
    readonly property real scaleFactor: Constants.scaleFactor || 1
    readonly property real diameter: Math.round(buttonSize * scaleFactor)
    // How far the touch area reaches past the circle; at least to the 7 mm minimum.
    property real hitMargin: Math.max(0, (Constants.touchTargetMinimum - diameter) / 2)
    readonly property bool hasText: text !== ""

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

    Silica.GlassSurface {
        anchors.centerIn: parent
        width: Math.min(root.width, root.height)
        height: width
        scale: root.down ? 0.94 : 1
        lit: root.variant === "primary"
        pressed: root.down

        Behavior on scale {
            NumberAnimation {
                duration: MMotion.quick
                easing.type: Easing.OutCubic
            }
        }

        GlyphIcon {
            visible: !root.hasText
            anchors.centerIn: parent
            name: root.iconName
            size: Math.min(Math.round(root.iconSize * root.scaleFactor), Math.floor(parent.width * 0.45))
            color: root.iconColor
        }

        Text {
            visible: root.hasText
            anchors.centerIn: parent
            text: root.text
            color: root.textColor
            font.family: Silica.Theme.fontFamilyHeading
            font.pixelSize: Math.min(Silica.Theme.fontSizeExtraLarge, Math.floor(parent.width * 0.45))
            font.weight: Font.Light
        }
    }

    MouseArea {
        id: mouseArea

        anchors.fill: parent
        anchors.margins: -root.hitMargin
        enabled: !root.disabled
        onPressed: MHaptics.lightImpact()
        onClicked: root.clicked()
    }
}
