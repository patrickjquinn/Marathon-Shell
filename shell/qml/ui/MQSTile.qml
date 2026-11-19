import QtQuick
import MarathonOS.Shell
import Sailfish.Silica 1.0 as Silica

// Quick Settings switch: a glass disc, lit with the ambience when on, its
// label beneath. Sized from Silica's units, so it grows with
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
    // Tab reaches each tile on a hardware keyboard; Return or Space toggles it.
    activeFocusOnTab: true
    Keys.onReturnPressed: toggled()
    Keys.onEnterPressed: toggled()
    Keys.onSpacePressed: toggled()

    Silica.GlassSurface {
        id: circle

        objectName: "ring"
        anchors.horizontalCenter: parent.horizontalCenter
        width: Silica.Theme.itemSizeSmall
        height: width
        scale: tileMouse.pressed ? 0.96 : 1.0
        lit: tile.on
        pressed: tileMouse.pressed || (tile.busy && busyPulse.bright)

        Behavior on scale {
            enabled: !MMotion.reduceMotion
            NumberAnimation {
                duration: MMotion.quick
                easing.type: Easing.OutQuad
            }
        }

        // A keyboard-focused tile wears a ring.
        Rectangle {
            anchors.fill: parent
            visible: tile.activeFocus
            radius: width / 2
            color: "transparent"
            border.width: Math.max(2, Math.round(Silica.Theme.paddingSmall / 2))
            border.color: Silica.Theme.highlightColor
        }

        GlyphIcon {
            anchors.centerIn: parent
            name: tile.iconName
            size: Silica.Theme.iconSizeSmall
            color: Silica.Theme.primaryColor
        }
    }

    Text {
        id: labelText

        anchors.top: circle.bottom
        anchors.topMargin: Silica.Theme.paddingSmall
        anchors.horizontalCenter: parent.horizontalCenter
        width: tile.width
        text: tile.label
        color: tile.on ? Silica.Theme.primaryColor : Silica.Theme.secondaryColor
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
