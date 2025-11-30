import QtQuick
import MarathonUI.Theme

Rectangle {
    id: root

    property alias text: headerText.text

    height: 44
    color: MColors.glassHeader

    // No blur - clean and crisp
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
