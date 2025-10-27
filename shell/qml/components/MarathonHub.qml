import QtQuick
import MarathonOS.Shell
import "."

Rectangle {
    id: hub
    anchors.fill: parent
    color: MColors.backgroundDark
    
    signal closed()
    
    property int selectedTabIndex: 0
    property bool isInPeekMode: false  // Set by parent (MarathonPeek vs MarathonPageView)
    
    // Cache frequently-used properties for performance
    readonly property int cachedSafeAreaTop: Constants.safeAreaTop
    readonly property int cachedTouchTargetSmall: Constants.touchTargetSmall
    readonly property int cachedBorderRadiusSharp: Constants.borderRadiusSharp
    readonly property int cachedBorderWidthThin: Constants.borderWidthThin
    readonly property color cachedAccentBright: MColors.accentBright
    readonly property color cachedSurface: MColors.surface
    readonly property color cachedSurface2: MColors.surface2
    readonly property color cachedBorderOuter: MColors.borderOuter
    readonly property color cachedBorderInner: MColors.borderInner
    
    Column {
        anchors.fill: parent
        anchors.topMargin: hub.isInPeekMode ? hub.cachedSafeAreaTop : 0
        spacing: 0
                    
        Row {
            id: hubTabs
            width: parent.width
            height: hub.cachedTouchTargetSmall
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
                    height: hub.cachedTouchTargetSmall
                    
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: hub.cachedBorderRadiusSharp
                        color: index === hub.selectedTabIndex ? hub.cachedSurface2 : hub.cachedSurface
                        border.width: hub.cachedBorderWidthThin
                        border.color: index === hub.selectedTabIndex ? hub.cachedAccentBright : hub.cachedBorderOuter
                        antialiasing: Constants.enableAntialiasing
                        
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
                            radius: hub.cachedBorderRadiusSharp
                            color: "transparent"
                            border.width: hub.cachedBorderWidthThin
                            border.color: hub.cachedBorderInner
                            antialiasing: Constants.enableAntialiasing
                        }
                        
                        Column {
                            anchors.centerIn: parent
                            spacing: 4
                            
                            Icon {
                                name: modelData.icon
                                size: Constants.iconSizeSmall
                                color: index === hub.selectedTabIndex ? hub.cachedAccentBright : MColors.textSecondary
                                anchors.horizontalCenter: parent.horizontalCenter
                                opacity: index === hub.selectedTabIndex ? 1.0 : (tabMouseArea.pressed ? 0.8 : 0.6)
                                
                                Behavior on opacity {
                                    NumberAnimation { duration: 200 }
                                }
                            }
                            
                            Text {
                                text: modelData.name
                                color: index === hub.selectedTabIndex ? hub.cachedAccentBright : MColors.textSecondary
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
            
            model: NotificationModel
            
            delegate: Rectangle {
                width: notificationsList.width
                height: Constants.bottomBarHeight
                color: model.isRead ? MColors.backgroundDark : MColors.surface
                
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: MColors.borderOuter
                }
                
                Row {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: Constants.spacingMedium
                    
                    Rectangle {
                        width: 48
                        height: 48
                        radius: 24
                        color: MColors.accentDim
                        anchors.verticalCenter: parent.verticalCenter
                        antialiasing: Constants.enableAntialiasing
                        
                        Icon {
                            name: "bell"
                            size: Constants.iconSizeMedium
                            color: MColors.text
                            anchors.centerIn: parent
                        }
                    }
                    
                    Column {
                        width: parent.width - 120
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        
                        Row {
                            width: parent.width
                            spacing: Constants.spacingSmall
                            
                            Text {
                                text: model.title
                                color: model.isRead ? MColors.textSecondary : MColors.text
                                font.pixelSize: Typography.sizeBody
                                font.weight: model.isRead ? Font.Normal : Font.Bold
                                elide: Text.ElideRight
                            }
                        }
                        
                        Text {
                            text: model.body || ""
                            color: MColors.textSecondary
                            font.pixelSize: Typography.sizeSmall
                            width: parent.width
                            elide: Text.ElideRight
                            maximumLineCount: 2
                            wrapMode: Text.WordWrap
                        }
                    }
                    
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Constants.spacingSmall
                        
                        Text {
                            text: Qt.formatDateTime(new Date(model.timestamp), "hh:mm")
                            color: MColors.textSecondary
                            font.pixelSize: Typography.sizeXSmall
                            anchors.right: parent.right
                        }
                        
                        Rectangle {
                            visible: !model.isRead
                            width: 10
                            height: 10
                            radius: Constants.borderRadiusSharp
                            color: MColors.accentBright
                            anchors.right: parent.right
                            antialiasing: Constants.enableAntialiasing
                        }
                    }
                }
                
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        console.log("Notification clicked:", model.title)
                        NotificationModel.markAsRead(model.id)
                    }
                }
            }
            
            Text {
                visible: notificationsList.count === 0
                text: "No notifications"
                color: MColors.textSecondary
                font.pixelSize: Typography.sizeBody
                anchors.centerIn: parent
            }
        }
    }
}
