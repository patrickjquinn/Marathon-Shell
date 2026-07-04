import MarathonUI.Core
import MarathonUI.Effects
import MarathonUI.Theme
import QtQuick

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
    radius: MRadius.md
    color: on ? MColors.marathonTealBright : MColors.elev2
    border.width: 1
    // Off-state border lifted to whiteOverlay16 so each tile reads as a
    // raised key against the elev0 panel rather than a faint outline.
    border.color: on ? MColors.tealBorder : MColors.whiteOverlay16

    // Active-tile teal glow — a blur-free halo that bleeds ~8px past the
    // tile so an on-toggle reads as lit against the dark panel. Peak teal
    // sits at the tile edge and fades to nothing outward; strongest along
    // the sides (vertical ramp). No MultiEffect — a real Gaussian glow
    // would tank the grid on etnaviv. Declared first so it sits behind.
    Rectangle {
        visible: tile.on
        anchors.fill: parent
        anchors.margins: -8
        radius: parent.radius + 8
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.14; color: Qt.rgba(0, 191 / 255, 165 / 255, 0.32) }
            GradientStop { position: 0.86; color: Qt.rgba(0, 191 / 255, 165 / 255, 0.32) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // On-state lit dome — the teal fill ramps bright at the top to a deeper
    // teal at the base, so an active tile reads as a lit key with a face and
    // a shadowed base rather than a flat swatch. This (not the outer halo)
    // is what gives the on-state real presence. Icon/label paint on top.
    Rectangle {
        visible: tile.on
        anchors.fill: parent
        radius: parent.radius
        gradient: Gradient {
            GradientStop { position: 0.0; color: MColors.marathonTealBright }
            GradientStop { position: 1.0; color: MColors.marathonTeal }
        }
    }

    // Off-state top sheen — a faint white ramp fading out by mid-height.
    // With the inner hairline below it, the tile catches light along its
    // top edge (glass lit from above) instead of sitting dead-flat.
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        visible: !tile.on
        gradient: Gradient {
            GradientStop { position: 0.0; color: MColors.whiteOverlay08 }
            GradientStop { position: 0.5; color: "transparent" }
        }
    }

    // Sub-pixel inner top hairline — gives the tile physical presence on
    // glass. Tealified when on, plain whiteOverlay when off.
    MTopHairline {
        radius: parent.radius
        color: on ? Qt.rgba(0, 0, 0, 0.22) : MColors.whiteOverlay08
        lineWidth: 1
        z: 1
    }

    // 1x1 (compact) — icon top-centered, label below
    Column {
        anchors.centerIn: parent
        spacing: MSpacing.sm
        visible: !tile.isWide

        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: tile.iconName
            size: 24
            color: tile.on ? "#000000" : MColors.textPrimary
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: tile.label
            color: tile.on ? "#000000" : MColors.textPrimary
            font.family: MTypography.fontFamily
            font.pixelSize: MTypography.sizeFootnote
            font.weight: MTypography.weightMedium
            horizontalAlignment: Text.AlignHCenter
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
            color: tile.on ? "#000000" : MColors.textPrimary
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 24 - MSpacing.md
            spacing: 2

            Text {
                text: tile.label
                color: tile.on ? "#000000" : MColors.textPrimary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeFootnote
                font.weight: MTypography.weightDemiBold
                width: parent.width
                elide: Text.ElideRight
            }
            Text {
                text: tile.sublabel
                visible: text.length > 0
                color: tile.on ? Qt.rgba(0, 0, 0, 0.72) : MColors.textSecondary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeCaption
                font.weight: MTypography.weightMedium
                width: parent.width
                elide: Text.ElideRight
            }
        }
    }

    Behavior on color {
        ColorAnimation {
            duration: MMotion.quick
            easing.type: Easing.OutCubic
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: tile.toggled()
        onPressed: tile.scale = 0.96
        onReleased: tile.scale = 1.0
    }
    Behavior on scale {
        NumberAnimation {
            duration: MMotion.quick
            easing.type: Easing.OutBack
        }
    }
}
