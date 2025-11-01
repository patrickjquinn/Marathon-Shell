import QtQuick
import MarathonOS.Shell
import "."
import MarathonUI.Theme

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
                            spacing: Constants.spacingXSmall
                            
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
                                font.pixelSize: MTypography.sizeXSmall
                                font.family: MTypography.fontFamily
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
                id: notificationDelegate
                width: notificationsList.width
                height: {
                    var baseHeight = Constants.bottomBarHeight
                    // Add extra height if notification has actions
                    if (model.actions && model.actions.length > 0) {
                        return baseHeight + 60
                    }
                    return baseHeight
                }
                color: model.isRead ? MColors.backgroundDark : MColors.surface
                
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: Constants.dividerHeight
                    color: MColors.borderOuter
                }
                
                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: Constants.spacingMedium
                    
                    Row {
                        width: parent.width
                        height: Math.round(48 * Constants.scaleFactor)
                        spacing: Constants.spacingMedium
                        
                        Rectangle {
                            width: Math.round(48 * Constants.scaleFactor)
                            height: Math.round(48 * Constants.scaleFactor)
                            radius: Math.round(24 * Constants.scaleFactor)
                            color: MColors.accentDim
                            anchors.verticalCenter: parent.verticalCenter
                            antialiasing: Constants.enableAntialiasing
                            
                            Icon {
                                name: model.icon || "bell"
                                size: Constants.iconSizeMedium
                                color: MColors.text
                                anchors.centerIn: parent
                            }
                        }
                        
                        Column {
                            width: parent.width - Math.round(48 * Constants.scaleFactor) - Math.round(72 * Constants.scaleFactor) - Constants.spacingMedium * 2
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Constants.spacingXSmall
                            
                            Text {
                                text: model.title
                                color: model.isRead ? MColors.textSecondary : MColors.text
                                font.pixelSize: MTypography.sizeBody
                                font.weight: model.isRead ? Font.Normal : Font.Bold
                                font.family: MTypography.fontFamily
                                elide: Text.ElideRight
                                width: parent.width
                            }
                            
                            Text {
                                text: model.body || ""
                                color: MColors.textSecondary
                                font.pixelSize: MTypography.sizeSmall
                                font.family: MTypography.fontFamily
                                width: parent.width
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                wrapMode: Text.WordWrap
                            }
                        }
                        
                        Column {
                            width: Math.round(72 * Constants.scaleFactor)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Constants.spacingSmall
                            
                            Text {
                                text: Qt.formatDateTime(new Date(model.timestamp), "hh:mm")
                                color: MColors.textSecondary
                                font.pixelSize: MTypography.sizeXSmall
                                font.family: MTypography.fontFamily
                                anchors.right: parent.right
                            }
                            
                            Rectangle {
                                visible: !model.isRead
                                width: Constants.smallIndicatorSize + Math.round(2 * Constants.scaleFactor)
                                height: Constants.smallIndicatorSize + Math.round(2 * Constants.scaleFactor)
                                radius: Constants.borderRadiusSharp
                                color: MColors.accentBright
                                anchors.right: parent.right
                                antialiasing: Constants.enableAntialiasing
                            }
                        }
                    }
                    
                    // Action buttons row
                    Row {
                        width: parent.width
                        height: 40
                        spacing: Constants.spacingSmall
                        visible: model.actions && model.actions.length > 0
                        
                        Repeater {
                            model: notificationDelegate.ListView.view.model.getNotificationActions ? 
                                   notificationDelegate.ListView.view.model.getNotificationActions(index) : 
                                   (notificationDelegate.ListView.view.model.get(index).actions || [])
                            
                            Rectangle {
                                property int actionCount: notificationDelegate.ListView.view.model.getNotificationActions ? 
                                                          notificationDelegate.ListView.view.model.getNotificationActions(index).length : 
                                                          (notificationDelegate.ListView.view.model.get(index).actions ? notificationDelegate.ListView.view.model.get(index).actions.length : 0)
                                
                                width: actionCount > 0 ? (parent.width - (actionCount - 1) * Constants.spacingSmall) / actionCount : 0
                                height: 40
                                radius: Constants.borderRadiusSmall
                                color: actionBtnMouseArea.pressed ? MColors.accentPressed : (actionBtnMouseArea.containsMouse ? MColors.accentHover : MColors.accent)
                                border.width: Constants.borderWidthThin
                                border.color: Qt.rgba(255, 255, 255, 0.15)
                                antialiasing: Constants.enableAntialiasing
                                
                                Behavior on color {
                                    ColorAnimation { duration: Constants.animationDurationFast }
                                }
                                
                                Text {
                                    text: {
                                        var action = modelData.toLowerCase()
                                        if (action === "reply") return "Reply"
                                        if (action === "snooze") return "Snooze"
                                        if (action === "view") return "View"
                                        if (action === "dismiss") return "Dismiss"
                                        if (action === "open") return "Open"
                                        if (action === "archive") return "Archive"
                                        if (action === "delete") return "Delete"
                                        return modelData
                                    }
                                    color: MColors.text
                                    font.pixelSize: MTypography.sizeSmall
                                    font.weight: Font.Medium
                                    font.family: MTypography.fontFamily
                                    anchors.centerIn: parent
                                }
                                
                                MouseArea {
                                    id: actionBtnMouseArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    
                                    onClicked: (mouse) => {
                                        Logger.info("Hub", "Action clicked: " + modelData)
                                        HapticService.light()
                                        
                                        // Get the notification from parent delegate
                                        var notification = notificationDelegate.ListView.view.model.get(index)
                                        if (notification) {
                                            // Trigger the action
                                            NotificationService.triggerAction(notification.id, modelData)
                                            
                                            // Handle specific actions
                                            if (modelData.toLowerCase() === "reply") {
                                                Router.launchApp(notification.appId, {"action": "reply", "notificationId": notification.id})
                                                Router.goHome()
                                            } else if (modelData.toLowerCase() === "snooze") {
                                                Logger.info("Hub", "Snoozing notification for 10 minutes")
                                                NotificationService.dismissNotification(notification.id)
                                            } else if (modelData.toLowerCase() === "view" || modelData.toLowerCase() === "open") {
                                                Router.launchApp(notification.appId)
                                                Router.goHome()
                                            } else if (modelData.toLowerCase() === "dismiss" || modelData.toLowerCase() === "delete") {
                                                NotificationService.dismissNotification(notification.id)
                                            } else if (modelData.toLowerCase() === "archive") {
                                                NotificationService.dismissNotification(notification.id)
                                            }
                                        }
                                        
                                        mouse.accepted = true
                                    }
                                }
                            }
                        }
                    }
                }
                
                MouseArea {
                    anchors.fill: parent
                    z: -1
                    onClicked: {
                        Logger.info("Hub", "Notification clicked: " + model.title)
                        NotificationModel.markAsRead(model.id)
                        
                        // Open the app if available
                        if (model.appId) {
                            Router.launchApp(model.appId)
                            Router.goHome()
                        }
                    }
                }
            }
            
            Text {
                visible: notificationsList.count === 0
                text: "No notifications"
                color: MColors.textSecondary
                font.pixelSize: MTypography.sizeBody
                anchors.centerIn: parent
            }
        }
    }
}
