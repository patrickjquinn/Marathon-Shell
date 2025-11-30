import QtQuick
import MarathonUI.Theme

Item {
    id: section

    property string title: ""
    property string subtitle: ""
    default property alias content: contentColumn.children

    width: parent ? parent.width : 400
    height: headerColumn.height + contentCard.height + (title !== "" ? MSpacing.md : 0)

    Column {
        id: headerColumn
        width: parent.width
        spacing: MSpacing.xs
        visible: title !== ""

        Text {
            text: title
            color: MColors.textPrimary
            font.pixelSize: MTypography.sizeLarge
            font.weight: MTypography.weightDemiBold
            font.family: MTypography.fontFamily
            width: parent.width
        }

        Text {
            visible: subtitle !== ""
            text: subtitle
            color: MColors.textSecondary
            font.pixelSize: MTypography.sizeSmall
            font.family: MTypography.fontFamily
            wrapMode: Text.WordWrap
            width: parent.width
            opacity: 0.7
        }
    }

    Rectangle {
        id: contentCard
        anchors.top: headerColumn.bottom
        anchors.topMargin: title !== "" ? MSpacing.md : 0
        width: parent.width
        height: contentColumn.height
        color: MColors.bb10Card
        radius: MRadius.lg
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.03)
        }

        Column {
            id: contentColumn
            width: parent.width
        }
    }
}
