import QtQuick
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import MarathonUI.Containers
import MarathonUI.Controls

Item {
    id: toastContainer
    anchors.fill: parent
    z: 3000
    
    property var toastQueue: []
    property var currentToast: null
    property bool showInlineReply: false
    
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
        toast.visible = true
        toast.y = -toast.height
        slideIn.start()
        autoHideTimer.restart()
    }
    
    MCard {
        id: toast
        anchors.horizontalCenter: parent.horizontalCenter
        y: -height
        width: parent.width - MSpacing.sm * 2
        height: showInlineReply ? 140 : 72
        elevation: 3
        visible: false
        
        Behavior on y {
            NumberAnimation { 
                duration: MMotion.moderate
                easing.bezierCurve: MMotion.easingDecelerateCurve
            }
        }
        
        Behavior on height {
            NumberAnimation {
                duration: MMotion.quick
                easing.bezierCurve: MMotion.easingDecelerateCurve
            }
        }
        
        Item {
            anchors.fill: parent
            
            Row {
                id: mainContent
                width: parent.width - MSpacing.xs * 2
                height: 56
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: showInlineReply ? undefined : parent.verticalCenter
                anchors.top: showInlineReply ? parent.top : undefined
                anchors.topMargin: showInlineReply ? MSpacing.xs : 0
                spacing: MSpacing.md
                
                Rectangle {
                width: 48
                height: 48
                radius: MRadius.md
                color: MColors.elevated
                anchors.verticalCenter: parent.verticalCenter
                    
                    Icon {
                    name: currentToast?.icon || "bell"
                    size: 24
                    color: MColors.textPrimary
                        anchors.centerIn: parent
                    }
                }
                
                Column {
                width: parent.width - 48 - MSpacing.md
                    anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                
                MLabel {
                    text: currentToast?.title || ""
                    variant: "primary"
                    font.weight: MTypography.weightBold
                        font.pixelSize: MTypography.sizeBody
                        elide: Text.ElideRight
                        width: parent.width
                    }
                    
                MLabel {
                    text: currentToast?.body || ""
                    variant: "secondary"
                        font.pixelSize: MTypography.sizeSmall
                        elide: Text.ElideRight
                    maximumLineCount: 1
                width: parent.width
                    }
                }
            }
            
            // Inline reply field (for messaging notifications)
            Row {
                width: parent.width - MSpacing.xs * 2
                height: 48
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: mainContent.bottom
                anchors.topMargin: MSpacing.sm
                spacing: MSpacing.sm
                visible: showInlineReply
                
                MTextInput {
                    id: replyField
                    width: parent.width - sendButton.width - MSpacing.sm
                    height: 40
                    placeholderText: "Reply..."
                    
                    onAccepted: {
                        if (text.trim().length > 0 && currentToast) {
                            Logger.info("NotificationToast", "Sending inline reply: " + text)
                            FreedesktopNotifications.InvokeReply(currentToast.id, text)
                            text = ""
                            showInlineReply = false
                            dismissToast()
                        }
                    }
                    
                    Keys.onEscapePressed: {
                        showInlineReply = false
                        text = ""
                    }
                }
                
                MButton {
                    id: sendButton
                    text: "Send"
                    width: 80
                    height: 40
                    enabled: replyField.text.trim().length > 0
                    onClicked: replyField.accepted()
                }
            }
        }
        
        MouseArea {
            anchors.fill: parent
            z: -1
            
            property real startY: 0
            property real dragY: 0
            
            onPressed: (mouse) => {
                startY = mouse.y
                dragY = 0
                autoHideTimer.stop()
            }
            
            onPositionChanged: (mouse) => {
                dragY = mouse.y - startY
                if (dragY < 0) {
                    toast.y = Math.max(toast.y + dragY * 0.5, -toast.height)
                }
            }
            
            onReleased: (mouse) => {
                if (dragY < -30) {
                    dismissToast()
                } else {
                    toast.y = Constants.statusBarHeight + MSpacing.sm
                    autoHideTimer.restart()
                }
            }
            
            onClicked: {
                // Check if this is a messaging notification that supports inline reply
                var supportsInlineReply = currentToast && (
                    currentToast.appId === "messages" ||
                    currentToast.appId === "org.telegram.desktop" ||
                    currentToast.appId === "signal-desktop" ||
                    (currentToast.category && currentToast.category.includes("message"))
                )
                
                if (supportsInlineReply && !showInlineReply) {
                    // Show inline reply field
                    Logger.info("NotificationToast", "Showing inline reply for: " + currentToast.id)
                    showInlineReply = true
                    autoHideTimer.stop()
                    
                    // Focus the reply field after a brief delay
                    Qt.callLater(function() {
                        replyField.forceActiveFocus()
                    })
                } else if (!showInlineReply) {
                    // Navigate to app
                Logger.info("NotificationToast", "Toast tapped: " + currentToast.id)
                NotificationService.clickNotification(currentToast.id)
                NotificationModel.markAsRead(currentToast.id)
                
                if (currentToast.appId) {
                    NavigationRouter.navigateToDeepLink(
                        currentToast.appId,
                        "",
                        {
                            "notificationId": currentToast.id,
                            "action": "view",
                            "from": "notification"
                        }
                    )
                } else {
                    Router.goToHub()
                }
                
                dismissToast()
                }
                }
            }
        }
        
        NumberAnimation {
            id: slideIn
            target: toast
            property: "y"
        to: Constants.statusBarHeight + MSpacing.sm
        duration: MMotion.moderate
        easing.bezierCurve: MMotion.easingDecelerateCurve
        }
        
        NumberAnimation {
            id: slideOut
            target: toast
            property: "y"
            to: -toast.height
        duration: MMotion.quick
        easing.bezierCurve: MMotion.easingAccelerateCurve
            onFinished: {
                toast.visible = false
                toastContainer.showNextToast()
        }
    }
    
    Timer {
        id: autoHideTimer
        interval: 5000
        onTriggered: dismissToast()
    }
    
    function dismissToast() {
        autoHideTimer.stop()
        showInlineReply = false
        replyField.text = ""
        slideOut.start()
    }
}
