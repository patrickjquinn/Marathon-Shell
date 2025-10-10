import QtQuick
import "../theme"
import "../stores"
import "."

Rectangle {
    id: hub
    anchors.fill: parent
    color: "#0A0A0A"
    
    signal closed()
    
    Column {
        anchors.fill: parent
        spacing: 0
        
        Rectangle {
            id: hubHeader
            width: parent.width
            height: 80
            color: "#1A1A1A"
            z: 1
            
            Row {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16
                
                Text {
                    text: "BlackBerry Hub"
                    color: "#FFFFFF"
                    font.pixelSize: 28
                    font.weight: Font.Bold
                    anchors.verticalCenter: parent.verticalCenter
                }
                
                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    color: "#006666"
                    anchors.verticalCenter: parent.verticalCenter
                    
                    Text {
                        text: NotificationStore.notifications.length.toString()
                        color: "#FFFFFF"
                        font.pixelSize: 16
                        font.weight: Font.Bold
                        anchors.centerIn: parent
                    }
                }
                
                Item { width: parent.width - 300; height: 1 }
                
                Rectangle {
                    width: 40
                    height: 40
                    radius: 20
                    color: "transparent"
                    border.width: 2
                    border.color: "#006666"
                    anchors.verticalCenter: parent.verticalCenter
                    z: 999
                    
                    Icon {
                        name: "x"
                        size: 24
                        color: "#006666"
                        anchors.centerIn: parent
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        z: 1000
                        onPressed: console.log("❌ Close button pressed")
                        onClicked: {
                            console.log("❌ Close button clicked - emitting closed()")
                            closed()
                        }
                    }
                }
            }
        }
        
        Row {
            id: hubTabs
            width: parent.width
            height: 60
            z: 0
            
            Repeater {
                model: [
                    { name: "All", icon: "inbox" },
                    { name: "Email", icon: "mail" },
                    { name: "Messages", icon: "message-square" },
                    { name: "Calls", icon: "phone" },
                    { name: "Social", icon: "users" }
                ]
                
                Rectangle {
                    width: hub.width / 5
                    height: 60
                    color: index === 0 ? "#004d4d" : "#1A1A1A"
                    
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 3
                        color: "#006666"
                        visible: index === 0
                    }
                    
                    Column {
                        anchors.centerIn: parent
                        spacing: 4
                        
                        Icon {
                            name: modelData.icon
                            size: 20
                            color: index === 0 ? "#00CCCC" : "#666666"
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        
                        Text {
                            text: modelData.name
                            color: index === 0 ? "#FFFFFF" : "#888888"
                            font.pixelSize: 11
                            font.weight: index === 0 ? Font.Bold : Font.Normal
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        onClicked: console.log("Hub tab clicked:", modelData.name)
                    }
                }
            }
        }
        
        ListView {
            id: notificationsList
            width: parent.width
            height: parent.height - hubHeader.height - hubTabs.height
            clip: true
            spacing: 0
            
            model: NotificationStore.notifications
            
            delegate: Rectangle {
                width: notificationsList.width
                height: 100
                color: modelData.read ? "#0A0A0A" : "#141414"
                
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: "#222222"
                }
                
                Row {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 16
                    
                    Rectangle {
                        width: 48
                        height: 48
                        radius: 24
                        color: modelData.type === "email" ? "#006666" :
                               modelData.type === "sms" ? "#00AA00" :
                               modelData.type === "call" ? "#0088FF" : "#FF8800"
                        anchors.verticalCenter: parent.verticalCenter
                        
                        Icon {
                            name: modelData.type === "email" ? "mail" :
                                  modelData.type === "sms" ? "message-square" :
                                  modelData.type === "call" ? "phone" : "bell"
                            size: 24
                            color: "#FFFFFF"
                            anchors.centerIn: parent
                        }
                    }
                    
                    Column {
                        width: parent.width - 120
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        
                        Row {
                            width: parent.width
                            spacing: 8
                            
                            Text {
                                text: modelData.title
                                color: modelData.read ? "#888888" : "#FFFFFF"
                                font.pixelSize: 18
                                font.weight: modelData.read ? Font.Normal : Font.Bold
                                elide: Text.ElideRight
                            }
                        }
                        
                        Text {
                            text: modelData.content || modelData.subtitle || ""
                            color: "#666666"
                            font.pixelSize: 14
                            width: parent.width
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.WordWrap
                        }
                    }
                    
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        
                        Text {
                            text: modelData.time
                            color: "#666666"
                            font.pixelSize: 12
                            anchors.right: parent.right
                        }
                        
                        Rectangle {
                            visible: !modelData.read
                            width: 10
                            height: 10
                            radius: 5
                            color: "#00CCCC"
                            anchors.right: parent.right
                        }
                    }
                }
                
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        console.log("Notification clicked:", modelData.title)
                        NotificationStore.markAsRead(modelData.id)
                    }
                }
            }
            
            Text {
                visible: notificationsList.count === 0
                text: "No notifications"
                color: "#666666"
                font.pixelSize: 18
                anchors.centerIn: parent
            }
        }
    }
}
