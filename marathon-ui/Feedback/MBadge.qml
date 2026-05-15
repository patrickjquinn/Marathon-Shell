import QtQuick
import MarathonUI.Theme

// Marathon DS · Count badge (ds-components.jsx:DSBadges · "Counts").
//
// Teal-bright fill, black text. Optional 4 px squircle radius for
// rect badges (used on app grid), or pill radius for inline counts.
// Bare 8 px teal dot for "unread, no count" — use the `dot` mode.
Rectangle {
    id: root

    property string text: ""
    property color badgeColor: MColors.marathonTealBright
    property color textColor: "#000000"
    property int count: 0
    property bool dot: false          // true → 8 px teal dot, no text

    implicitWidth: dot ? 8 : Math.max(18, contentText.width + 14)
    implicitHeight: dot ? 8 : 18

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
        width: 16
        height: 16
        radius: 8
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
