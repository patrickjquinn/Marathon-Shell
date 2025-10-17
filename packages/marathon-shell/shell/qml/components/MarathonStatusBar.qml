import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme

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
        
        Text {
            text: SystemStatusStore.batteryLevel + "%"
            color: StatusBarIconService.getBatteryColor(SystemStatusStore.batteryLevel, SystemStatusStore.isCharging)
            font.pixelSize: Constants.fontSizeSmall
            font.family: Typography.fontFamily
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    
    Text {
        anchors.centerIn: parent
        text: SystemStatusStore.timeString
        color: MColors.text
        font.pixelSize: Constants.fontSizeMedium
        font.weight: Font.Medium
    }
    
    Row {
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
            visible: StatusBarIconService.shouldShowBluetooth(SystemStatusStore.isBluetoothOn)
        }
        
        Icon {
            name: StatusBarIconService.getSignalIcon(SystemStatusStore.cellularStrength)
            color: MColors.text
            size: Constants.iconSizeSmall
            anchors.verticalCenter: parent.verticalCenter
            opacity: StatusBarIconService.getSignalOpacity(SystemStatusStore.cellularStrength)
            visible: SystemStatusStore.cellularStrength > 0
        }
        
        Icon {
            name: StatusBarIconService.getWifiIcon(SystemStatusStore.isWifiOn, SystemStatusStore.wifiStrength)
            color: MColors.text
            size: Constants.iconSizeSmall
            anchors.verticalCenter: parent.verticalCenter
            opacity: StatusBarIconService.getWifiOpacity(SystemStatusStore.isWifiOn, SystemStatusStore.wifiStrength)
        }
    }
}

