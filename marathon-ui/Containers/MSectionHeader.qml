import QtQuick
import MarathonUI.Theme
import MarathonOS.Shell

Rectangle {
    id: root

    readonly property real scaleFactor: Constants.scaleFactor || 1.0

    property alias text: headerText.text

    height: Math.round(44 * scaleFactor)
    color: MColors.glassHeader

    border.width: 1
    border.color: MColors.borderGlass

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        color: "transparent"
        border.width: 1
        border.color: MColors.highlightSubtle
    }

    Text {
        id: headerText
        anchors.left: parent.left
        anchors.leftMargin: MSpacing.xl
        anchors.verticalCenter: parent.verticalCenter
        color: MColors.marathonTeal
        font.pixelSize: MTypography.sizeXSmall
        font.weight: MTypography.weightDemiBold
        font.family: MTypography.fontFamily
        text: text.toUpperCase()
        font.letterSpacing: 1.2
    }
}
