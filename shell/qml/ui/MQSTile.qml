import QtQuick
import MarathonOS.Shell
import Sailfish.Silica 1.0 as Silica

// Quick Settings switch, as BB10's: a disc with the glyph at the left, lit
// when on; what it is and how it stands at the right ("SKYZMTGV" over
// "Wi-Fi · good"). A tap switches it; holding it opens its settings page.
Item {
    id: tile

    property string iconName: "square"
    property string label: ""
    property string status: ""
    property bool on: false
    // One-shot actions (Screenshot, Camera) are buttons, not switches.
    property bool checkable: true
    // Its settings page, if it has one: holding the tile opens it.
    property bool hasPage: false
    // The backend is switching: pulse the disc as Silica's Switch.busy does.
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

    MPressHighlight {
        anchors.fill: parent
        down: tileMouse.pressed
    }

    // A keyboard-focused tile wears a ring.
    Rectangle {
        anchors.fill: parent
        visible: tile.activeFocus
        radius: Silica.Theme.paddingMedium
        color: "transparent"
        border.width: Math.max(2, Math.round(Silica.Theme.paddingSmall / 2))
        border.color: Silica.Theme.highlightColor
    }

    Rectangle {
        id: disc

        readonly property bool lit: tile.checkable && tile.on
        readonly property bool pressed: tile.busy && busyPulse.bright

        objectName: "ring"
        x: Silica.Theme.paddingMedium
        anchors.verticalCenter: parent.verticalCenter
        width: Silica.Theme.itemSizeExtraSmall * 0.75
        height: width
        radius: width / 2
        color: lit ? MColors.accentFill : MColors.controlFill
        opacity: pressed ? 0.6 : 1
        border.width: MColors.eink && !lit ? 1 : 0
        border.color: MColors.border

        GlyphIcon {
            anchors.centerIn: parent
            name: tile.iconName
            size: Silica.Theme.iconSizeSmall
            // Ink on an off tile's paper on e-paper.
            color: MColors.eink && !parent.lit ? Silica.Theme.primaryColor : "white"
        }
    }

    Column {
        id: textColumn

        anchors.left: disc.right
        anchors.leftMargin: Silica.Theme.paddingLarge
        anchors.right: parent.right
        anchors.rightMargin: Silica.Theme.paddingSmall
        anchors.verticalCenter: parent.verticalCenter

        Text {
            width: parent.width
            text: tile.label
            color: Silica.Theme.primaryColor
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
        // Held: its settings page, or what `held` does where it has none.
        onPressAndHold: tile.hasPage ? tile.opened() : tile.held()
    }
}
