import QtQuick
import MarathonUI.Theme
import MarathonUI.Core
import MarathonOS.Shell

Item {
    id: root

    property string iconName: "inbox"
    property string title: "Nothing here yet"
    property string message: ""
    property string actionText: ""
    property int iconSize: 80

    signal actionClicked

    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.8, 400)
        spacing: MSpacing.lg

        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: iconName
            size: iconSize
            color: MColors.textTertiary
            opacity: 0.6
        }

        Column {
            width: parent.width
            spacing: MSpacing.sm

            MLabel {
                width: parent.width
                text: title
                variant: "primary"
                font.pixelSize: MTypography.sizeLarge
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
            }

            MLabel {
                width: parent.width
                text: message
                variant: "secondary"
                font.pixelSize: MTypography.sizeBody
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                visible: message.length > 0
            }
        }

        MButton {
            anchors.horizontalCenter: parent.horizontalCenter
            text: actionText
            variant: "primary"
            visible: actionText.length > 0
            onClicked: root.actionClicked()
        }
    }
}
