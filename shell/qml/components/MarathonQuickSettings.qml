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
    
    // RESPONSIVE GRID CALCULATIONS (like CSS Grid)
    // 2 cols: < 800px (phones including 720x720)
    // 3 cols: 800-1200px (tablets)
    // 4 cols: > 1200px (large tablets, desktop)
    readonly property int gridColumns: Constants.screenWidth < 800 ? 2 : (Constants.screenWidth < 1200 ? 3 : 4)
    readonly property real tileHeight: Constants.hubHeaderHeight
    // Calculate how many rows fit: subtract date (50) + sliders (160) + spacing
    readonly property real reservedHeight: 50 + 160 + Constants.spacingMedium * 4 + Constants.spacingLarge * 2 + 80
    readonly property real availableGridHeight: Math.max(tileHeight * 3, height - reservedHeight)
    readonly property int maxGridRows: Math.max(3, Math.min(5, Math.floor(availableGridHeight / (tileHeight + Constants.spacingSmall))))
    readonly property int tilesPerPage: gridColumns * maxGridRows
    readonly property real calculatedGridHeight: (tileHeight * maxGridRows) + (Constants.spacingSmall * (maxGridRows - 1))
    
    // Reactive properties for tile updates
    property string networkSubtitle: SystemStatusStore.ethernetConnected ? 
        (NetworkManager.ethernetConnectionName || "Wired") : 
        (SystemStatusStore.wifiNetwork || "Not connected")
    property string networkIcon: SystemStatusStore.ethernetConnected ? "plug-zap" : "wifi"  // Using "plug-zap" for ethernet (Lucide icon)
    property string networkLabel: SystemStatusStore.ethernetConnected ? "Ethernet" : "Wi-Fi"
    property string cellularSubtitle: (typeof CellularManager !== 'undefined' ? CellularManager.operatorName : "") || "No service"
    property string batterySubtitle: "Battery " + SystemStatusStore.batteryLevel + "%"
    
    // Force model updates when key properties change
    property int updateTrigger: 0
    
    // ALL TILES MODEL (accessible from anywhere in quickSettings)
    property var allTiles: [
        { id: "settings", icon: "settings", label: "Settings", active: false, available: true, trigger: updateTrigger },
        { id: "lock", icon: "lock", label: "Lock device", active: false, available: true, trigger: updateTrigger },
        { id: "rotation", icon: "rotate-ccw", label: "Rotation lock", active: SystemControlStore.isRotationLocked, available: true, trigger: updateTrigger },
        { id: "wifi", icon: networkIcon, label: networkLabel, active: SystemControlStore.isWifiOn || SystemStatusStore.ethernetConnected, available: NetworkManager.wifiAvailable || SystemStatusStore.ethernetConnected, subtitle: networkSubtitle, trigger: updateTrigger },
        { id: "bluetooth", icon: "bluetooth", label: "Bluetooth", active: SystemControlStore.isBluetoothOn, available: NetworkManager.bluetoothAvailable, trigger: updateTrigger },
        { id: "flight", icon: "plane", label: "Flight mode", active: SystemControlStore.isAirplaneModeOn, available: true, trigger: updateTrigger },
        { id: "cellular", icon: "signal", label: "Mobile network", active: SystemControlStore.isCellularOn, available: (typeof ModemManagerCpp !== 'undefined' && ModemManagerCpp.modemAvailable), subtitle: cellularSubtitle, trigger: updateTrigger },
        { id: "notifications", icon: "bell", label: "Notifications", active: SystemControlStore.isDndMode, available: true, subtitle: SystemControlStore.isDndMode ? "Silent" : "Normal", trigger: updateTrigger },
        { id: "torch", icon: "sun", label: "Torch", active: SystemControlStore.isFlashlightOn, available: (typeof FlashlightManager !== 'undefined' ? FlashlightManager.available : false), trigger: updateTrigger },
        { id: "alarm", icon: "clock", label: "Alarm", active: SystemControlStore.isAlarmOn, available: true, trigger: updateTrigger },
        { id: "battery", icon: "battery", label: "Battery saving", active: SystemControlStore.isLowPowerMode, available: true, trigger: updateTrigger },
        { id: "monitor", icon: "info", label: "Device monitor", active: false, available: true, subtitle: batterySubtitle, trigger: updateTrigger }
    ]
    
    Connections {
        target: SystemControlStore
        function onIsWifiOnChanged() { updateTrigger++ }
        function onIsBluetoothOnChanged() { updateTrigger++ }
        function onIsAirplaneModeOnChanged() { updateTrigger++ }
        function onIsCellularOnChanged() { updateTrigger++ }
    }
    
    Connections {
        target: SystemStatusStore
        function onWifiNetworkChanged() { updateTrigger++ }
        function onEthernetConnectedChanged() { updateTrigger++ }
        function onBatteryLevelChanged() { updateTrigger++ }
    }
    
    Connections {
        target: NetworkManager
        function onEthernetConnectionNameChanged() { updateTrigger++ }
    }
    
    Component.onCompleted: {
        Logger.info("QuickSettings", "Grid layout: " + gridColumns + " cols × " + maxGridRows + " rows (screen: " + Constants.screenWidth + "px)")
    }
    
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
    
    // Center container for responsive layout
    Item {
        anchors.fill: parent
        
        Item {
            id: contentContainer
            anchors.centerIn: parent
            // Use full width on mobile (<= 1080px), max 800px on tablets/desktop
            width: Constants.screenWidth <= 1080 ? parent.width : Math.min(parent.width, 800)
            height: parent.height
            
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
                font.pixelSize: Constants.fontSizeMedium
                font.weight: Font.Normal
                font.family: Typography.fontFamily
                anchors.left: parent.left
            }
            
            // Paginated Quick Settings Toggles
            Column {
                width: parent.width
                spacing: Constants.spacingMedium
                
                SwipeView {
                    id: toggleSwipeView
                    width: parent.width
                    height: calculatedGridHeight
                    clip: true
                    interactive: count > 1
                    
                    // Dynamically create pages based on tilesPerPage
                    Repeater {
                        model: Math.ceil(allTiles.length / tilesPerPage)
                        
                        Item {
                            width: toggleSwipeView.width
                            height: toggleSwipeView.height
                            
                            Grid {
                                anchors.fill: parent
                                columns: gridColumns
                                columnSpacing: Constants.spacingSmall
                                rowSpacing: Constants.spacingSmall
                                
                                Repeater {
                                    model: {
                                        var startIdx = index * tilesPerPage
                                        var endIdx = Math.min(startIdx + tilesPerPage, allTiles.length)
                                        return allTiles.slice(startIdx, endIdx)
                                    }
                                    
                                    delegate: QuickSettingsTile {
                                        tileWidth: (toggleSwipeView.width - (Constants.spacingSmall * (gridColumns - 1))) / gridColumns
                                        toggleData: modelData
                                        onTapped: handleToggleTap(modelData.id)
                                        onLongPressed: handleLongPress(modelData.id)
                                    }
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
                spacing: Constants.spacingSmall
                
                Text {
                    text: "Brightness"
                    color: MColors.text
                    font.pixelSize: Constants.fontSizeMedium
                    font.weight: Font.Medium
                    font.family: Typography.fontFamily
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
                spacing: Constants.spacingSmall
                
                Text {
                    text: "Volume"
                    color: MColors.text
                    font.pixelSize: Constants.fontSizeMedium
                    font.weight: Font.Medium
                    font.family: Typography.fontFamily
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
        
        // Ignore long press for settings, lock, and monitor (info-only) tiles
        if (toggleId === "settings" || toggleId === "lock" || toggleId === "monitor") {
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
            "battery": "marathon://settings/power",
            "settings": "marathon://settings"
            // Note: "monitor" is info-only, no deep link
        }
        
        var deepLink = deepLinkMap[toggleId]
        if (deepLink) {
            Logger.info("QuickSettings", "Navigating to deep link: " + deepLink)
            NavigationRouter.navigate(deepLink)
            UIStore.closeQuickSettings()
        }
    }
}
