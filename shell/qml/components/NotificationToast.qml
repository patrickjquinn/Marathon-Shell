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
        height: 72
        elevation: 3
        visible: false
        
        Behavior on y {
            NumberAnimation { 
                duration: MMotion.moderate
                easing.bezierCurve: MMotion.easingDecelerateCurve
            }
        }
        
        Row {
            anchors.fill: parent
            anchors.leftMargin: MSpacing.xs
            anchors.rightMargin: MSpacing.xs
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
        slideOut.start()
    }
}
