import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

// Marathon DS · Quick Settings tile — BB10 split-bay pattern.
//
// Two-bay layout: 60 px left bay (icon) + flex right bay (label + sub).
//   • On  → left bay fills tealBright, icon black, right bay primary
//   • Off → left bay transparent (elev-2 bg), icon tertiary, sub dim
// Border + halo also switch on `on`. The split-bay is the signature
// BB10 affordance — left side reads as the "active" indicator.
//
// 64 px tall (touch-small-ish), 4 px radius. Used by MarathonQuickSettings.
Rectangle {
    id: tile

    property string iconName: "square"
    property string label: ""
    property string sublabel: ""
    property bool on: false

    signal toggled

    // Card base.
    implicitHeight: 64
    radius: MRadius.md
    color: MColors.bb10Elevated
    border.width: 1
    border.color: on ? MColors.tealBorder : MColors.whiteOverlay04
    clip: true

    // Inner inset highlight — uniform whether on or off.
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: parent.radius - 1
        color: "transparent"
        border.width: 1
        border.color: MColors.whiteOverlay04
        z: 1
    }

    Row {
        anchors.fill: parent
        spacing: 0

        // ── Left bay — solid teal when on ────────────────────
        Rectangle {
            id: leftBay
            width: 60
            height: parent.height
            color: tile.on ? MColors.marathonTealBright : "transparent"
            border.width: 0

            // Right edge of the bay is a 1 px separator.
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: tile.on ? MColors.tealBorder : MColors.whiteOverlay04
            }

            Icon {
                anchors.centerIn: parent
                name: tile.iconName
                size: 22
                color: tile.on ? "#000000" : MColors.textTertiary
            }
        }

        // ── Right bay — label + sub ──────────────────────────
        Item {
            width: parent.width - leftBay.width
            height: parent.height

            Column {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 2

                Text {
                    text: tile.label
                    color: tile.on ? MColors.textPrimary : MColors.textSecondary
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeFootnote
                    font.weight: tile.on ? MTypography.weightDemiBold : MTypography.weightMedium
                    elide: Text.ElideRight
                    width: parent.width
                }
                Text {
                    text: tile.sublabel
                    color: tile.on ? MColors.marathonTealBright : MColors.textTertiary
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeEyebrow
                    font.weight: MTypography.weightMedium
                    elide: Text.ElideRight
                    width: parent.width
                    visible: text.length > 0
                }
            }
        }
    }

    // Per CODING_RULES C8: no infinite animations. The glow on-state
    // border is a static colour, not an animated effect.
    Behavior on color {
        ColorAnimation {
            duration: MMotion.quick
            easing.type: Easing.OutCubic
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: tile.toggled()
        onPressed: tile.scale = 0.97
        onReleased: tile.scale = 1.0
    }
    Behavior on scale {
        NumberAnimation {
            duration: MMotion.quick
            easing.type: Easing.OutBack
        }
    }
}
