import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

// Marathon DS · Now Bar — 36 px live-activity strip.
//
// Variants (set `variant`):
//   • "music"  — icon badge + title + artist/duration + 5-bar visualiser
//   • "call"   — icon badge + caller + "CALL · 02:14" + pulse ring on badge
//   • "nav"    — icon badge + destination + distance/eta
//   • "timer"  — icon badge + label + remaining time
//
// Always renders glass over its parent. Anchored top: 28 (just under
// status bar) by callers. Floats above content with blur(20) — heavier
// than Active Frames (blur 16) so it reads as on-top.
//
// One Now Bar per screen. The system aggregates music / call / nav /
// timer feeds and picks the highest-priority one to surface.
Item {
    id: root

    // Layout token — DS spec.
    implicitHeight: 36

    // Variant + content.
    property string variant: "music"          // "music" | "call" | "nav" | "timer"
    property string iconName: "music"         // glyph in the badge
    property string label: ""                 // bold line — "Modular Tides"
    property string sublabel: ""              // dim line — "Avior · 1:48"
    property color tintColor: MColors.marathonTealBright

    // Music-only — animated equaliser bars.
    property bool playing: variant === "music"

    // Call-only — pulse ring around badge.
    property bool pulsing: variant === "call"

    signal activated  // user tapped the bar

    // Glass background.
    Rectangle {
        anchors.fill: parent
        color: MColors.glassTitlebar
        radius: MRadius.md
        border.width: 1
        border.color: MColors.borderGlass
    }

    // Subtle outer shadow + inner highlight (per DS §02).
    // Skipping MultiEffect drop shadow per the perf rule —
    // the inner highlight + glass tint composes the depth.
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: MRadius.md - 1
        color: "transparent"
        border.width: 1
        border.color: MColors.whiteOverlay04
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: variant === "call" ? 14 : 6
        anchors.rightMargin: 12
        spacing: 10

        // Icon badge.
        Item {
            id: badgeWrap
            width: variant === "call" ? 26 : 26
            height: width
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: MColors.bb10Elevated
                border.width: 1
                border.color: MColors.whiteOverlay08

                Icon {
                    anchors.centerIn: parent
                    name: root.iconName
                    size: 13
                    color: root.tintColor
                }
            }

            // Pulse ring — call variant. Animates radius/opacity to
            // signal "active call." Gated on visible per CODING_RULES
            // C8 so no idle cost when not in call.
            Rectangle {
                anchors.fill: parent
                anchors.margins: -2
                radius: (parent.width + 4) / 2
                color: "transparent"
                border.width: 1
                border.color: MColors.tealBorder
                opacity: 0.5
                visible: root.pulsing

                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    running: root.pulsing && root.visible
                    NumberAnimation {
                        from: 0.5
                        to: 0.0
                        duration: 1200
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        from: 0.0
                        to: 0.5
                        duration: 0
                    }
                }
            }
        }

        // Label / sublabel — flex-1, ellipses.
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - badgeWrap.width - visualWrap.width - parent.spacing * 2
            spacing: 2

            Text {
                width: parent.width
                text: root.label
                color: MColors.textPrimary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeEyebrow   // DS NowBar 11/600
                font.weight: MTypography.weightDemiBold
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: root.sublabel
                color: MColors.textSecondary
                font.family: MTypography.fontFamily
                // 9 px is intentionally below the type ramp — DS NowBar spec
                // ("11/600 title, 9/400 subtitle"). Live-activity sublabel
                // never appears anywhere else; promoting to a token would
                // imply reuse that doesn't exist.
                font.pixelSize: 9
                font.weight: MTypography.weightRegular
                elide: Text.ElideRight
                visible: text.length > 0
            }
        }

        // Right-side variant content. Music = visualiser, others = empty.
        Item {
            id: visualWrap
            anchors.verticalCenter: parent.verticalCenter
            width: root.variant === "music" ? visualiser.implicitWidth : 0
            height: 12

            Row {
                id: visualiser
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                visible: root.variant === "music"

                // Five teal bars, heights [6, 10, 4, 8, 5] per DS §02.
                Repeater {
                    model: [6, 10, 4, 8, 5]
                    delegate: Rectangle {
                        required property int index
                        required property int modelData
                        width: 2
                        height: modelData
                        radius: 1
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.tintColor
                        opacity: index % 2 ? 1.0 : 0.5

                        // Subtle height bob when playing. Animation only
                        // runs while the bar is actually visible.
                        SequentialAnimation on height {
                            loops: Animation.Infinite
                            running: root.playing && root.visible
                            NumberAnimation {
                                from: modelData
                                to: 2
                                duration: 280 + index * 70
                                easing.type: Easing.InOutQuad
                            }
                            NumberAnimation {
                                from: 2
                                to: modelData
                                duration: 280 + index * 70
                                easing.type: Easing.InOutQuad
                            }
                        }
                    }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.activated()
        onPressed: scaleAnim.start()
    }
    SequentialAnimation {
        id: scaleAnim
        NumberAnimation {
            target: root
            property: "scale"
            to: 0.98
            duration: MMotion.micro
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "scale"
            to: 1.0
            duration: MMotion.quick
            easing.type: Easing.OutBack
        }
    }
}
