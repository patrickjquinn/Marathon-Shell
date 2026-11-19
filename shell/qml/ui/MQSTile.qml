import QtQuick
import MarathonOS.Shell
import Sailfish.Silica 1.0 as Silica

// Quick Settings switch, as BB10's: the glyph at the left, what it is and how
// it stands at the right ("SKYZMTGV" over "Wi-Fi · good"). Tapping the glyph
// switches it; tapping the words opens its settings when it has a page, and
// switches it when it has none. A glass tile, lit with the ambience when on,
// with Silica's Switch glow at its end.
Item {
    id: tile

    property string iconName: "square"
    property string label: ""
    property string status: ""
    property bool on: false
    // One-shot actions (Screenshot, Camera) are buttons, not switches.
    property bool checkable: true
    // Its settings page, if it has one: the words open it.
    property bool hasPage: false
    // The backend is switching: pulse the tile as Silica's Switch.busy does.
    property bool busy: false

    signal toggled
    signal held
    signal opened

    implicitWidth: Silica.Theme.itemSizeExtraLarge * 2
    implicitHeight: Math.max(Silica.Theme.itemSizeSmall, textColumn.implicitHeight + Silica.Theme.paddingMedium * 2)

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
        scale: glyphMouse.pressed || wordsMouse.pressed ? 0.97 : 1.0
        lit: tile.checkable && tile.on
        pressed: glyphMouse.pressed || wordsMouse.pressed || (tile.busy && busyPulse.bright)

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

    GlyphIcon {
        id: icon

        x: Silica.Theme.paddingMedium
        anchors.verticalCenter: parent.verticalCenter
        name: tile.iconName
        size: Silica.Theme.iconSizeSmall
        color: Silica.Theme.primaryColor
    }

    Column {
        id: textColumn

        anchors.left: icon.right
        anchors.leftMargin: Silica.Theme.paddingMedium
        anchors.right: mark.left
        anchors.verticalCenter: parent.verticalCenter

        Text {
            width: parent.width
            text: tile.label
            color: tile.on || !tile.checkable ? Silica.Theme.primaryColor : Silica.Theme.secondaryColor
            font.family: Silica.Theme.fontFamily
            font.pixelSize: Silica.Theme.fontSizeExtraSmall
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

    Silica.GlassItem {
        id: mark

        objectName: "stateMark"
        width: tile.checkable ? Silica.Theme.itemSizeExtraSmall * 0.45 : Silica.Theme.paddingSmall
        height: width
        anchors.right: parent.right
        anchors.rightMargin: Silica.Theme.paddingSmall
        anchors.verticalCenter: parent.verticalCenter
        visible: tile.checkable && tile.on
        color: Silica.Theme.lightPrimaryColor
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

    // The glyph switches it.
    MouseArea {
        id: glyphMouse

        objectName: "glyphArea"
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: tile.hasPage ? icon.x + icon.width + Silica.Theme.paddingSmall : parent.width
        onClicked: tile.toggled()
        onPressAndHold: tile.held()
    }

    // The words open its page.
    MouseArea {
        id: wordsMouse

        objectName: "wordsArea"
        enabled: tile.hasPage
        visible: tile.hasPage
        anchors.left: glyphMouse.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        onClicked: tile.opened()
        onPressAndHold: tile.held()
    }
}
