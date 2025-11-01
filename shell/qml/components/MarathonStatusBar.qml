import QtQuick
import MarathonOS.Shell

Item {
    id: statusBar
    height: Constants.statusBarHeight
    
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: WallpaperStore.isDark ? "#80000000" : "#80FFFFFF" }
            GradientStop { position: 1.0; color: "transparent" }
        }
        z: Constants.zIndexBackground
    }
    
    Row {
        id: leftIconGroup
        anchors.left: parent.left
        anchors.leftMargin: Constants.spacingMedium
        anchors.verticalCenter: parent.verticalCenter
        spacing: Constants.spacingSmall
        z: 1
        
        Icon {
            name: StatusBarIconService.getBatteryIcon(SystemStatusStore.batteryLevel, SystemStatusStore.isCharging)
            color: StatusBarIconService.getBatteryColor(SystemStatusStore.batteryLevel, SystemStatusStore.isCharging)
            size: Constants.iconSizeSmall
            anchors.verticalCenter: parent.verticalCenter
        }
        
        // Charging indicator (bolt icon overlay)
        Icon {
            name: "zap"
            color: MColors.success
            size: Constants.iconSizeSmall
            anchors.verticalCenter: parent.verticalCenter
            visible: SystemStatusStore.isCharging
        }
        
        Text {
            text: SystemStatusStore.batteryLevel + "%"
            color: StatusBarIconService.getBatteryColor(SystemStatusStore.batteryLevel, SystemStatusStore.isCharging)
            font.pixelSize: Constants.fontSizeSmall
            font.family: Typography.fontFamily
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    
    Text {
        id: clockText
        text: SystemStatusStore.timeString
        color: MColors.text
        font.pixelSize: Constants.fontSizeMedium
        font.weight: Font.Medium
        anchors.verticalCenter: parent.verticalCenter
        
        // Dynamic position based on setting
        property string position: (typeof SettingsManagerCpp !== 'undefined' && SettingsManagerCpp.statusBarClockPosition) ? SettingsManagerCpp.statusBarClockPosition : "center"
        
        states: [
            State {
                name: "left"
                when: clockText.position === "left"
                AnchorChanges {
                    target: clockText
                    anchors.horizontalCenter: undefined
                    anchors.left: parent.left
                    anchors.right: undefined
                }
                PropertyChanges {
                    target: clockText
                    // Properly position after left icons (actual width + spacing + margin)
                    anchors.leftMargin: leftIconGroup.x + leftIconGroup.width + Constants.spacingLarge
                }
            },
            State {
                name: "center"
                when: clockText.position === "center" || !clockText.position
                AnchorChanges {
                    target: clockText
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.left: undefined
                    anchors.right: undefined
                }
            },
            State {
                name: "right"
                when: clockText.position === "right"
                AnchorChanges {
                    target: clockText
                    anchors.horizontalCenter: undefined
                    anchors.left: undefined
                    anchors.right: parent.right
                }
                PropertyChanges {
                    target: clockText
                    // Properly position before right icons (actual width + spacing + margin)
                    anchors.rightMargin: rightIconGroup.width + rightIconGroup.anchors.rightMargin + Constants.spacingLarge
                }
            }
        ]
    }
    
    Row {
        id: rightIconGroup
        anchors.right: parent.right
        anchors.rightMargin: Constants.spacingMedium
        anchors.verticalCenter: parent.verticalCenter
        spacing: Constants.spacingMedium
        z: 1
        
        Icon {
            name: "plane"
            color: MColors.text
            size: Constants.iconSizeSmall
            anchors.verticalCenter: parent.verticalCenter
            visible: StatusBarIconService.shouldShowAirplaneMode(SystemStatusStore.isAirplaneMode)
        }
        
        Icon {
            name: "bell"
            color: MColors.text
            size: Constants.iconSizeSmall
            anchors.verticalCenter: parent.verticalCenter
            visible: StatusBarIconService.shouldShowDND(SystemStatusStore.isDndMode)
            opacity: 0.9
        }
        
        Icon {
            name: StatusBarIconService.getBluetoothIcon(SystemStatusStore.isBluetoothOn, SystemStatusStore.isBluetoothConnected)
            color: MColors.text
            size: Constants.iconSizeSmall
            anchors.verticalCenter: parent.verticalCenter
            opacity: StatusBarIconService.getBluetoothOpacity(SystemStatusStore.isBluetoothOn, SystemStatusStore.isBluetoothConnected)
            visible: NetworkManager.bluetoothAvailable && StatusBarIconService.shouldShowBluetooth(SystemStatusStore.isBluetoothOn)
        }
        
        // Cellular - always show, signal-off (crossed antenna) when unavailable
        Icon {
            name: (typeof ModemManagerCpp !== 'undefined' && ModemManagerCpp.modemAvailable) 
                  ? StatusBarIconService.getSignalIcon(SystemStatusStore.cellularStrength)
                  : "smartphone"
            color: MColors.text
            size: Constants.iconSizeSmall
            anchors.verticalCenter: parent.verticalCenter
            opacity: (typeof ModemManagerCpp !== 'undefined' && ModemManagerCpp.modemAvailable) 
                     ? StatusBarIconService.getSignalOpacity(SystemStatusStore.cellularStrength)
                     : 0.3
        }
        
        // Ethernet - only show when connected
        Icon {
            name: "cable"  // Using cable icon instead of plug-zap to avoid confusion with power
            color: MColors.text
            size: Constants.iconSizeSmall
            anchors.verticalCenter: parent.verticalCenter
            visible: SystemStatusStore.ethernetConnected
            opacity: 1.0
        }
        
        // WiFi - always show, wifi-off when unavailable
        Icon {
            name: NetworkManager.wifiAvailable ? StatusBarIconService.getWifiIcon(SystemStatusStore.isWifiOn, SystemStatusStore.wifiStrength, NetworkManager.wifiConnected) : "wifi-off"
            color: MColors.text
            size: Constants.iconSizeSmall
            anchors.verticalCenter: parent.verticalCenter
            opacity: NetworkManager.wifiAvailable ? StatusBarIconService.getWifiOpacity(SystemStatusStore.isWifiOn, SystemStatusStore.wifiStrength, NetworkManager.wifiConnected) : 0.3
        }
    }
}

