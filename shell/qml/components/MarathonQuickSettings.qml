import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import "../MarathonUI/Theme"
import "../MarathonUI/Controls"
import "."

Rectangle {
    id: quickSettings
    color: MColors.background
    opacity: 0.98
    
    signal closed()
    signal launchApp(var app)
    
    property real dragStartY: 0
    property bool isDragging: false
    
    MouseArea {
        anchors.fill: parent
        z: -1
        propagateComposedEvents: true
        
        onPressed: (mouse) => {
            dragStartY = mouse.y
            isDragging = false
        }
        
        onPositionChanged: (mouse) => {
            if (Math.abs(mouse.y - dragStartY) > 10) {
                isDragging = true
            }
            if (isDragging && (mouse.y - dragStartY) < -50) {
                closed()
            }
        }
        
        onReleased: {
            if (isDragging && (dragStartY > 0)) {
                closed()
            }
            isDragging = false
            dragStartY = 0
        }
    }
    
    Flickable {
        id: scrollView
        anchors.fill: parent
        anchors.topMargin: Constants.spacingLarge
        anchors.leftMargin: Constants.spacingMedium
        anchors.rightMargin: Constants.spacingMedium
        anchors.bottomMargin: 80
        contentHeight: contentColumn.height
        clip: true
        
        flickDeceleration: 5000
        maximumFlickVelocity: 2500
        
        Column {
            id: contentColumn
            width: parent.width
            spacing: Constants.spacingMedium
        
            Text {
                text: SystemStatusStore.dateString
                color: MColors.text
                font.pixelSize: MTypography.sizeBody
                font.weight: MTypography.weightNormal
                font.family: MTypography.fontFamily
                anchors.left: parent.left
            }
            
            // Paginated Quick Settings Toggles
            Column {
                width: parent.width
                spacing: Constants.spacingMedium
                
                SwipeView {
                    id: toggleSwipeView
                    width: parent.width
                    height: Constants.isTallScreen ? 450 : 340
                    clip: true
                    interactive: true
                    
                    // Page 1
                    Item {
                        width: toggleSwipeView.width
                        height: toggleSwipeView.height
                        
                        Grid {
                            anchors.fill: parent
                            columns: 2
                            columnSpacing: Constants.spacingSmall
                            rowSpacing: Constants.spacingSmall
                            
                            Repeater {
                                model: [
                                    { id: "settings", icon: "settings", label: "Settings", active: false },
                                    { id: "lock", icon: "lock", label: "Lock device", active: false },
                                    { id: "rotation", icon: "rotate-ccw", label: "Rotation lock", active: SystemControlStore.isRotationLocked },
                                    { id: "wifi", icon: "wifi", label: "Wi-Fi", active: SystemControlStore.isWifiOn, subtitle: SystemStatusStore.wifiNetwork || "" },
                                    { id: "bluetooth", icon: "bluetooth", label: "Bluetooth", active: SystemControlStore.isBluetoothOn },
                                    { id: "flight", icon: "plane", label: "Flight mode", active: SystemControlStore.isAirplaneModeOn },
                                    { id: "torch", icon: "sun", label: "Torch", active: SystemControlStore.isFlashlightOn },
                                    { id: "alarm", icon: "clock", label: "Alarm", active: SystemControlStore.isAlarmOn }
                                ]
                                
                                delegate: QuickSettingsTile {
                                    tileWidth: (toggleSwipeView.width - 12) / 2
                                    toggleData: modelData
                                    onTapped: handleToggleTap(modelData.id)
                                    onLongPressed: handleLongPress(modelData.id)
                                }
                            }
                        }
                    }
                    
                    // Page 2
                    Item {
                        width: toggleSwipeView.width
                        height: toggleSwipeView.height
                        
                        Grid {
                            anchors.fill: parent
                            columns: 2
                            columnSpacing: 12
                            rowSpacing: 12
                            
                            Repeater {
                                model: [
                                    { id: "cellular", icon: "signal", label: "Mobile network", active: SystemControlStore.isCellularOn, subtitle: (typeof CellularManager !== 'undefined' ? CellularManager.operatorName : "") || "No service" },
                                    { id: "notifications", icon: "bell", label: "Notifications", active: SystemControlStore.isDndMode, subtitle: "Normal" },
                                    { id: "battery", icon: "battery", label: "Battery saving", active: SystemControlStore.isLowPowerMode },
                                    { id: "monitor", icon: "info", label: "Device monitor", active: false, subtitle: "Battery " + SystemStatusStore.batteryLevel + "%" }
                                ]
                                
                                delegate: QuickSettingsTile {
                                    tileWidth: (toggleSwipeView.width - 12) / 2
                                    toggleData: modelData
                                    onTapped: handleToggleTap(modelData.id)
                                    onLongPressed: handleLongPress(modelData.id)
                                }
                            }
                        }
                    }
                }
                
                // Page indicator
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Constants.spacingSmall
                    
                    Repeater {
                        model: toggleSwipeView.count
                        
                        Rectangle {
                            width: index === toggleSwipeView.currentIndex ? 24 : 8
                            height: 8
                            radius: MRadius.md
                            color: index === toggleSwipeView.currentIndex ? MColors.accent : Qt.rgba(255, 255, 255, 0.3)
                            
                            Behavior on width {
                                NumberAnimation { duration: 200 }
                            }
                            
                            Behavior on color {
                                ColorAnimation { duration: 200 }
                            }
                        }
                    }
                }
            }
            
            // Media Playback Manager
            MediaPlaybackManager {
                id: mediaPlayer
                width: parent.width
            }
            
            // Brightness Slider
            Column {
                width: parent.width
                spacing: MSpacing.md
                
                Text {
                    text: "Brightness"
                    color: MColors.text
                    font.pixelSize: MTypography.sizeBody
                    font.weight: MTypography.weightMedium
                    font.family: MTypography.fontFamily
                }
                
                MSlider {
                    width: parent.width
                    from: 0
                    to: 100
                    value: SystemControlStore.brightness
                    onMoved: {
                        SystemControlStore.setBrightness(value)
                    }
                }
            }
            
            // Volume Slider
            Column {
                width: parent.width
                spacing: MSpacing.md
                
                Text {
                    text: "Volume"
                    color: MColors.text
                    font.pixelSize: MTypography.sizeBody
                    font.weight: MTypography.weightMedium
                    font.family: MTypography.fontFamily
                }
                
                MSlider {
                    width: parent.width
                    from: 0
                    to: 100
                    value: SystemControlStore.volume
                    onMoved: {
                        SystemControlStore.setVolume(value)
                    }
                }
            }
            
            Item { height: Constants.navBarHeight }
        }
    }
    
    // Handle toggle tap
    function handleToggleTap(toggleId) {
        Logger.info("QuickSettings", "Toggle tapped: " + toggleId)
        
        if (toggleId === "wifi") {
            SystemControlStore.toggleWifi()
        } else if (toggleId === "bluetooth") {
            SystemControlStore.toggleBluetooth()
        } else if (toggleId === "flight") {
            SystemControlStore.toggleAirplaneMode()
        } else if (toggleId === "rotation") {
            SystemControlStore.toggleRotationLock()
        } else if (toggleId === "torch") {
            SystemControlStore.toggleFlashlight()
        } else if (toggleId === "alarm") {
            SystemControlStore.toggleAlarm()
            UIStore.closeQuickSettings()
            Qt.callLater(function() {
                var app = { id: "clock", name: "Clock", icon: "qrc:/images/clock.svg", type: "marathon" }
                launchApp(app)
            })
        } else if (toggleId === "battery") {
            SystemControlStore.toggleLowPowerMode()
        } else if (toggleId === "settings") {
            UIStore.closeQuickSettings()
            Qt.callLater(function() {
                var app = { id: "settings", name: "Settings", icon: "qrc:/images/settings.svg", type: "marathon" }
                launchApp(app)
            })
        } else if (toggleId === "lock") {
            UIStore.closeQuickSettings()
            Qt.callLater(function() {
                SessionStore.lock()
            })
        } else if (toggleId === "cellular") {
            SystemControlStore.toggleCellular()
        } else if (toggleId === "notifications") {
            SystemControlStore.toggleDndMode()
        } else if (toggleId === "monitor") {
            Logger.info("QuickSettings", "Device monitor - info only, no action")
        }
    }
    
    // Handle long press (deep link to settings)
    function handleLongPress(toggleId) {
        Logger.info("QuickSettings", "Toggle long-pressed: " + toggleId)
        
        // Ignore long press for settings and lock tiles
        if (toggleId === "settings" || toggleId === "lock") {
            return
        }
        
        var deepLinkMap = {
            "wifi": "marathon://settings/wifi",
            "bluetooth": "marathon://settings/bluetooth",
            "cellular": "marathon://settings/cellular",
            "flight": "marathon://settings/cellular",
            "rotation": "marathon://settings/display",
            "torch": "marathon://settings/display",
            "alarm": "marathon://settings/sound",
            "notifications": "marathon://settings/notifications",
            "battery": "marathon://settings/about",
            "settings": "marathon://settings"
        }
        
        var deepLink = deepLinkMap[toggleId]
        if (deepLink) {
            NavigationRouter.navigate(deepLink)
            UIStore.closeQuickSettings()
        }
    }
}
