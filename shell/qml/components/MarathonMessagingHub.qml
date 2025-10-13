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
                height: 60
                anchors.horizontalCenter: parent.horizontalCenter
                color: "#FFFFFF"
                opacity: 0.1
                radius: 8
                
                Row {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12
                    
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
            radius: 20
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 20
            color: "#FFFFFF"
            opacity: 0.2
            
            Text {
                anchors.centerIn: parent
                text: "▼"
                color: Colors.text
                font.pixelSize: 16
            }
            
            MouseArea {
                anchors.fill: parent
                onClicked: showVertical = false
            }
        }
    }
}

