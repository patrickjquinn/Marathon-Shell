import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme

Rectangle {
    id: root
    
    property string title: ""
    property string subtitle: ""
    
    implicitWidth: parent.width
    implicitHeight: subtitle ? 60 : 44
    color: "transparent"
    
    Column {
        anchors.fill: parent
        anchors.leftMargin: Constants.spacingLarge
        anchors.rightMargin: Constants.spacingLarge
        anchors.topMargin: Constants.spacingMedium
        anchors.bottomMargin: Constants.spacingSmall
        spacing: Constants.spacingXSmall
        
        Text {
            text: root.title
            color: MColors.text
            font.pixelSize: Constants.fontSizeSmall
            font.weight: Font.DemiBold
            font.family: MTypography.fontFamily
            textFormat: Text.PlainText
        }
        
        Text {
            visible: subtitle !== ""
            text: subtitle
            color: MColors.textSecondary
            font.pixelSize: Constants.fontSizeXSmall
            font.family: MTypography.fontFamily
            wrapMode: Text.WordWrap
            width: parent.width
        }
    }
}

