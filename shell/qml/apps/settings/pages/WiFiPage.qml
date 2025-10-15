import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import "../components"

SettingsPageTemplate {
    id: wifiPage
    pageTitle: "WiFi"
    
    property string pageName: "wifi"
    
    content: Flickable {
        contentHeight: wifiContent.height + 40
        clip: true
        boundsBehavior: Flickable.DragAndOvershootBounds
        
        Column {
            id: wifiContent
            width: parent.width
            spacing: Constants.spacingXLarge
            leftPadding: 24
            rightPadding: 24
            topPadding: 24
            
            // WiFi toggle
            Rectangle {
                width: parent.width - 48
                height: Constants.appIconSize
                radius: 4
                color: Qt.rgba(255, 255, 255, 0.04)
                border.width: 1
                border.color: Qt.rgba(255, 255, 255, 0.08)
                
                Row {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: Constants.spacingMedium
                    
                    Icon {
                        name: "wifi"
                        size: Constants.iconSizeMedium
                        color: Colors.text
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        width: parent.width - 120
                        
                        Text {
                            text: "WiFi"
                            color: Colors.text
                            font.pixelSize: Typography.sizeBody
                            font.weight: Font.DemiBold
                            font.family: Typography.fontFamily
                        }
                        
                        Text {
                            text: NetworkManager.wifiEnabled ? "Enabled" : "Disabled"
                            color: Colors.textSecondary
                            font.pixelSize: Typography.sizeSmall
                            font.family: Typography.fontFamily
                        }
                    }
                    
                    Item { width: 1; height: 1 } // Spacer
                    
                    MarathonToggle {
                        checked: NetworkManager.wifiEnabled
                        anchors.verticalCenter: parent.verticalCenter
                        onToggled: {
                            NetworkManager.toggleWifi()
                            if (NetworkManager.wifiEnabled) {
                                // Start scanning when WiFi is turned on
                                Qt.callLater(() => {
                                    NetworkManager.scanWifi()
                                })
                            }
                        }
                    }
                }
            }
            
            // Current network (if connected)
            Section {
                title: "Current Network"
                width: parent.width - 48
                visible: NetworkManager.wifiConnected && NetworkManager.wifiEnabled
                
                Rectangle {
                    width: parent.width
                    height: Constants.hubHeaderHeight
                    radius: 4
                    color: Qt.rgba(20, 184, 166, 0.08)
                    border.width: 1
                    border.color: Qt.rgba(20, 184, 166, 0.3)
                    
                    Row {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: Constants.spacingMedium
                        
                        Icon {
                            name: "wifi"
                            size: 28
                            color: Qt.rgba(20, 184, 166, 1.0)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            width: parent.width - 100
                            
                            Text {
                                text: NetworkManager.wifiSsid || "Connected"
                                color: Colors.text
                                font.pixelSize: Typography.sizeBody
                                font.weight: Font.DemiBold
                                font.family: Typography.fontFamily
                                elide: Text.ElideRight
                                width: parent.width
                            }
                            
                            Text {
                                text: "Connected • " + NetworkManager.wifiSignalStrength + "% signal"
                                color: Colors.textSecondary
                                font.pixelSize: Typography.sizeSmall
                                font.family: Typography.fontFamily
                            }
                        }
                        
                        Item { width: 1; height: 1 } // Spacer
                        
                        Icon {
                            name: "chevron-down"
                            size: Constants.iconSizeSmall
                            color: Colors.textSecondary
                            rotation: -90
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            // TODO: Show network details
                            Logger.info("WiFiPage", "Show details for: " + NetworkManager.wifiSsid)
                        }
                    }
                }
            }
            
            // Available networks
            Section {
                title: NetworkManager.wifiEnabled ? "Available Networks" : "Turn on WiFi to see networks"
                width: parent.width - 48
                visible: NetworkManager.wifiEnabled
                
                // Scanning indicator
                Row {
                    width: parent.width
                    height: 48
                    spacing: Constants.spacingMedium
                    visible: NetworkManager.isScanning
                    
                    BusyIndicator {
                        running: parent.visible
                        width: 32
                        height: 32
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    
                    Text {
                        text: "Scanning for networks..."
                        color: Colors.textSecondary
                        font.pixelSize: Typography.sizeBody
                        font.family: Typography.fontFamily
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                
                // Network list
                Column {
                    width: parent.width
                    spacing: Constants.spacingSmall
                    visible: !NetworkManager.isScanning && NetworkManager.availableNetworks.length > 0
                    
                    Repeater {
                        model: NetworkManager.availableNetworks
                        
                        Rectangle {
                            width: parent.width
                            height: Constants.appIconSize
                            radius: 4
                            color: Qt.rgba(255, 255, 255, 0.04)
                            border.width: 1
                            border.color: Qt.rgba(255, 255, 255, 0.08)
                            
                            Row {
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: Constants.spacingMedium
                                
                                // Signal strength indicator
                                Icon {
                                    name: "wifi"
                                    size: Constants.iconSizeMedium
                                    color: modelData.signal > 60 ? Qt.rgba(20, 184, 166, 1.0) : 
                                           modelData.signal > 30 ? Colors.text : Colors.textSecondary
                                    anchors.verticalCenter: parent.verticalCenter
                                    opacity: modelData.signal > 60 ? 1.0 :
                                             modelData.signal > 30 ? 0.7 : 0.4
                                }
                                
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4
                                    width: parent.width - 100
                                    
                                    Text {
                                        text: modelData.ssid
                                        color: Colors.text
                                        font.pixelSize: Typography.sizeBody
                                        font.weight: Font.Medium
                                        font.family: Typography.fontFamily
                                        elide: Text.ElideRight
                                        width: parent.width
                                    }
                                    
                                    Row {
                                        spacing: Constants.spacingSmall
                                        
                                        Text {
                                            text: modelData.security || "Open"
                                            color: Colors.textSecondary
                                            font.pixelSize: Typography.sizeSmall
                                            font.family: Typography.fontFamily
                                        }
                                        
                                        Text {
                                            text: "•"
                                            color: Colors.textSecondary
                                            font.pixelSize: Typography.sizeSmall
                                            visible: modelData.frequency
                                        }
                                        
                                        Text {
                                            text: modelData.frequency ? (modelData.frequency + " GHz") : ""
                                            color: Colors.textSecondary
                                            font.pixelSize: Typography.sizeSmall
                                            font.family: Typography.fontFamily
                                            visible: modelData.frequency
                                        }
                                    }
                                }
                                
                                Item { width: 1; height: 1 } // Spacer
                                
                                Icon {
                                    name: modelData.secure ? "lock" : "globe"
                                    size: Constants.iconSizeSmall
                                    color: Colors.textSecondary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    HapticService.light()
                                    Logger.info("WiFiPage", "Connect to: " + modelData.ssid)
                                    NetworkManager.connectToWifi(modelData.ssid)
                                }
                            }
                        }
                    }
                }
                
                // No networks found
                Text {
                    width: parent.width
                    text: "No networks found"
                    color: Colors.textSecondary
                    font.pixelSize: Typography.sizeBody
                    font.family: Typography.fontFamily
                    horizontalAlignment: Text.AlignHCenter
                    topPadding: 24
                    bottomPadding: 24
                    visible: !NetworkManager.isScanning && NetworkManager.availableNetworks.length === 0
                }
                
                // Rescan button
                Rectangle {
                    width: parent.width
                    height: 48
                    radius: 4
                    color: Qt.rgba(20, 184, 166, 0.12)
                    border.width: 1
                    border.color: Qt.rgba(20, 184, 166, 0.3)
                    visible: !NetworkManager.isScanning
                    
                    Row {
                        anchors.centerIn: parent
                        spacing: Constants.spacingSmall
                        
                        Icon {
                            name: "rotate-cw"
                            size: Constants.iconSizeSmall
                            color: Qt.rgba(20, 184, 166, 1.0)
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        
                        Text {
                            text: "Scan for networks"
                            color: Qt.rgba(20, 184, 166, 1.0)
                            font.pixelSize: Typography.sizeBody
                            font.weight: Font.Medium
                            font.family: Typography.fontFamily
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            HapticService.medium()
                            NetworkManager.scanWifi()
                        }
                    }
                }
            }
            
            Item { height: Constants.navBarHeight }
        }
    }
    
    Component.onCompleted: {
        Logger.info("WiFiPage", "Initialized")
        // Scan for networks on page load if WiFi is on
        if (NetworkManager.wifiEnabled) {
            NetworkManager.scanWifi()
        }
    }
}

