import QtQuick
import MarathonUI.Theme
import MarathonOS.Shell

Rectangle {
    id: root

    property string title: ""
    property alias actions: actionsItem.children

    readonly property real scaleFactor: Constants.scaleFactor || 1.0
    readonly property real barHeight: Math.round(88 * scaleFactor)
    readonly property real borderWidth: Math.max(1, Math.round(1 * scaleFactor))
    readonly property real titleFontSize: Math.round(28 * scaleFactor)
    readonly property real titleLetterSpacing: -0.5 * scaleFactor

    height: barHeight
    color: MColors.glassTitlebar

    // Glass morphism without blur (blur effect would blur content UNDER the bar, not desired)
    border.width: borderWidth
    border.color: MColors.borderGlass

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: -borderWidth
        anchors.leftMargin: -borderWidth
        anchors.rightMargin: -borderWidth
        color: "transparent"
        border.width: borderWidth
        border.color: Qt.rgba(1, 1, 1, 0.06)
        z: 1
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: MSpacing.xl
        anchors.verticalCenter: parent.verticalCenter
        spacing: MSpacing.sm

        Text {
            text: root.title
            color: MColors.textPrimary
            font.pixelSize: titleFontSize
            font.weight: Font.Light
            font.family: MTypography.fontFamily
            font.letterSpacing: titleLetterSpacing
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Row {
        id: actionsItem
        anchors.right: parent.right
        anchors.rightMargin: MSpacing.xl
        anchors.verticalCenter: parent.verticalCenter
        spacing: MSpacing.md
    }
}
