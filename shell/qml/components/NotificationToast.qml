import QtQuick
import MarathonOS.Shell
import "../MarathonUI/Theme"

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
        height: 80
        radius: MRadius.sm
        color: Qt.rgba(0, 0, 0, 0.95)
        border.width: 1
        border.color: MColors.border
        visible: false
        
        property var notification: null
        
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: parent.radius - 1
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(255, 255, 255, 0.03)
        }
        
        Row {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12
            
            Rectangle {
                width: MSpacing.touchTargetLarge
                height: MSpacing.touchTargetLarge
                radius: MRadius.sm
                color: Qt.rgba(255, 255, 255, 0.05)
                border.width: 1
                border.color: Qt.rgba(255, 255, 255, 0.08)
                anchors.verticalCenter: parent.verticalCenter
                
                Icon {
                    name: toast.notification?.icon || "bell"
                    size: 32
                    color: MColors.text
                    anchors.centerIn: parent
                }
            }
            
            Column {
                width: parent.width - 72
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                
                Text {
                    text: toast.notification?.title || ""
                    color: Colors.text
                    font.pixelSize: Typography.sizeBody
                    font.weight: Font.DemiBold
                    font.family: Typography.fontFamily
                    elide: Text.ElideRight
                    width: parent.width
                }
                
                Text {
                    text: toast.notification?.body || ""
                    color: Colors.textSecondary
                    font.pixelSize: Typography.sizeSmall
                    font.family: Typography.fontFamily
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.WordWrap
                    width: parent.width
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

