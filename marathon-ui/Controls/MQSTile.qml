import MarathonUI.Core
import MarathonUI.Effects
import MarathonUI.Theme
import QtQuick
import MarathonOS.Shell
import Sailfish.Silica 1.0 as Silica

// Marathon DS · Quick Settings tile — 4-col compact (BB10-modern hybrid).
//
// Square-ish, icon top-centered, label below. No sublabel in compact mode
// (4-col widths can't comfortably hold an SSID without elision dust).
// Active state is signaled by full teal fill + black icon/label + inner
// teal halo hairline; off-state stays elev-2 with a visible whiteOverlay
// border so the grid reads as a uniform field of pressables.
//
// Tokens (Marathon DS):
//   container radius MRadius.md (4 px) — BB10 industrial corner
//   inner pad   MSpacing.md (16 px) all sides
//   icon size   MSpacing.lg + 4 = 24 px
//   icon→label  MSpacing.sm (10 px)
//   label       MTypography.sizeFootnote (13 px) Medium
//   height      84 px — fits icon + gap + label without clip
Rectangle {
    id: tile

    property string iconName: "square"
    property string label: ""
    property string sublabel: ""        // shown only in wide variant
    property bool on: false

    // ── M3 Expressive cell-span variant ────────────────────────
    // Single-cell ("1x1") = compact icon-over-label square (default).
    // Wide ("2x1") = horizontal layout: icon LEFT, label + optional
    // sublabel stacked RIGHT. Spans 2 grid columns when the parent
    // grid honours `Layout.columnSpan: 2` (caller sets this in the
    // Grid Repeater). The variant property is consumed by the layout
    // and by the internal arrangement decision below.
    property string variant: "1x1"      // "1x1" | "2x1"
    readonly property bool isWide: variant === "2x1"

    signal toggled

    implicitHeight: 84
    scale: tileMouse.pressed ? 0.96 : 1.0

    Accessible.role: Accessible.Button
    Accessible.name: sublabel.length > 0 ? label + ", " + sublabel : label
    Accessible.checkable: true
    Accessible.checked: on
    Accessible.onPressAction: toggled()
    radius: MRadius.md
    // Sailfish Top Menu switch: no key face, a round icon lit with the
    // ambience highlight when on.
    color: "transparent"
    // 1x1 (compact) — icon top-centered, label below
    Column {
        anchors.centerIn: parent
        spacing: MSpacing.xs
        visible: !tile.isWide

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.round(34 * (Constants.scaleFactor || 1.0))
            height: width
            radius: width / 2
            color: tile.on ? Silica.Theme.rgba(Silica.Theme.highlightBackgroundColor, Silica.Theme.highlightBackgroundOpacity)
                           : Silica.Theme.rgba(Silica.Theme.primaryColor, 0.08)

            Icon {
                anchors.centerIn: parent
                name: tile.iconName
                size: 20
                color: tile.on ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                Behavior on color { ColorAnimation { duration: MMotion.quick } }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: tile.label
            color: tile.on ? Silica.Theme.highlightColor : Silica.Theme.secondaryColor
            font.family: MTypography.fontFamily
            font.pixelSize: MTypography.sizeFootnote
            font.weight: MTypography.weightMedium
            horizontalAlignment: Text.AlignHCenter
            // Constrain and elide, as the wide variant below already does.
            // Without a width this rendered at its natural size and overflowed
            // the tile: sizeFootnote scales but the 4-column grid does not, so
            // at userScaleFactor 1.50 "Bluetooth", "Location", "Hotspot" and
            // "Settings" spilled past their tiles into their neighbours.
            //
            // Bind to the TILE, not to parent. The parent Column is
            // intrinsically sized (anchors.centerIn, no explicit width), so
            // parent.width depends on this child — a circular binding that
            // collapses to 0 and elides the label away entirely.
            width: tile.width - Math.round(10 * (Constants.scaleFactor || 1.0))
            elide: Text.ElideRight
            Behavior on color { ColorAnimation { duration: MMotion.quick } }
        }
    }

    // 2x1 (wide) — icon left, label + sublabel stacked right.
    // Same height as 1x1 (84 px), 2× width. Use for tiles where the
    // value is information-bearing (Wi-Fi SSID, current connection,
    // playback "Now Playing") and the compact form clips with
    // elision dust.
    Row {
        anchors.fill: parent
        anchors.leftMargin: MSpacing.md
        anchors.rightMargin: MSpacing.md
        spacing: MSpacing.md
        visible: tile.isWide

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: tile.iconName
            size: 24
            color: tile.on ? MColors.marathonTealBright : MColors.textSecondary
            Behavior on color { ColorAnimation { duration: MMotion.quick } }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 24 - MSpacing.md
            spacing: 2

            Text {
                text: tile.label
                color: tile.on ? MColors.textPrimary : MColors.textSecondary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeFootnote
                font.weight: MTypography.weightDemiBold
                width: parent.width
                elide: Text.ElideRight
            }
            Text {
                text: tile.sublabel
                visible: text.length > 0
                color: tile.on ? MColors.marathonTealBright : MColors.textSecondary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeCaption
                font.weight: MTypography.weightMedium
                width: parent.width
                elide: Text.ElideRight
            }
        }
    }

    Behavior on color {
        enabled: !MMotion.reduceMotion

        ColorAnimation {
            duration: MMotion.quick
            easing.type: Easing.OutCubic
        }
    }

    MouseArea {
        id: tileMouse

        anchors.fill: parent
        onClicked: tile.toggled()
    }
    Behavior on scale {
        enabled: !MMotion.reduceMotion

        NumberAnimation {
            duration: MMotion.quick
            easing.type: Easing.OutBack
        }
    }
}
