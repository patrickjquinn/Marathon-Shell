import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme

Column {
    id: root
    
    property string title: ""
    property string subtitle: ""
    default property alias content: contentContainer.data
    
    spacing: 0
    
    Rectangle {
        visible: title !== ""
        width: parent.width
        height: subtitle ? Constants.touchTargetLarge : Constants.touchTargetMedium
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
                font.pixelSize: Constants.fontSizeLarge
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
    
    Rectangle {
        width: parent.width
        implicitHeight: contentContainer.childrenRect.height
        color: MColors.surface
        radius: Constants.borderRadiusSharp
        border.width: Constants.borderWidthMedium
        border.color: MColors.border
        antialiasing: Constants.enableAntialiasing
        
        Rectangle {
            anchors.fill: parent
            anchors.margins: Constants.borderWidthThin
            radius: parent.radius - Constants.borderWidthThin
            color: "transparent"
            border.width: Constants.borderWidthThin
            border.color: MColors.borderInner
            antialiasing: Constants.enableAntialiasing
        }
        
        Column {
            id: contentContainer
            width: parent.width
        }
    }
}

