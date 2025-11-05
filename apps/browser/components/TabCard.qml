import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Core

Rectangle {
    id: tabCard
    height: Constants.cardHeight
    radius: Constants.borderRadiusSharp
    color: isCurrentTab ? MColors.elevated : MColors.surface
    border.width: Constants.borderWidthThin
    border.color: isCurrentTab ? MColors.accentBright : MColors.border
    antialiasing: Constants.enableAntialiasing
    
    signal clicked()
    signal closeRequested()
    
    property var tabData: null
    property bool isCurrentTab: false
    
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Constants.borderRadiusSharp
        color: "transparent"
        border.width: Constants.borderWidthThin
        border.color: MColors.borderSubtle
        antialiasing: Constants.enableAntialiasing
    }
    
    Column {
        anchors.fill: parent
        anchors.margins: MSpacing.md
        spacing: MSpacing.sm
        
        Item {
            width: parent.width
            height: Constants.touchTargetSmall
            
            Icon {
                id: globeIcon
                anchors.left: parent.left
                anchors.top: parent.top
                name: "globe"
                size: Constants.iconSizeSmall
                color: isCurrentTab ? MColors.accentBright : MColors.textSecondary
            }
            
            Column {
                anchors.left: globeIcon.right
                anchors.leftMargin: MSpacing.sm
                anchors.right: closeButton.left
                anchors.rightMargin: MSpacing.sm
                anchors.top: parent.top
                spacing: 2
                
                Text {
                    width: parent.width
                    text: tabData ? (tabData.title || "New Tab") : "New Tab"
                    font.pixelSize: MTypography.sizeBody
                    font.weight: Font.DemiBold
                    color: isCurrentTab ? MColors.text : MColors.textSecondary
                    elide: Text.ElideRight
                }
                
                Text {
                    width: parent.width
                    text: tabData ? (tabData.url || "about:blank") : "about:blank"
                    font.pixelSize: MTypography.sizeSmall
                    color: MColors.textTertiary
                    elide: Text.ElideMiddle
                }
            }
            
            Rectangle {
                id: closeButton
                anchors.right: parent.right
                anchors.top: parent.top
                width: Constants.touchTargetSmall
                height: Constants.touchTargetSmall
                radius: Constants.borderRadiusSmall
                color: closeMouseArea.pressed ? Qt.rgba(1, 0, 0, 0.2) : "transparent"
                
                Icon {
                    anchors.centerIn: parent
                    name: "x"
                    size: Constants.iconSizeSmall
                    color: MColors.text
                }
                
                MouseArea {
                    id: closeMouseArea
                    anchors.fill: parent
                    onClicked: {
                        tabCard.closeRequested()
                    }
                }
            }
        }
        
        Rectangle {
            width: parent.width
            height: parent.height - Constants.touchTargetSmall - MSpacing.sm
            radius: Constants.borderRadiusSmall
            color: MColors.background
            border.width: Constants.borderWidthThin
            border.color: MColors.border
            clip: true
            
            Text {
                anchors.centerIn: parent
                text: tabData ? (tabData.title || tabData.url || "Loading...") : "Loading..."
                font.pixelSize: MTypography.sizeSmall
                color: MColors.textTertiary
            }
        }
    }
    
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: {
            tabCard.clicked()
        }
    }
}

