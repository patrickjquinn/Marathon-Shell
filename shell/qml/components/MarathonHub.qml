import QtQuick
import MarathonOS.Shell
import "."

Rectangle {
    id: hub
    anchors.fill: parent
    anchors.topMargin: Constants.safeAreaTop
    color: Qt.rgba(0.05, 0.05, 0.05, 0.95)
    
    signal closed()
    
    property int selectedTabIndex: 0
    
    Column {
        anchors.fill: parent
        spacing: 0
                    
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
                
                Item {
                    width: hub.width / 5
                    height: 60
                    
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: 3
                        color: index === hub.selectedTabIndex ? Qt.rgba(20, 184, 166, 0.15) : Qt.rgba(255, 255, 255, 0.03)
                        border.width: 1
                        border.color: index === hub.selectedTabIndex ? Qt.rgba(20, 184, 166, 0.7) : Qt.rgba(255, 255, 255, 0.08)
                        layer.enabled: true
                        
                        transform: Translate {
                            y: tabMouseArea.pressed ? -1 : 0
                            
                            Behavior on y {
                                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                            }
                        }
                        
                        Behavior on border.color {
                            ColorAnimation { duration: 150 }
                        }
                        
                        Behavior on color {
                            ColorAnimation { duration: 150 }
                        }
                        
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 1
                            radius: parent.radius - 1
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.rgba(255, 255, 255, 0.02)
                        }
                        
                        Column {
                            anchors.centerIn: parent
                            spacing: 4
                            
                            Icon {
                                name: modelData.icon
                                size: 20
                                color: index === hub.selectedTabIndex ? Colors.accent : Colors.textTertiary
                                anchors.horizontalCenter: parent.horizontalCenter
                                opacity: index === hub.selectedTabIndex ? 1.0 : (tabMouseArea.pressed ? 0.8 : 0.6)
                                
                                Behavior on opacity {
                                    NumberAnimation { duration: 200 }
                                }
                            }
                            
                            Text {
                                text: modelData.name
                                color: index === hub.selectedTabIndex ? Colors.accent : Colors.textTertiary
                                font.pixelSize: Typography.sizeXSmall
                                font.family: Typography.fontFamily
                                font.weight: index === hub.selectedTabIndex ? Font.DemiBold : Font.Normal
                                anchors.horizontalCenter: parent.horizontalCenter
                                opacity: index === hub.selectedTabIndex ? 1.0 : (tabMouseArea.pressed ? 0.8 : 0.7)
                                
                                Behavior on opacity {
                                    NumberAnimation { duration: 200 }
                                }
                            }
                        }
                    }
                    
                    MouseArea {
                        id: tabMouseArea
                        anchors.fill: parent
                        
                        
                        z: 100
                        onClicked: {
                            hub.selectedTabIndex = index
                            Logger.info("Hub", "Switched to tab: " + modelData.name + " (index: " + index + ")")
                        }
                    }
                }
            }
        }
        
        ListView {
            id: notificationsList
            width: parent.width
            height: parent.height - hubTabs.height
            clip: true
            spacing: 0
            cacheBuffer: Math.max(0, height * 2)
            reuseItems: true
            
            model: NotificationStore.notifications
            
            delegate: Rectangle {
                width: notificationsList.width
                height: 100
                color: modelData.read ? Colors.backgroundDark : Colors.surface
                
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: Colors.surfaceLight
                }
                
                Row {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 16
                    
                    Rectangle {
                        width: 48
                        height: 48
                        radius: Colors.cornerRadiusCircle
                        color: modelData.type === "email" ? Colors.accent :
                               modelData.type === "sms" ? Colors.success :
                               modelData.type === "call" ? "#0088FF" : Colors.warning
                        anchors.verticalCenter: parent.verticalCenter
                        
                        Icon {
                            name: modelData.type === "email" ? "mail" :
                                  modelData.type === "sms" ? "message-square" :
                                  modelData.type === "call" ? "phone" : "bell"
                            size: 24
                            color: Colors.text
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
                                color: modelData.read ? Colors.textSecondary : Colors.text
                                font.pixelSize: Typography.sizeBody
                                font.weight: modelData.read ? Font.Normal : Font.Bold
                                elide: Text.ElideRight
                            }
                        }
                        
                        Text {
                            text: modelData.content || modelData.subtitle || ""
                            color: Colors.textTertiary
                            font.pixelSize: Typography.sizeSmall
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
                            color: Colors.textTertiary
                            font.pixelSize: Typography.sizeXSmall
                            anchors.right: parent.right
                        }
                        
                        Rectangle {
                            visible: !modelData.read
                            width: 10
                            height: 10
                            radius: Colors.cornerRadiusSmall
                            color: Colors.accentLight
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
                color: Colors.textSecondary
                font.pixelSize: Typography.sizeBody
                anchors.centerIn: parent
            }
        }
    }
}
