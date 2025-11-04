import QtQuick
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme

Item {
    id: toastContainer
    anchors.fill: parent
    z: 3000
    
    property var toastQueue: []
    property var currentToast: null
    
    function showToast(notification) {
        toastQueue.push(notification)
        if (!currentToast) {
            showNextToast()
        }
    }
    
    function showNextToast() {
        if (toastQueue.length === 0) {
            currentToast = null
            return
        }
        
        currentToast = toastQueue.shift()
        toast.notification = currentToast
        toast.visible = true
        toast.y = -toast.height
        slideIn.start()
        autoHideTimer.restart()
    }
    
    Rectangle {
        id: toast
        anchors.horizontalCenter: parent.horizontalCenter
        y: -height
        width: Math.min(parent.width - 32, 400)
        height: notification?.actions?.length > 0 ? Constants.hubHeaderHeight + 60 : Constants.hubHeaderHeight
        radius: Constants.borderRadiusSharp
        color: MColors.surface
        border.width: Constants.borderWidthMedium
        border.color: MColors.border
        antialiasing: Constants.enableAntialiasing
        visible: false
        
        property var notification: null
        
        Behavior on height {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
        
        // Inner border for depth
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Constants.borderRadiusSharp
            color: "transparent"
            border.width: Constants.borderWidthThin
            border.color: MColors.highlightMedium
            antialiasing: Constants.enableAntialiasing
        }
        
        Column {
            anchors.fill: parent
            anchors.margins: 12
            spacing: Constants.spacingMedium
            
            Row {
                width: parent.width
                height: MSpacing.touchTargetLarge
                spacing: Constants.spacingMedium
                
                Rectangle {
                    width: MSpacing.touchTargetLarge
                    height: MSpacing.touchTargetLarge
                    radius: Constants.borderRadiusSharp
                    color: MColors.surface
                    border.width: Constants.borderWidthThin
                    border.color: MColors.border
                    antialiasing: Constants.enableAntialiasing
                    
                    Icon {
                        name: toast.notification?.icon || "bell"
                        size: Constants.iconSizeMedium
                        color: MColors.text
                        anchors.centerIn: parent
                    }
                }
                
                Column {
                    width: parent.width - MSpacing.touchTargetLarge - Constants.spacingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    
                    Text {
                        text: toast.notification?.title || ""
                        color: MColors.text
                        font.pixelSize: MTypography.sizeBody
                        font.weight: Font.DemiBold
                        font.family: MTypography.fontFamily
                        elide: Text.ElideRight
                        width: parent.width
                    }
                    
                    Text {
                        text: toast.notification?.body || ""
                        color: MColors.textSecondary
                        font.pixelSize: MTypography.sizeSmall
                        font.family: MTypography.fontFamily
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }
                }
            }
            
            // Action buttons
            Row {
                width: parent.width
                height: 40
                spacing: Constants.spacingSmall
                visible: toast.notification?.actions?.length > 0
                
                Repeater {
                    model: toast.notification?.actions || []
                    
                    Rectangle {
                        width: (parent.width - (toast.notification.actions.length - 1) * Constants.spacingSmall) / toast.notification.actions.length
                        height: 40
                        radius: Constants.borderRadiusSmall
                        color: actionMouseArea.pressed ? MColors.accentPressed : (actionMouseArea.containsMouse ? MColors.accentHover : MColors.accent)
                        border.width: Constants.borderWidthThin
                        border.color: Qt.rgba(255, 255, 255, 0.2)
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
                            id: actionMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            
                            onClicked: {
                                Logger.info("NotificationToast", "Action clicked: " + modelData + " for notification " + toast.notification.id)
                                HapticService.light()
                                
                                // Trigger the action
                                NotificationService.triggerAction(toast.notification.id, modelData)
                                
                                // Handle specific actions
                                if (modelData.toLowerCase() === "reply") {
                                    // Open the app with reply interface
                                    Router.launchApp(toast.notification.appId, {"action": "reply", "notificationId": toast.notification.id})
                                } else if (modelData.toLowerCase() === "snooze") {
                                    // Snooze the notification for 10 minutes
                                    Logger.info("NotificationToast", "Snoozing notification for 10 minutes")
                                    // TODO: Implement snooze functionality
                                } else if (modelData.toLowerCase() === "view" || modelData.toLowerCase() === "open") {
                                    // Open the app
                                    Router.launchApp(toast.notification.appId)
                                } else if (modelData.toLowerCase() === "dismiss") {
                                    NotificationService.dismissNotification(toast.notification.id)
                                }
                                
                                // Dismiss the toast
                                dismissToast()
                            }
                        }
                    }
                }
            }
        }
        
        MouseArea {
            anchors.fill: parent
            onClicked: {
                Logger.info("NotificationToast", "Toast tapped: " + toast.notification.id)
                NotificationService.clickNotification(toast.notification.id)
                Router.goToHub()
                dismissToast()
            }
            
            property real startY: 0
            
            onPressed: (mouse) => {
                startY = mouse.y
            }
            
            onPositionChanged: (mouse) => {
                if (mouse.y - startY < -20) {
                    dismissToast()
                }
            }
        }
        
        NumberAnimation {
            id: slideIn
            target: toast
            property: "y"
            to: Constants.statusBarHeight + 16
            duration: 300
            easing.type: Easing.OutCubic
        }
        
        NumberAnimation {
            id: slideOut
            target: toast
            property: "y"
            to: -toast.height
            duration: 250
            easing.type: Easing.InCubic
            onFinished: {
                toast.visible = false
                toastContainer.showNextToast()
            }
        }
    }
    
    Timer {
        id: autoHideTimer
        interval: 5000
        onTriggered: dismissToast()
    }
    
    function dismissToast() {
        autoHideTimer.stop()
        slideOut.start()
    }
}

