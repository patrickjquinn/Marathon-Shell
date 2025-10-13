import QtQuick
import "../Theme"

Column {
    id: root
    
    property string title: ""
    property string subtitle: ""
    default property alias content: contentContainer.data
    
    spacing: 0
    
    Rectangle {
        visible: title !== ""
        width: parent.width
        height: subtitle ? 64 : 48
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
    
    Rectangle {
        width: parent.width
        implicitHeight: contentContainer.childrenRect.height
        color: MColors.glass
        radius: MRadius.md
        border.width: 1
        border.color: MColors.glassBorder
        
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(255, 255, 255, 0.03)
        }
        
        Column {
            id: contentContainer
            width: parent.width
        }
    }
}

