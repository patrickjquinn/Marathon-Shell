import QtQuick
import QtQuick.Controls
import MarathonOS.Shell

Item {
    ListView {
        anchors.fill: parent
        anchors.topMargin: Constants.spacingMedium
        clip: true
        model: calendarApp.events
        spacing: 0
        
        delegate: Item {
            width: parent.width
            height: Constants.touchTargetLarge
            
            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: Constants.spacingLarge
                anchors.rightMargin: Constants.spacingLarge
                color: "transparent"
                
                Column {
                    anchors.fill: parent
                    anchors.margins: Constants.spacingMedium
                    spacing: Constants.spacingXSmall
                    
                    Text {
                        text: modelData.title
                        color: Colors.text
                        font.pixelSize: Constants.fontSizeMedium
                        font.weight: Font.DemiBold
                    }
                    
                    Text {
                        text: modelData.allDay ? Qt.formatDate(new Date(modelData.date), "MMM d, yyyy") : 
                              Qt.formatDate(new Date(modelData.date), "MMM d") + " at " + modelData.time
                        color: Colors.textSecondary
                        font.pixelSize: Constants.fontSizeSmall
                    }
                }
                
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Constants.spacingMedium
                    anchors.rightMargin: Constants.spacingMedium
                    height: Constants.borderWidthThin
                    color: Colors.border
                }
            }
        }
        
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width * 0.8, Constants.screenWidth * 0.6)
            height: emptyColumn.height
            color: "transparent"
            visible: parent.count === 0
            
            Column {
                id: emptyColumn
                anchors.centerIn: parent
                spacing: Constants.spacingLarge
                
                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "calendar"
                    size: Constants.iconSizeXLarge * 2
                    color: Colors.textSecondary
                    opacity: 0.5
                }
                
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No events"
                    color: Colors.textSecondary
                    font.pixelSize: Constants.fontSizeLarge
                    font.weight: Font.Medium
                }
            }
        }
    }
}

