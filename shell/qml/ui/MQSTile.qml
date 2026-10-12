import QtQuick
import MarathonOS.Shell
import Sailfish.Silica 1.0 as Silica

// Quick Settings switch: a round icon lit with the ambience highlight
// when on, its label beneath. Sized from Silica's units, so it grows with
// the density and the user's interface size.
Item {
    id: tile

    property string iconName: "square"
    property string label: ""
    property bool on: false
    // One-shot actions (Screenshot, Power) are buttons, not switches.
    property bool checkable: true

    signal toggled

    implicitWidth: Silica.Theme.itemSizeExtraLarge
    implicitHeight: circle.height + Silica.Theme.paddingSmall + labelText.height + Silica.Theme.paddingMedium

    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.checkable: checkable
    Accessible.checked: checkable && on
    Accessible.onPressAction: toggled()

    Rectangle {
        id: circle

        anchors.horizontalCenter: parent.horizontalCenter
        width: Silica.Theme.itemSizeExtraSmall
        height: width
        radius: width / 2
        scale: tileMouse.pressed ? 0.92 : 1.0
        color: tile.on ? Silica.Theme.rgba(Silica.Theme.highlightBackgroundColor, Silica.Theme.highlightBackgroundOpacity)
                       : Silica.Theme.rgba(Silica.Theme.primaryColor, tileMouse.pressed ? 0.2 : 0.1)

        Behavior on color {
            enabled: !MMotion.reduceMotion
            ColorAnimation { duration: MMotion.quick }
        }
        Behavior on scale {
            enabled: !MMotion.reduceMotion
            NumberAnimation { duration: MMotion.quick; easing.type: Easing.OutBack }
        }

        GlyphIcon {
            anchors.centerIn: parent
            name: tile.iconName
            size: Silica.Theme.iconSizeSmall
            color: tile.on || tileMouse.pressed ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
        }
    }

    Text {
        id: labelText

        anchors.top: circle.bottom
        anchors.topMargin: Silica.Theme.paddingSmall
        anchors.horizontalCenter: parent.horizontalCenter
        width: tile.width
        text: tile.label
        color: tile.on ? Silica.Theme.highlightColor : Silica.Theme.secondaryColor
        font.family: Silica.Theme.fontFamily
        font.pixelSize: Silica.Theme.fontSizeExtraSmall
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
    }

    MouseArea {
        id: tileMouse

        anchors.fill: parent
        onClicked: tile.toggled()
    }
}
