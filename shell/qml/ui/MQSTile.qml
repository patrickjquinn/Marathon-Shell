import QtQuick
import MarathonOS.Shell
import Sailfish.Silica 1.0 as Silica

// Quick Settings switch: a glass tile, lit with the ambience when on, that
// says what it is and how it stands ("SKYZMTGV", "Auto · 24%"). When on it
// also wears Silica's Switch glow. A wide tile lays out in a row
// and, as BB10's quick settings did, tapping its name opens its settings;
// the rest of a tile switches it, and holding it does what `held` says.
Item {
    id: tile

    property string iconName: "square"
    property string label: ""
    property string status: ""
    property bool on: false
    // One-shot actions (Screenshot, Camera) are buttons, not switches.
    property bool checkable: true
    property bool wide: false
    // The backend is switching: pulse the tile as Silica's Switch.busy does.
    property bool busy: false

    signal toggled
    signal held
    signal opened

    implicitWidth: Silica.Theme.itemSizeExtraLarge
    implicitHeight: Silica.Theme.paddingMedium + Silica.Theme.iconSizeSmall + Silica.Theme.paddingSmall + textColumn.implicitHeight + Silica.Theme.paddingSmall

    Accessible.role: Accessible.Button
    Accessible.name: status !== "" ? label + ", " + status : label
    Accessible.checkable: checkable
    Accessible.checked: checkable && on
    Accessible.onPressAction: toggled()
    // Tab reaches each tile on a hardware keyboard; Return or Space toggles it.
    activeFocusOnTab: true
    Keys.onReturnPressed: toggled()
    Keys.onEnterPressed: toggled()
    Keys.onSpacePressed: toggled()

    Silica.GlassSurface {
        id: card

        objectName: "ring"
        anchors.fill: parent
        radius: Silica.Theme.paddingMedium
        scale: tileMouse.pressed || nameMouse.pressed ? 0.97 : 1.0
        lit: tile.checkable && tile.on
        pressed: tileMouse.pressed || nameMouse.pressed || (tile.busy && busyPulse.bright)

        Behavior on scale {
            enabled: !MMotion.reduceMotion
            NumberAnimation {
                duration: MMotion.quick
                easing.type: Easing.OutQuad
            }
        }
    }

    // A keyboard-focused tile wears a ring.
    Rectangle {
        anchors.fill: card
        visible: tile.activeFocus
        radius: card.radius
        color: "transparent"
        border.width: Math.max(2, Math.round(Silica.Theme.paddingSmall / 2))
        border.color: Silica.Theme.highlightColor
    }

    Silica.GlassItem {
        objectName: "stateMark"
        visible: tile.checkable && tile.on
        width: Silica.Theme.itemSizeExtraSmall * 0.45
        height: width
        anchors.right: card.right
        anchors.top: card.top
        anchors.rightMargin: Silica.Theme.paddingSmall / 2
        anchors.topMargin: Silica.Theme.paddingSmall / 2
        color: Silica.Theme.lightPrimaryColor
        backgroundColor: Silica.Theme.backgroundGlowColor
    }

    GlyphIcon {
        id: icon

        x: Silica.Theme.paddingMedium
        y: tile.wide ? (tile.height - height) / 2 : Silica.Theme.paddingMedium
        name: tile.iconName
        size: tile.wide ? Math.round(Silica.Theme.iconSizeMedium * 0.75) : Silica.Theme.iconSizeSmall
        color: Silica.Theme.primaryColor
    }

    Column {
        id: textColumn

        anchors.left: tile.wide ? icon.right : parent.left
        anchors.leftMargin: Silica.Theme.paddingMedium
        anchors.right: parent.right
        anchors.rightMargin: Silica.Theme.paddingMedium
        anchors.bottom: tile.wide ? undefined : parent.bottom
        anchors.bottomMargin: Silica.Theme.paddingSmall
        anchors.verticalCenter: tile.wide ? parent.verticalCenter : undefined

        Text {
            width: parent.width
            text: tile.label
            color: tile.on || !tile.checkable ? Silica.Theme.primaryColor : Silica.Theme.secondaryColor
            font.family: Silica.Theme.fontFamily
            font.pixelSize: tile.wide ? Silica.Theme.fontSizeExtraSmall : Silica.Theme.fontSizeTiny
            elide: Text.ElideRight
        }
        Text {
            objectName: "status"
            width: parent.width
            visible: text !== ""
            text: tile.status
            color: Silica.Theme.secondaryColor
            font.family: Silica.Theme.fontFamily
            font.pixelSize: Silica.Theme.fontSizeTiny
            elide: Text.ElideRight
        }
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

    // A wide tile's name opens its settings.
    MouseArea {
        id: nameMouse

        objectName: "nameArea"
        enabled: tile.wide
        visible: tile.wide
        anchors.fill: textColumn
        anchors.margins: -Silica.Theme.paddingSmall
        onClicked: tile.opened()
        onPressAndHold: tile.held()
    }
}
