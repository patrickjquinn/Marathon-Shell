import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import "../components"

SettingsPageTemplate {
    id: bluetoothPage
    pageTitle: "Bluetooth"
    
    property string pageName: "bluetooth"
    
    content: Flickable {
        contentHeight: bluetoothContent.height + 40
        clip: true
        boundsBehavior: Flickable.DragAndOvershootBounds
        
        Column {
            id: bluetoothContent
            width: parent.width
            spacing: Constants.spacingXLarge
            leftPadding: 24
            rightPadding: 24
            topPadding: 24
            
            // Bluetooth toggle
            Rectangle {
                width: parent.width - 48
                height: Constants.appIconSize
                radius: 4
                color: Qt.rgba(255, 255, 255, 0.04)
                border.width: 1
                border.color: Qt.rgba(255, 255, 255, 0.08)
                
                Icon {
                    id: bluetoothIcon
                    anchors.left: parent.left
                    anchors.leftMargin: Constants.spacingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    name: "bluetooth"
                    size: Constants.iconSizeMedium
                    color: Colors.text
                }
                
                Column {
                    anchors.left: bluetoothIcon.right
                    anchors.leftMargin: Constants.spacingMedium
                    anchors.right: bluetoothToggle.left
                    anchors.rightMargin: Constants.spacingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    
                    Text {
                        text: "Bluetooth"
                        color: Colors.text
                        font.pixelSize: Typography.sizeBody
                        font.weight: Font.DemiBold
                        font.family: Typography.fontFamily
                    }
                    
                    Text {
                        text: SystemControlStore.isBluetoothOn ? "Enabled" : "Disabled"
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
                    checked: SystemControlStore.isBluetoothOn
                    onToggled: {
                        SystemControlStore.toggleBluetooth()
                    }
                }
            }
            
            // Paired devices
            Section {
                title: "Paired Devices"
                width: parent.width - 48
                visible: SystemControlStore.isBluetoothOn
                
                Column {
                    width: parent.width
                    spacing: Constants.spacingSmall
                    
                    // Placeholder for paired devices
                    Text {
                        width: parent.width
                        text: "No paired devices"
                        color: Colors.textSecondary
                        font.pixelSize: Typography.sizeBody
                        font.family: Typography.fontFamily
                        horizontalAlignment: Text.AlignHCenter
                        topPadding: 24
                        bottomPadding: 24
                    }
                }
            }
            
            // Available devices
            Section {
                title: "Available Devices"
                width: parent.width - 48
                visible: SystemControlStore.isBluetoothOn
                
                Text {
                    width: parent.width
                    text: "Bluetooth device scanning will be implemented with BlueZ D-Bus integration"
                    color: Colors.textSecondary
                    font.pixelSize: Typography.sizeSmall
                    font.family: Typography.fontFamily
                    wrapMode: Text.WordWrap
                    topPadding: 12
                }
            }
            
            Item { height: Constants.navBarHeight }
        }
    }
    
    Component.onCompleted: {
        Logger.info("BluetoothPage", "Initialized")
    }
}

