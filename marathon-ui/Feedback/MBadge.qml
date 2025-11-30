import QtQuick
import MarathonUI.Theme

Rectangle {
    id: root

    property string text: ""
    property color badgeColor: MColors.error
    property int count: 0

    implicitWidth: Math.max(MSpacing.lg, contentText.width + MSpacing.sm * 2)
    implicitHeight: MSpacing.lg

    radius: height / 2
    color: badgeColor
    visible: count > 0 || text !== ""

    scale: visible ? 1.0 : 0.8

    Behavior on scale {
        SpringAnimation {
            spring: MMotion.springLight
            damping: MMotion.dampingLight
            epsilon: MMotion.epsilon
        }
    }

    Text {
        id: contentText
        anchors.centerIn: parent
        text: root.text !== "" ? root.text : (root.count > 99 ? "99+" : root.count.toString())
        color: MColors.textOnAccent
        font.pixelSize: MTypography.sizeXSmall
        font.weight: MTypography.weightDemiBold
        font.family: MTypography.fontFamily
    }
}
