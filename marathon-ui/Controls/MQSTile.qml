import MarathonUI.Core
import MarathonUI.Effects
import MarathonUI.Theme
import QtQuick
import MarathonOS.Shell

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
    // Off = elev2 key; On = a dark teal-tinted key. The tile no longer floods
    // solid teal (that read as a flat 2014-era swatch) — activation is carried
    // by a teal RADIAL GLOW + brightened glyph + teal border, the same
    // active-state language the top tab bar uses.
    color: on ? MColors.tealTintDark : MColors.elev2
    border.width: 1
    // Off-state border lifted to whiteOverlay16 so each tile reads as a
    // raised key against the elev0 panel rather than a faint outline. On-state
    // gets a brighter teal rim (hover-strength) so the lit key has a crisp edge.
    border.color: on ? MColors.tealBorderHover : MColors.whiteOverlay16
    Behavior on border.color {
        ColorAnimation { duration: MMotion.quick }
    }

    // Radial "dome" glow — the SAME treatment for BOTH states so on and off
    // tiles read as one component family. On → a bright teal glow that lights
    // the key up; off → a faint neutral dome that gives the resting key the
    // identical glass depth, just unlit. Static Canvas paint (same technique
    // as the tab bar's active-tab glow), repainted whenever `on` flips.
    // Behind icon + label.
    Canvas {
        id: domeGlow
        anchors.fill: parent
        onPaint: {
            const ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            const cx = width / 2;
            const cy = height / 2;
            const rad = Math.max(width, height) * 0.72;
            const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, rad);
            if (tile.on) {
                g.addColorStop(0.0, "rgba(29, 233, 182, 0.62)");
                g.addColorStop(0.45, "rgba(29, 233, 182, 0.28)");
                g.addColorStop(1.0, "rgba(29, 233, 182, 0.0)");
            } else {
                // Neutral resting dome — same shape, unlit. A whisper of white
                // so the key catches light from its centre like the lit ones.
                g.addColorStop(0.0, "rgba(255, 255, 255, 0.055)");
                g.addColorStop(0.5, "rgba(255, 255, 255, 0.018)");
                g.addColorStop(1.0, "rgba(255, 255, 255, 0.0)");
            }
            ctx.fillStyle = g;
            ctx.fillRect(0, 0, width, height);
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Component.onCompleted: requestPaint()
        Connections {
            target: tile
            function onOnChanged() { domeGlow.requestPaint(); }
        }
    }

    // Sub-pixel inner top hairline — gives the tile physical presence on
    // glass. Tealified when on, plain whiteOverlay when off.
    MTopHairline {
        radius: parent.radius
        // On → a teal-lit top edge over the dark active key; off → plain white.
        color: tile.on ? MColors.marathonTealBorderHover : MColors.whiteOverlay08
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
            // On → teal-bright glyph over the halo (lit); off → dim secondary.
            color: tile.on ? MColors.marathonTealBright : MColors.textSecondary
            Behavior on color { ColorAnimation { duration: MMotion.quick } }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: tile.label
            color: tile.on ? MColors.textPrimary : MColors.textSecondary
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
