import QtQuick
import MarathonOS.Shell
import "."

Item {
    id: messagingHub
    height: 0
    visible: false
    
    property bool showVertical: false
    
    Rectangle {
        visible: false
        width: parent.width
        height: parent.height
        color: "#CC000000"
        z: 1
        
        ListView {
            width: parent.width
            height: parent.height
            model: []
            spacing: 0
            clip: true
            
            delegate: Rectangle {
                width: ListView.view.width
                height: Constants.touchTargetSmall
                anchors.horizontalCenter: parent.horizontalCenter
                color: "#FFFFFF"
                opacity: 0.1
                radius: Constants.borderRadiusSmall
                
                Row {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: Constants.spacingMedium
                    
                    Icon {
                        name: "bell"
                        size: 28
                        color: Colors.text
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        
                        Text {
                            text: modelData.title
                            color: Colors.text
                            font.pixelSize: Typography.sizeBody
                            font.weight: Font.Bold
                        }
                        
                        Text {
                            text: modelData.content
                            color: Colors.textSecondary
                            font.pixelSize: Typography.sizeSmall
                        }
                    }
                }
            }
        }
        
        Rectangle {
            width: 40
            height: 40
            radius: Constants.borderRadiusXLarge
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Constants.spacingLarge
            color: "#FFFFFF"
            opacity: 0.2
            
            Text {
                anchors.centerIn: parent
                text: "▼"
                color: Colors.text
                font.pixelSize: Constants.fontSizeMedium
            }
            
            MouseArea {
                anchors.fill: parent
                onClicked: showVertical = false
            }
        }
    }
}

