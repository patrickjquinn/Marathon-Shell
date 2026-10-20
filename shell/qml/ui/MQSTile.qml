import QtQuick
import MarathonOS.Shell
import Sailfish.Silica 1.0 as Silica

// Quick Settings switch: a glass ring lit with the ambience highlight when
// on, its label beneath. Sized from Silica's units, so it grows with
// the density and the user's interface size.
Item {
    id: tile

    property string iconName: "square"
    property string label: ""
    property bool on: false
    // One-shot actions (Screenshot, Power) are buttons, not switches.
    property bool checkable: true
    // The backend is switching: pulse the ring as Silica's Switch.busy does.
    property bool busy: false

    signal toggled
    signal held

    implicitWidth: Silica.Theme.itemSizeExtraLarge
    implicitHeight: circle.height + Silica.Theme.paddingSmall + labelText.height

    Accessible.role: Accessible.Button
    Accessible.name: label
    Accessible.checkable: checkable
    Accessible.checked: checkable && on
    Accessible.onPressAction: toggled()

    Rectangle {
        id: circle

        objectName: "ring"
        anchors.horizontalCenter: parent.horizontalCenter
        width: Silica.Theme.itemSizeSmall
        height: width
        radius: width / 2
        scale: tileMouse.pressed ? 0.92 : 1.0
        // A glass ring, filled with the highlight when on.
        color: tile.on ? Silica.Theme.rgba(Silica.Theme.highlightBackgroundColor, Silica.Theme.highlightBackgroundOpacity)
                       : Silica.Theme.rgba(Silica.Theme.primaryColor, tileMouse.pressed ? 0.12 : 0)
        border.width: Math.max(1, Math.round(Silica.Theme.paddingSmall / 4))
        border.color: tile.busy ? Silica.Theme.rgba(Silica.Theme.highlightColor, busyPulse.bright ? 1 : Silica.Theme.opacityLow)
                    : tile.on ? Silica.Theme.highlightColor : Silica.Theme.rgba(Silica.Theme.primaryColor, 0.35)

        Behavior on border.color {
            enabled: tile.busy && !MMotion.reduceMotion
            ColorAnimation { duration: busyPulse.interval - 50; easing.type: Easing.InOutQuad }
        }
        Behavior on color {
            enabled: !MMotion.reduceMotion
            ColorAnimation { duration: MMotion.quick }
        }
        Behavior on scale {
            enabled: !MMotion.reduceMotion
            NumberAnimation { duration: MMotion.quick; easing.type: Easing.OutQuad }
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
        font.pixelSize: Silica.Theme.fontSizeTiny
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
    }

    Timer {
        id: busyPulse

        property bool bright: true

        objectName: "busyPulse"
        interval: 500
        repeat: true
        running: tile.busy && tile.visible && !MMotion.reduceMotion
        onRunningChanged: bright = true
        onTriggered: bright = !bright
    }

    MouseArea {
        id: tileMouse

        anchors.fill: parent
        onClicked: tile.toggled()
        onPressAndHold: tile.held()
    }
}
