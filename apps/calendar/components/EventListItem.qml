import QtQuick
import QtQuick.Layouts
import MarathonUI.Theme
import MarathonUI.Core
import MarathonOS.Shell

Rectangle {
    id: root
    width: parent.width
    height: 72
    color: "transparent"

    property string title: ""
    property string time: ""
    property string date: ""
    property bool allDay: false

    signal clicked

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: MSpacing.md
        anchors.rightMargin: MSpacing.md
        anchors.topMargin: MSpacing.xs
        anchors.bottomMargin: MSpacing.xs

        color: MColors.surface
        radius: Constants.borderRadiusSmall
        border.color: MColors.border
        border.width: 1

        // Color strip
        Rectangle {
            width: 4
            height: parent.height - 16
            color: MColors.accent
            radius: 2
            anchors.left: parent.left
            anchors.leftMargin: MSpacing.sm
            anchors.verticalCenter: parent.verticalCenter
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: MSpacing.xl // Make room for strip
            anchors.rightMargin: MSpacing.md
            anchors.topMargin: MSpacing.sm
            anchors.bottomMargin: MSpacing.sm
            spacing: 2

            Text {
                text: root.title
                color: MColors.text
                font.pixelSize: MTypography.sizeBody
                font.weight: Font.DemiBold
                font.family: MTypography.fontFamily
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Text {
                text: root.allDay ? "All Day" : root.time
                color: MColors.textSecondary
                font.pixelSize: MTypography.sizeSmall
                font.family: MTypography.fontFamily
                Layout.fillWidth: true
            }
        }

        Icon {
            name: "chevron-right"
            size: 20
            color: MColors.textTertiary
            anchors.right: parent.right
            anchors.rightMargin: MSpacing.md
            anchors.verticalCenter: parent.verticalCenter
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.clicked()
            onPressed: parent.color = MColors.elevated
            onReleased: parent.color = MColors.surface
            onCanceled: parent.color = MColors.surface
        }
    }
}
