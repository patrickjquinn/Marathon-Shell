import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Core
import "../components"

SettingsPageTemplate {
    id: bluetoothPage
    pageTitle: "Bluetooth"
    
    property string pageName: "bluetooth"
    
    content: Flickable {
        contentHeight: bluetoothContent.height + Constants.navBarHeight + MSpacing.xl * 3
        clip: true
        boundsBehavior: Flickable.DragAndOvershootBounds
        
        Column {
            id: bluetoothContent
            width: parent.width
            spacing: MSpacing.lg
            leftPadding: MSpacing.lg
            rightPadding: MSpacing.lg
            topPadding: MSpacing.lg
            
            Rectangle {
                width: parent.width - MSpacing.lg * 2
                height: Constants.appIconSize
                radius: Constants.borderRadiusMedium
                color: Qt.rgba(255, 255, 255, 0.04)
                border.width: Constants.borderWidthThin
                border.color: Qt.rgba(255, 255, 255, 0.08)
                
                Icon {
                    id: bluetoothIcon
                    anchors.left: parent.left
                    anchors.leftMargin: MSpacing.md
                    anchors.verticalCenter: parent.verticalCenter
                    name: BluetoothManagerCpp.enabled ? "bluetooth" : "bluetooth-off"
                    size: Constants.iconSizeMedium
                    color: BluetoothManagerCpp.enabled ? MColors.marathonTeal : MColors.textSecondary
                }
                
                Column {
                    anchors.left: bluetoothIcon.right
                    anchors.leftMargin: MSpacing.md
                    anchors.right: bluetoothToggle.left
                    anchors.rightMargin: MSpacing.md
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: MSpacing.xs
                    
                    Text {
                        text: "Bluetooth"
                        color: MColors.textPrimary
                        font.pixelSize: MTypography.sizeBody
                        font.weight: Font.DemiBold
                        font.family: MTypography.fontFamily
                    }
                    
                    Text {
                        text: BluetoothManagerCpp.enabled ? (BluetoothManagerCpp.scanning ? "Scanning..." : "Enabled") : "Disabled"
                        color: MColors.textSecondary
                        font.pixelSize: MTypography.sizeSmall
                        font.family: MTypography.fontFamily
                    }
                }
                
                MToggle {
                    id: bluetoothToggle
                    anchors.right: parent.right
                    anchors.rightMargin: MSpacing.md
                    anchors.verticalCenter: parent.verticalCenter
                    checked: BluetoothManagerCpp.enabled
                    onToggled: {
                        BluetoothManagerCpp.enabled = !BluetoothManagerCpp.enabled
                    }
                }
            }
            
            MSection {
                title: "Paired Devices"
                width: parent.width - MSpacing.lg * 2
                visible: BluetoothManagerCpp.enabled && BluetoothManagerCpp.pairedDevices.length > 0
                
                Column {
                    width: parent.width
                    spacing: 0
                    
                    Repeater {
                        model: BluetoothManagerCpp.pairedDevices
                        
                        Rectangle {
                            width: parent.width
                            height: Constants.hubHeaderHeight
                            color: "transparent"
                            
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: Constants.borderRadiusSmall
                                color: deviceMouseArea.pressed ? Qt.rgba(20, 184, 166, 0.15) : "transparent"
                                
                                Behavior on color {
                                    ColorAnimation { duration: Constants.animationDurationFast }
                                }
                            }
                            
                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: MSpacing.md
                                anchors.rightMargin: MSpacing.md
                                spacing: MSpacing.md
                                
                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: modelData.icon || "bluetooth"
                                    size: Constants.iconSizeMedium
                                    color: modelData.connected ? MColors.marathonTeal : MColors.textSecondary
                                }
                                
                                Column {
                                    id: deviceColumn
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - Constants.iconSizeMedium - Constants.iconSizeSmall - MSpacing.md * 4
                                    
                                    Text {
                                        width: parent.width
                                        text: modelData.alias || modelData.name || modelData.address
                                        color: MColors.textPrimary
                                        font.pixelSize: MTypography.sizeBody
                                        font.family: MTypography.fontFamily
                                        elide: Text.ElideRight
                                    }
                                    
                                    Text {
                                        width: parent.width
                                        text: modelData.connected ? "Connected" : "Not connected"
                                        color: modelData.connected ? MColors.marathonTeal : MColors.textSecondary
                                        font.pixelSize: MTypography.sizeSmall
                                        font.family: MTypography.fontFamily
                                    }
                                }
                                
                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.right: parent.right
                                    name: "chevron-right"
                                    size: Constants.iconSizeSmall
                                    color: MColors.textSecondary
                                }
                            }
                            
                            MouseArea {
                                id: deviceMouseArea
                                anchors.fill: parent
                                onClicked: {
                                    if (modelData.connected) {
                                        BluetoothManagerCpp.disconnectDevice(modelData.address)
                                    } else {
                                        BluetoothManagerCpp.connectDevice(modelData.address)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            MSection {
                title: "Available Devices"
                width: parent.width - MSpacing.lg * 2
                visible: BluetoothManagerCpp.enabled
                
                Column {
                    width: parent.width
                    spacing: MSpacing.md
                    topPadding: MSpacing.md
                    
                    MButton {
                        anchors.horizontalCenter: parent.horizontalCenter
                        // width: parent.width - removed to allow implicit sizing
                        text: BluetoothManagerCpp.scanning ? "Stop Scanning" : "Scan for Devices"
                        variant: BluetoothManagerCpp.scanning ? "primary" : "default"
                        onClicked: {
                            if (BluetoothManagerCpp.scanning) {
                                BluetoothManagerCpp.stopScan()
                            } else {
                                BluetoothManagerCpp.startScan()
                            }
                        }
                    }
                    
                    Column {
                        width: parent.width
                        spacing: 0
                        visible: BluetoothManagerCpp.devices.length > 0
                        
                        Repeater {
                            model: BluetoothManagerCpp.devices
                            
                            Rectangle {
                                width: parent.width
                                height: Constants.hubHeaderHeight
                                color: "transparent"
                                visible: !modelData.paired
                                
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 1
                                    radius: Constants.borderRadiusSmall
                                    color: availableDeviceMouseArea.pressed ? Qt.rgba(20, 184, 166, 0.15) : "transparent"
                                    
                                    Behavior on color {
                                        ColorAnimation { duration: Constants.animationDurationFast }
                                    }
                                }
                                
                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: MSpacing.md
                                    anchors.rightMargin: MSpacing.md
                                    spacing: MSpacing.md
                                    
                                    Icon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: modelData.icon || "bluetooth"
                                        size: Constants.iconSizeMedium
                                        color: MColors.textSecondary
                                    }
                                    
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - Constants.iconSizeMedium - MSpacing.md * 2
                                        
                                        Text {
                                            width: parent.width
                                            text: modelData.alias || modelData.name || modelData.address
                                            color: MColors.textPrimary
                                            font.pixelSize: MTypography.sizeBody
                                            font.family: MTypography.fontFamily
                                            elide: Text.ElideRight
                                        }
                                        
                                        Text {
                                            width: parent.width
                                            text: modelData.rssi ? "Signal: " + modelData.rssi + " dBm" : "Available"
                                            color: MColors.textSecondary
                                            font.pixelSize: MTypography.sizeSmall
                                            font.family: MTypography.fontFamily
                                        }
                                    }
                                }
                                
                                MouseArea {
                                    id: availableDeviceMouseArea
                                    anchors.fill: parent
                                    onClicked: {
                                        Logger.info("BluetoothPage", "Selected device for pairing: " + modelData.name)
                                        HapticService.light()
                                        
                                        // Show pairing dialog
                                        // Most devices use "justworks" pairing, but some may require PIN
                                        bluetoothPairDialogLoader.show(
                                            modelData.name,
                                            modelData.address,
                                            modelData.type || "device",
                                            "justworks" // Will be updated if device requests PIN/passkey
                                        )
                                    }
                                }
                            }
                        }
                    }
                    
                    Text {
                        width: parent.width
                        text: BluetoothManagerCpp.scanning ? "Scanning for devices..." : "No devices found"
                        color: MColors.textSecondary
                        font.pixelSize: MTypography.sizeBody
                        font.family: MTypography.fontFamily
                        horizontalAlignment: Text.AlignHCenter
                        topPadding: MSpacing.lg
                        bottomPadding: MSpacing.lg
                        visible: BluetoothManagerCpp.devices.length === 0
                    }
                }
            }
            
            Item { height: Constants.navBarHeight }
        }
    }
    
    // Bluetooth pairing dialog
    Loader {
        id: bluetoothPairDialogLoader
        anchors.fill: parent
        active: false
        z: 1000
        
        sourceComponent: Component {
            BluetoothPairDialog {
                id: pairDialog
                anchors.fill: parent
                
                // Use direct signal handlers instead of .connect()
                onPairRequested: (pin) => {
                    Logger.info("BluetoothPage", "Pairing requested with PIN: " + (pin ? "****" : "none"))
                    BluetoothManagerCpp.pairDevice(deviceAddress, pin)
                }
                
                onPairConfirmed: (accepted) => {
                    Logger.info("BluetoothPage", "Pairing confirmation: " + accepted)
                    if (accepted) {
                        BluetoothManagerCpp.confirmPairing(deviceAddress, true)
                    } else {
                        BluetoothManagerCpp.confirmPairing(deviceAddress, false)
                        bluetoothPairDialogLoader.item.hide()
                    }
                }
                
                onCancelled: {
                    Logger.info("BluetoothPage", "Pairing cancelled")
                    BluetoothManagerCpp.cancelPairing(deviceAddress)
                }
            }
        }
        
        function show(name, address, type, mode) {
            active = true
            if (item) {
                item.show(name, address, type, mode)
            }
        }
    }
    
    Connections {
        target: BluetoothManagerCpp
        
        function onEnabledChanged() {
            if (BluetoothManagerCpp.enabled) {
                BluetoothManagerCpp.startScan()
            } else {
                BluetoothManagerCpp.stopScan()
            }
        }

        function onPairingSucceeded(address) {
            Logger.info("BluetoothPage", "✓ Successfully paired with: " + address)
            
            if (bluetoothPairDialogLoader.active && bluetoothPairDialogLoader.item) {
                bluetoothPairDialogLoader.item.hide()
            }
            
            HapticService.medium()
        }
        
        function onPairingFailed(address, error) {
            Logger.error("BluetoothPage", "✗ Failed to pair with " + address + ": " + error)
            
            if (bluetoothPairDialogLoader.active && bluetoothPairDialogLoader.item) {
                bluetoothPairDialogLoader.item.showError(error || "Pairing failed. Try again.")
            }
        }
        
        function onPinRequested(address, deviceName) {
            Logger.info("BluetoothPage", "PIN requested for device: " + deviceName)
            
            if (bluetoothPairDialogLoader.active && bluetoothPairDialogLoader.item) {
                // Update dialog to PIN entry mode
                bluetoothPairDialogLoader.item.show(deviceName, address, "device", "pin")
            }
        }
        
        function onPasskeyRequested(address, deviceName) {
            Logger.info("BluetoothPage", "Passkey requested for device: " + deviceName)
            
            if (bluetoothPairDialogLoader.active && bluetoothPairDialogLoader.item) {
                // Update dialog to passkey entry mode
                bluetoothPairDialogLoader.item.show(deviceName, address, "device", "passkey")
            }
        }
        
        function onPasskeyConfirmation(address, deviceName, passkey) {
            Logger.info("BluetoothPage", "Passkey confirmation requested: " + passkey)
            
            if (bluetoothPairDialogLoader.active && bluetoothPairDialogLoader.item) {
                // Update dialog to confirmation mode
                bluetoothPairDialogLoader.item.showPasskeyConfirmation(deviceName, address, "device", passkey)
            }
        }
    }
    
    Component.onCompleted: {
        Logger.info("BluetoothPage", "Initialized")
        // Start scanning if Bluetooth is enabled
        if (BluetoothManagerCpp.enabled) {
            BluetoothManagerCpp.startScan()
        }
    }
}
