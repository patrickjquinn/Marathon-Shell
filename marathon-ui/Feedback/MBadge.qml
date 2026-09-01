import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme

// Marathon DS · Count badge (ds-components.jsx:DSBadges · "Counts").
//
// Teal-bright fill, black text. Optional 4 px squircle radius for
// rect badges (used on app grid), or pill radius for inline counts.
// Bare 8 px teal dot for "unread, no count" — use the `dot` mode.
//
// All sizes below are design-px. The count text is a scaled type token,
// so the pill has to scale with it: at 1.5x an 11 px eyebrow renders a
// ~20 px line-box, which a fixed 18 px badge clipped.
Rectangle {
    id: root

    property string text: ""
    property color badgeColor: MColors.marathonTealBright
    property color textColor: "#000000"
    property int count: 0
    property bool dot: false          // true → 8 px teal dot, no text

    readonly property real scaleFactor: Constants.scaleFactor || 1.0
    readonly property real dotSize: Math.round(8 * scaleFactor)

    // Height tracks the text it has to hold; the DS 18 is the floor.
    // Width falls back to height so single digits stay circular.
    implicitHeight: dot ? dotSize
                        : Math.max(Math.round(18 * scaleFactor),
                                   contentText.implicitHeight + Math.round(4 * scaleFactor))
    implicitWidth: dot ? dotSize
                       : Math.max(root.implicitHeight,
                                  contentText.implicitWidth + Math.round(14 * root.scaleFactor))

    radius: dot ? width / 2 : height / 2
    color: badgeColor
    visible: dot || count > 0 || text !== ""

    scale: visible ? 1.0 : 0.8

    Behavior on scale {
        SpringAnimation {
            spring: MMotion.springLight
            damping: MMotion.dampingLight
            epsilon: MMotion.epsilon
        }
    }

    // Optional teal-glow halo for the dot variant.
    Rectangle {
        visible: root.dot
        anchors.centerIn: parent
        width: Math.round(16 * root.scaleFactor)
        height: width
        radius: width / 2
        color: MColors.marathonTealGlow
        opacity: 0.18
        z: -1
    }

    Text {
        id: contentText
        visible: !root.dot
        anchors.centerIn: parent
        text: root.text !== "" ? root.text : (root.count > 99 ? "99+" : root.count.toString())
        color: root.textColor
        font.pixelSize: MTypography.sizeEyebrow
        font.weight: Font.Bold
        font.family: MTypography.fontFamily
        font.features: ({
                "tnum": 1
            })
    }
}
