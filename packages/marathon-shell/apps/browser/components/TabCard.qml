import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme

Rectangle {
    id: tabCard
    height: Constants.cardHeight
    radius: Constants.borderRadiusSharp
    color: isCurrentTab ? MColors.surface2 : MColors.surface
    border.width: Constants.borderWidthThin
    border.color: isCurrentTab ? MColors.accentBright : MColors.borderOuter
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
        border.color: MColors.borderInner
        antialiasing: Constants.enableAntialiasing
    }
    
    Column {
        anchors.fill: parent
        anchors.margins: Constants.spacingMedium
        spacing: Constants.spacingSmall
        
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
                anchors.leftMargin: Constants.spacingSmall
                anchors.right: closeButton.left
                anchors.rightMargin: Constants.spacingSmall
                anchors.top: parent.top
                spacing: 2
                
                Text {
                    width: parent.width
                    text: tabData ? (tabData.title || "New Tab") : "New Tab"
                    font.pixelSize: Constants.fontSizeMedium
                    font.weight: Font.DemiBold
                    color: isCurrentTab ? MColors.text : MColors.textSecondary
                    elide: Text.ElideRight
                }
                
                Text {
                    width: parent.width
                    text: tabData ? (tabData.url || "about:blank") : "about:blank"
                    font.pixelSize: Constants.fontSizeSmall
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
            height: parent.height - Constants.touchTargetSmall - Constants.spacingSmall
            radius: Constants.borderRadiusSmall
            color: MColors.backgroundDark
            border.width: Constants.borderWidthThin
            border.color: MColors.borderOuter
            clip: true
            
            Text {
                anchors.centerIn: parent
                text: tabData ? (tabData.title || tabData.url || "Loading...") : "Loading..."
                font.pixelSize: Constants.fontSizeSmall
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

