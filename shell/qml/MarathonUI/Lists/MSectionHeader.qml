import QtQuick
import "../Theme"

Rectangle {
    id: root
    
    property string title: ""
    property string subtitle: ""
    
    implicitWidth: parent.width
    implicitHeight: subtitle ? 60 : 44
    color: "transparent"
    
    Column {
        anchors.fill: parent
        anchors.leftMargin: MSpacing.lg
        anchors.rightMargin: MSpacing.lg
        anchors.topMargin: MSpacing.md
        anchors.bottomMargin: MSpacing.sm
        spacing: MSpacing.xs
        
        Text {
            text: root.title
            color: MColors.text
            font.pixelSize: MTypography.sizeSmall
            font.weight: MTypography.weightDemiBold
            font.family: MTypography.fontFamily
            textFormat: Text.PlainText
        }
        
        Text {
            visible: subtitle !== ""
            text: subtitle
            color: MColors.textSecondary
            font.pixelSize: MTypography.sizeXSmall
            font.family: MTypography.fontFamily
            wrapMode: Text.WordWrap
            width: parent.width
        }
    }
}

