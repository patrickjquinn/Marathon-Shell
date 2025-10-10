import QtQuick
import "../theme"
import "."
import "../stores"

Item {
    id: messagingHub
    height: showVertical ? parent.height : 50
    
    property bool showVertical: false
    property var messages: [
        { id: 1, type: "email", title: "New Email", content: "You have a new email from John", count: 3 },
        { id: 2, type: "sms", title: "SMS", content: "Don't forget our meeting at 3 PM", count: 1 },
        { id: 3, type: "notification", title: "App Update", content: "A new version is available", count: 2 }
    ]
    
    signal toggleNotifications()
    
    Rectangle {
        id: background
        anchors.fill: parent
        color: WallpaperStore.isDark ? "#000000" : "#FFFFFF"
        opacity: 0.3
        z: 0
    }
    
    Row {
        visible: !showVertical
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12
        z: 1
        
        Repeater {
            model: messages
            
            Rectangle {
                width: 32
                height: 32
                radius: 16
                color: "transparent"
                
                Icon {
                    name: "bell"
                    size: 20
                    color: Colors.text
                    anchors.centerIn: parent
                }
                
                Rectangle {
                    visible: modelData.count > 1
                    anchors.top: parent.top
                    anchors.right: parent.right
                    width: 16
                    height: 16
                    radius: 8
                    color: Colors.error
                    
                    Text {
                        anchors.centerIn: parent
                        text: modelData.count
                        color: Colors.text
                        font.pixelSize: 10
                    }
                }
                
                MouseArea {
                    anchors.fill: parent
                    onClicked: showVertical = true
                }
            }
        }
    }
    
    Rectangle {
        visible: showVertical
        width: parent.width
        height: 150
        color: "#000000"
        opacity: 0.9
        z: 1
        
        Rectangle {
            width: parent.width
            height: 50
            color: "transparent"
            
            Row {
                anchors.centerIn: parent
                spacing: 12
                
                Text {
                    text: "Notifications"
                    color: Colors.text
                    font.pixelSize: Typography.sizeBody
                    font.weight: Font.Bold
                }
                
                Text {
                    text: "▼"
                    color: Colors.text
                    font.pixelSize: 12
                }
            }
            
            MouseArea {
                anchors.fill: parent
                onClicked: showVertical = false
            }
        }
        
        ListView {
            width: parent.width
            height: parent.height - 100
            model: messages
            spacing: 8
            clip: true
            
            delegate: Rectangle {
                width: ListView.view.width - 20
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

