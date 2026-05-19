import MarathonUI.Core
import MarathonUI.Effects
import MarathonUI.Theme
import QtQuick

// Marathon DS · Active Frame — BB10-inspired live tile.
//
// Fixed-height (158 px) glass-blurred container. Either mode is
// the same component; the mode prop swaps which slot is shown
// and where the title chrome sits.
//
//   mode = "home"     — curated widget. Header at TOP (icon · app
//                       name · count). Body shows the app's
//                       "next thing" — calendar's next event,
//                       music's now-playing, health's today rings,
//                       messages' unread.
//
//   mode = "switcher" — live snapshot. Title bar at BOTTOM (icon ·
//                       app name · state · close X). Body shows
//                       the app's last view.
//
// Apps register both via two slots: `widget` and `preview`. The
// parent MFramesView decides which to render based on its own mode.
//
// The 158 px height is hard — content truncates rather than grows.
// Per DS §04, no MultiEffect drop shadows; depth comes from the
// glass tint + inner highlight + outer border. Composition over
// the wallpaper does the heavy lifting visually.
Item {
    id: root

    implicitHeight: 158

    // Slots — caller provides one or both.
    default property alias widgetSlot: widgetHolder.data
    property Component preview: null

    // Mode + chrome content.
    property string mode: "home"             // "home" | "switcher"
    property string iconName: ""             // header / titlebar glyph
    property string appName: ""              // bold line
    property string badge: ""                // top-right: "3 today" / "Playing" / "3 unread"
    property color iconTint: MColors.marathonTealBright

    signal activated
    signal closed                            // switcher mode only — X button

    // ── Background ───────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(22 / 255, 23 / 255, 24 / 255, 0.78)
        radius: MRadius.md
        border.width: 1
        border.color: MColors.whiteOverlay08
    }

    // Inner highlight — top arc only, follows the squircle path
    // (matches MCard, MButton, MAppIcon home tiles).
    MTopHairline {
        radius: MRadius.md
        color: MColors.whiteOverlay06
    }

    // ── Header (home mode — top) ─────────────────────────────
    Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        height: 18
        visible: root.mode === "home"

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Icon {
                name: root.iconName
                color: root.iconTint
                size: 14
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: root.appName
                color: MColors.textPrimary
                font.family: MTypography.fontFamily
                font.pixelSize: 12
                font.weight: MTypography.weightDemiBold
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.badge
            color: MColors.textSecondary
            font.family: MTypography.fontFamily
            font.pixelSize: 10
            font.weight: MTypography.weightRegular
        }
    }

    // ── Title bar (switcher mode — bottom) ───────────────────
    Item {
        id: titleBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 36
        visible: root.mode === "switcher"

        // Glass-tabbar tint over the body — chrome on the snapshot.
        Rectangle {
            anchors.fill: parent
            color: MColors.glassTabbar
            radius: MRadius.md
            // Only the bottom corners are rounded — top is sharp
            // against the body content above. Approximated by
            // clipping at the parent's radius.
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: MColors.borderGlass
        }

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 12
            spacing: 10

            Rectangle {
                width: 24
                height: 24
                radius: MRadius.md
                color: MColors.bb10Elevated
                anchors.verticalCenter: parent.verticalCenter

                Icon {
                    anchors.centerIn: parent
                    name: root.iconName
                    color: root.iconTint
                    size: 12
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                    text: root.appName
                    color: MColors.textPrimary
                    font.family: MTypography.fontFamily
                    font.pixelSize: 12
                    font.weight: MTypography.weightDemiBold
                }
                Text {
                    text: root.badge
                    color: MColors.textSecondary
                    font.family: MTypography.fontFamily
                    font.pixelSize: 10
                    font.weight: MTypography.weightRegular
                    visible: text.length > 0
                }
            }
        }

        // Close X
        Item {
            width: 22
            height: 22
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter

            Icon {
                anchors.centerIn: parent
                name: "x"
                size: 14
                color: MColors.textTertiary
            }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -8
                onClicked: root.closed()
            }
        }
    }

    // ── Body slot ────────────────────────────────────────────
    // Home mode: below the header.
    // Switcher mode: above the title bar.
    Item {
        id: widgetHolder
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.top: root.mode === "home" ? header.bottom : parent.top
        anchors.bottom: root.mode === "switcher" ? titleBar.top : parent.bottom
        anchors.topMargin: root.mode === "home" ? 8 : 0
        anchors.bottomMargin: root.mode === "switcher" ? 0 : 8
        clip: true
    }

    // Tap to activate. Press scale per DS §02 — 0.96, springy.
    MouseArea {
        anchors.fill: parent
        onClicked: root.activated()
        onPressed: root.scale = 0.97
        onReleased: root.scale = 1.0
    }
    Behavior on scale {
        NumberAnimation {
            duration: MMotion.quick
            easing.type: Easing.OutBack
        }
    }
}
