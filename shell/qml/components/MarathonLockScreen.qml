import QtQuick
import MarathonOS.Shell
import "."
import "./ui"

Item {
    id: lockScreen
    anchors.fill: parent
    
    signal unlockRequested()
    signal cameraLaunched()
    signal notificationTapped(string id)
    
    property real swipeProgress: 0.0
    property real swipeCenterX: 0.5
    property real swipeCenterY: 0.5
    property string expandedNotificationId: ""
    
    Rectangle {
        id: lockContent
        anchors.fill: parent
        color: MColors.background
    
    Image {
        anchors.fill: parent
        source: WallpaperStore.path
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
    }
    
    // Dismiss expanded notifications when tapping elsewhere
    MouseArea {
        anchors.fill: parent
        z: 1
        enabled: expandedNotificationId !== ""
        onClicked: {
            expandedNotificationId = ""
            Logger.info("LockScreen", "Notifications dismissed")
        }
    }
    
        MarathonStatusBar {
            id: statusBar
        width: parent.width
            z: 5
        }
        
        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: Math.round(-80 * Constants.scaleFactor)
            spacing: Constants.spacingSmall
            
            Text {
                text: SystemStatusStore.timeString
                color: MColors.text
                font.pixelSize: Constants.fontSizeGigantic
                font.weight: Font.Thin
                anchors.horizontalCenter: parent.horizontalCenter
                
                // Drop shadow using multiple text layers
                Text {
                    text: parent.text
                    color: "#80000000"
                    font.pixelSize: parent.font.pixelSize
                    font.weight: parent.font.weight
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: 2
                    z: -1
                }
            }
            
            Text {
                text: SystemStatusStore.dateString
                color: MColors.text
                font.pixelSize: Typography.sizeLarge
                font.weight: Font.Normal
                anchors.horizontalCenter: parent.horizontalCenter
                opacity: 0.9
                
                // Drop shadow using multiple text layers
                Text {
                    text: parent.text
                    color: "#80000000"
                    font.pixelSize: parent.font.pixelSize
                    font.weight: parent.font.weight
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: 2
                    z: -1
                    opacity: parent.opacity
                }
            }
        }
        
        Column {
            anchors.left: parent.left
            anchors.leftMargin: Constants.spacingLarge
            anchors.verticalCenter: parent.verticalCenter
            spacing: Constants.spacingMedium
            z: 10
            
            Repeater {
                model: Math.min(NotificationModel.count, 4)
                
                Item {
                    width: expandedNotificationId === modelData.id ? Math.round(300 * Constants.scaleFactor) : Math.round(48 * Constants.scaleFactor)
                    height: Math.round(48 * Constants.scaleFactor)
                    
                    Behavior on width {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                    
                    Rectangle {
                        anchors.fill: parent
                        color: expandedNotificationId === modelData.id ? MColors.surface : "transparent"
                        radius: Constants.borderRadiusSharp
                        antialiasing: Constants.enableAntialiasing
                        
                        Behavior on color {
                            ColorAnimation { duration: 200 }
                        }
                        
                        Row {
                            anchors.fill: parent
                            anchors.margins: 4
                            spacing: Constants.spacingMedium
                            
                            Rectangle {
                                width: Constants.touchTargetMinimum
                                height: Constants.touchTargetMinimum
                                radius: Math.round(20 * Constants.scaleFactor)
                                color: expandedNotificationId === modelData.id ? MColors.surface2 : "transparent"
                                border.width: expandedNotificationId === modelData.id ? 0 : Constants.borderWidthThin
                                border.color: MColors.borderOuter
                                anchors.verticalCenter: parent.verticalCenter
                                antialiasing: Constants.enableAntialiasing
                                
                                Behavior on color {
                                    ColorAnimation { duration: 200 }
                                }
                                Behavior on border.width {
                                    NumberAnimation { duration: 200 }
                                }
                                
                                Image {
                                    source: modelData.icon
                                    width: Math.round(24 * Constants.scaleFactor)
                                    height: Math.round(24 * Constants.scaleFactor)
                                    fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: true
                                    anchors.centerIn: parent
                                }
                                
                                Rectangle {
                                    visible: !modelData.read
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.rightMargin: Math.round(-4 * Constants.scaleFactor)
                                    anchors.topMargin: Math.round(-4 * Constants.scaleFactor)
                                    width: Math.round(18 * Constants.scaleFactor)
                                    height: Math.round(18 * Constants.scaleFactor)
                                    radius: Constants.borderRadiusSharp
                                    color: MColors.error
                                    antialiasing: Constants.enableAntialiasing
                                    
                                    Text {
                                        text: "1"
                                        color: MColors.text
                                        font.pixelSize: Typography.sizeXSmall
                                        font.weight: Font.Bold
                                        anchors.centerIn: parent
                                    }
                                }
                            }
                            
    Column {
                                visible: expandedNotificationId === modelData.id
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - Math.round(68 * Constants.scaleFactor)
                                spacing: Math.round(2 * Constants.scaleFactor)
        
        Text {
                                    text: modelData.title
                                    color: MColors.text
                                    font.pixelSize: Typography.sizeSmall
                                    font.weight: Font.Bold
                                    elide: Text.ElideRight
                                    width: parent.width
        }
        
        Text {
                                    text: modelData.subtitle
                                    color: MColors.textSecondary
                                    font.pixelSize: Typography.sizeXSmall
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                            }
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            z: 100
                            
                            property var notification: modelData
                            
                            onClicked: {
                                if (expandedNotificationId === notification.id) {
                                    // Second tap: dismiss notification
                                    expandedNotificationId = ""
                                    Logger.info("LockScreen", "Notification dismissed: " + notification.title)
                                } else {
                                    // First tap: expand notification
                                    expandedNotificationId = notification.id
                                    Logger.info("LockScreen", "Notification expanded: " + notification.title)
                                }
                            }
                        }
                    }
                }
            }
        }
        
        MarathonBottomBar {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            showPageIndicators: false
        }
        
        Canvas {
            id: dissolveCanvas
            anchors.fill: parent
            z: 100
            visible: swipeProgress > 0
            
            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                
                ctx.fillStyle = "#000000"
                ctx.fillRect(0, 0, width, height)
                
                ctx.globalCompositeOperation = "destination-out"
                
                var centerX = swipeCenterX * width
                var centerY = swipeCenterY * height
                var maxDist = Math.sqrt(width * width + height * height)
                var radius = swipeProgress * maxDist
                
                for (var i = 0; i < 20; i++) {
                    var angle = (i / 20) * Math.PI * 2
                    var length = radius * (0.9 + Math.random() * 0.2)
                    
                    var gradient = ctx.createLinearGradient(
                        centerX, centerY,
                        centerX + Math.cos(angle) * length,
                        centerY + Math.sin(angle) * length
                    )
                    gradient.addColorStop(0, "rgba(255,255,255,1)")
                    gradient.addColorStop(1, "rgba(255,255,255,0)")
                    
                    ctx.beginPath()
                    ctx.moveTo(centerX, centerY)
                    ctx.lineTo(
                        centerX + Math.cos(angle) * length,
                        centerY + Math.sin(angle) * length
                    )
                    ctx.lineWidth = 80
                    ctx.strokeStyle = gradient
                    ctx.lineCap = "round"
                    ctx.stroke()
                }
                
                var radialGrad = ctx.createRadialGradient(centerX, centerY, 0, centerX, centerY, radius * 0.6)
                radialGrad.addColorStop(0, "rgba(255,255,255,1)")
                radialGrad.addColorStop(1, "rgba(255,255,255,0)")
                ctx.fillStyle = radialGrad
                ctx.beginPath()
                ctx.arc(centerX, centerY, radius * 0.6, 0, Math.PI * 2)
                ctx.fill()
            }
        }
        
        opacity: 1.0 - swipeProgress
    }
    
    MouseArea {
        anchors.fill: parent
        z: 5
        propagateComposedEvents: true
        
        property real startX: 0
        property real startY: 0
        property bool isDragging: false
        
        onPressed: (mouse) => {
            startX = mouse.x
            startY = mouse.y
            isDragging = false
            swipeCenterX = mouse.x / width
            swipeCenterY = mouse.y / height
            Logger.debug("LockScreen", "Touch at: " + mouse.x + ", " + mouse.y)
            
            // Let notifications handle their own clicks if touch is on them
            if (mouse.y > height * 0.3 && mouse.y < height * 0.7 && mouse.x < 350) {
                mouse.accepted = false
            }
        }
        
        onPositionChanged: (mouse) => {
            var distance = Math.sqrt(
                Math.pow(mouse.x - startX, 2) + 
                Math.pow(mouse.y - startY, 2)
            )
            
            if (distance > 10) {
                isDragging = true
            }
            
            if (isDragging) {
                swipeCenterX = mouse.x / width
                swipeCenterY = mouse.y / height
                // Easier unlock: only need to swipe 20% of screen height
                swipeProgress = Math.min(1.0, distance / (height * 0.20))
                dissolveCanvas.requestPaint()
            }
        }
        
        onReleased: (mouse) => {
            // Lower threshold: 25% progress (5% of screen height)
            if (isDragging && swipeProgress > 0.25) {
                swipeProgress = 1.0
                dissolveCanvas.requestPaint()
                unlockTimer.start()
            } else {
                swipeProgress = 0
                if (isDragging) {
                    expandedNotificationId = ""
                }
            }
            isDragging = false
        }
    }
    
    Behavior on swipeProgress {
        enabled: swipeProgress < 1.0
        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
    }
    
    Timer {
        id: unlockTimer
        interval: 150
        onTriggered: {
            Logger.state("LockScreen", "dissolveComplete", "unlocking")
            unlockRequested()
        }
    }
}
