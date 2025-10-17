import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Core
import "../components"

SettingsPageTemplate {
    id: bluetoothPage
    pageTitle: "Bluetooth"
    
    property string pageName: "bluetooth"
    
    content: Flickable {
        contentHeight: bluetoothContent.height + Constants.navBarHeight + Constants.spacingXLarge * 3
        clip: true
        boundsBehavior: Flickable.DragAndOvershootBounds
        
        Column {
            id: bluetoothContent
            width: parent.width
            spacing: Constants.spacingLarge
            leftPadding: Constants.spacingLarge
            rightPadding: Constants.spacingLarge
            topPadding: Constants.spacingLarge
            
            Rectangle {
                width: parent.width - Constants.spacingLarge * 2
                height: Constants.appIconSize
                radius: Constants.borderRadiusMedium
                color: Qt.rgba(255, 255, 255, 0.04)
                border.width: Constants.borderWidthThin
                border.color: Qt.rgba(255, 255, 255, 0.08)
                
                Icon {
                    id: bluetoothIcon
                    anchors.left: parent.left
                    anchors.leftMargin: Constants.spacingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    name: BluetoothManagerCpp.enabled ? "bluetooth" : "bluetooth-off"
                    size: Constants.iconSizeMedium
                    color: BluetoothManagerCpp.enabled ? Colors.accent : Colors.textSecondary
                }
                
                Column {
                    anchors.left: bluetoothIcon.right
                    anchors.leftMargin: Constants.spacingMedium
                    anchors.right: bluetoothToggle.left
                    anchors.rightMargin: Constants.spacingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Constants.spacingXSmall
                    
                    Text {
                        text: "Bluetooth"
                        color: Colors.text
                        font.pixelSize: Typography.sizeBody
                        font.weight: Font.DemiBold
                        font.family: Typography.fontFamily
                    }
                    
                    Text {
                        text: BluetoothManagerCpp.enabled ? (BluetoothManagerCpp.scanning ? "Scanning..." : "Enabled") : "Disabled"
                        color: Colors.textSecondary
                        font.pixelSize: Typography.sizeSmall
                        font.family: Typography.fontFamily
                    }
                }
                
                MarathonToggle {
                    id: bluetoothToggle
                    anchors.right: parent.right
                    anchors.rightMargin: Constants.spacingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    checked: BluetoothManagerCpp.enabled
                    onToggled: {
                        BluetoothManagerCpp.enabled = !BluetoothManagerCpp.enabled
                    }
                }
            }
            
            Section {
                title: "Paired Devices"
                width: parent.width - Constants.spacingLarge * 2
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
                                anchors.leftMargin: Constants.spacingMedium
                                anchors.rightMargin: Constants.spacingMedium
                                spacing: Constants.spacingMedium
                                
                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: modelData.icon || "bluetooth"
                                    size: Constants.iconSizeMedium
                                    color: modelData.connected ? Colors.accent : Colors.textSecondary
                                }
                                
                                Column {
                                    id: deviceColumn
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - Constants.iconSizeMedium - Constants.iconSizeSmall - Constants.spacingMedium * 4
                                    
                                    Text {
                                        width: parent.width
                                        text: modelData.alias || modelData.name || modelData.address
                                        color: Colors.text
                                        font.pixelSize: Typography.sizeBody
                                        font.family: Typography.fontFamily
                                        elide: Text.ElideRight
                                    }
                                    
                                    Text {
                                        width: parent.width
                                        text: modelData.connected ? "Connected" : "Not connected"
                                        color: modelData.connected ? Colors.accent : Colors.textSecondary
                                        font.pixelSize: Typography.sizeSmall
                                        font.family: Typography.fontFamily
                                    }
                                }
                                
                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.right: parent.right
                                    name: "chevron-right"
                                    size: Constants.iconSizeSmall
                                    color: Colors.textSecondary
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
            
            Section {
                title: "Available Devices"
                width: parent.width - Constants.spacingLarge * 2
                visible: BluetoothManagerCpp.enabled
                
                Column {
                    width: parent.width
                    spacing: Constants.spacingMedium
                    
                    MButton {
                        width: parent.width
                        text: BluetoothManagerCpp.scanning ? "Stop Scanning" : "Scan for Devices"
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
                                    anchors.leftMargin: Constants.spacingMedium
                                    anchors.rightMargin: Constants.spacingMedium
                                    spacing: Constants.spacingMedium
                                    
                                    Icon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: modelData.icon || "bluetooth"
                                        size: Constants.iconSizeMedium
                                        color: Colors.textSecondary
                                    }
                                    
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - Constants.iconSizeMedium - Constants.spacingMedium * 2
                                        
                                        Text {
                                            width: parent.width
                                            text: modelData.alias || modelData.name || modelData.address
                                            color: Colors.text
                                            font.pixelSize: Typography.sizeBody
                                            font.family: Typography.fontFamily
                                            elide: Text.ElideRight
                                        }
                                        
                                        Text {
                                            width: parent.width
                                            text: modelData.rssi ? "Signal: " + modelData.rssi + " dBm" : "Available"
                                            color: Colors.textSecondary
                                            font.pixelSize: Typography.sizeSmall
                                            font.family: Typography.fontFamily
                                        }
                                    }
                                }
                                
                                MouseArea {
                                    id: availableDeviceMouseArea
                                    anchors.fill: parent
                                    onClicked: {
                                        Logger.info("BluetoothPage", "Pairing with device: " + modelData.address)
                                        BluetoothManagerCpp.pairDevice(modelData.address)
                                    }
                                }
                            }
                        }
                    }
                    
                    Text {
                        width: parent.width
                        text: BluetoothManagerCpp.scanning ? "Scanning for devices..." : "No devices found"
                        color: Colors.textSecondary
                        font.pixelSize: Typography.sizeBody
                        font.family: Typography.fontFamily
                        horizontalAlignment: Text.AlignHCenter
                        topPadding: Constants.spacingLarge
                        bottomPadding: Constants.spacingLarge
                        visible: BluetoothManagerCpp.devices.length === 0
                    }
                }
            }
            
            Item { height: Constants.navBarHeight }
        }
    }
    
    Connections {
        target: BluetoothManagerCpp
        function onPairingSucceeded(address) {
            Logger.info("BluetoothPage", "Successfully paired with: " + address)
        }
        function onPairingFailed(address, error) {
            Logger.error("BluetoothPage", "Failed to pair with " + address + ": " + error)
        }
    }
}
