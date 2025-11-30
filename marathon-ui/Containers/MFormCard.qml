import QtQuick
import MarathonUI.Theme
import MarathonUI.Core
import MarathonUI.Controls

Rectangle {
    id: root

    property string title: ""
    property string description: ""
    property alias content: formContent.data
    property alias actions: formActions.data

    implicitWidth: parent ? parent.width : 400
    implicitHeight: formColumn.height + (MSpacing.xl * 2)

    color: MColors.bb10Card
    radius: MRadius.lg
    border.width: 1
    border.color: MColors.borderGlass

    Accessible.role: Accessible.Form
    Accessible.name: title
    Accessible.description: description

    // Performant shadow
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 2
        anchors.leftMargin: -2
        anchors.rightMargin: -2
        anchors.bottomMargin: -4
        z: -1
        radius: parent.radius
        color: Qt.rgba(0, 0, 0, 0.3)
        opacity: 0.4
    }

    layer.enabled: false

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: parent.radius - 1
        color: "transparent"
        border.width: 1
        border.color: MColors.highlightSubtle
    }

    Column {
        id: formColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: MSpacing.xl
        spacing: MSpacing.lg
        clip: true

        Column {
            width: parent.width
            spacing: MSpacing.xs
            visible: root.title !== "" || root.description !== ""

            Text {
                text: root.title
                color: MColors.textPrimary
                font.pixelSize: MTypography.sizeLarge
                font.weight: MTypography.weightDemiBold
                font.family: MTypography.fontFamily
                visible: root.title !== ""
                width: parent.width
            }

            Text {
                text: root.description
                color: MColors.textSecondary
                font.pixelSize: MTypography.sizeSmall
                font.weight: MTypography.weightNormal
                font.family: MTypography.fontFamily
                visible: root.description !== ""
                width: parent.width
                wrapMode: Text.WordWrap
            }
        }

        Column {
            id: formContent
            width: parent.width
            spacing: MSpacing.md
            clip: true
        }

        Row {
            id: formActions
            width: parent.width
            spacing: MSpacing.md
            layoutDirection: Qt.RightToLeft
        }
    }
}
