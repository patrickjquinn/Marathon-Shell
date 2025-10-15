import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Containers
import MarathonUI.Lists
import MarathonUI.Controls

MPage {
    id: wifiPage
    
    title: "WiFi"
    showBackButton: true
    
    property string pageName: "wifi"
    
    signal navigateBack()
    
    onBackClicked: navigateBack()
    
    content: Column {
        width: parent.width
        spacing: MSpacing.xl
        topPadding: MSpacing.lg
        bottomPadding: MSpacing.lg
        
        MSection {
            title: ""
            width: parent.width - MSpacing.lg * 2
            anchors.horizontalCenter: parent.horizontalCenter
            
            Rectangle {
                width: parent.width
                height: Constants.appIconSize
                color: "transparent"
                
                Row {
                    anchors.fill: parent
                    anchors.margins: MSpacing.lg
                    spacing: MSpacing.md
                    
                    Icon {
                        name: "wifi"
                        size: Constants.iconSizeMedium
                        color: MColors.text
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: MSpacing.xs
                        width: parent.width - 140
                        
                        Text {
                            text: "WiFi"
                            color: MColors.text
                            font.pixelSize: MTypography.sizeBody
                            font.weight: MTypography.weightDemiBold
                            font.family: MTypography.fontFamily
                        }
                        
                        Text {
                            text: SystemControlStore.isWifiOn ? "Enabled" : "Disabled"
                            color: MColors.textSecondary
                            font.pixelSize: MTypography.sizeSmall
                            font.family: MTypography.fontFamily
                        }
                    }
                    
                    Item { Layout.fillWidth: true; height: 1 }
                    
                    MToggle {
                        checked: SystemControlStore.isWifiOn
                        anchors.verticalCenter: parent.verticalCenter
                        onToggled: {
                            SystemControlStore.toggleWifi()
                            if (SystemControlStore.isWifiOn) {
                                Qt.callLater(() => NetworkManager.scanWifi())
                            }
                        }
                    }
                }
            }
        }
        
        MSection {
            title: "Current Network"
            width: parent.width - MSpacing.lg * 2
            anchors.horizontalCenter: parent.horizontalCenter
            visible: SystemStatusStore.wifiConnected && SystemControlStore.isWifiOn
            
            Rectangle {
                width: parent.width
                height: Constants.hubHeaderHeight
                radius: MRadius.md
                color: Qt.rgba(0, 102/255, 102/255, 0.08)
                border.width: 1
                border.color: Qt.rgba(0, 102/255, 102/255, 0.3)
                
                Row {
                    anchors.fill: parent
                    anchors.margins: MSpacing.lg
                    spacing: MSpacing.md
                    
                    Icon {
                        name: "wifi"
                        size: 28
                        color: MColors.accent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: MSpacing.xs
                        width: parent.width - 120
                        
                        Text {
                            text: SystemStatusStore.wifiNetwork || "Connected"
                            color: MColors.text
                            font.pixelSize: MTypography.sizeBody
                            font.weight: MTypography.weightDemiBold
                            font.family: MTypography.fontFamily
                            elide: Text.ElideRight
                            width: parent.width
                        }
                        
                        Text {
                            text: "Connected • " + (SystemStatusStore.wifiSignalStrength || "Good signal")
                            color: MColors.textSecondary
                            font.pixelSize: MTypography.sizeSmall
                            font.family: MTypography.fontFamily
                        }
                    }
                    
                    Item { width: 1; height: 1 }
                    
                    Icon {
                        name: "chevron-right"
                        size: Constants.iconSizeSmall
                        color: MColors.textSecondary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        Logger.info("WiFiPage", "Show details for: " + SystemStatusStore.wifiNetwork)
                    }
                }
            }
        }
        
        MSection {
            title: SystemControlStore.isWifiOn ? "Available Networks" : "Turn on WiFi to see networks"
            width: parent.width - MSpacing.lg * 2
            anchors.horizontalCenter: parent.horizontalCenter
            visible: SystemControlStore.isWifiOn
            
            Column {
                width: parent.width
                spacing: MSpacing.sm
                
                Row {
                    width: parent.width
                    height: 48
                    spacing: MSpacing.md
                    visible: NetworkManager.isScanning
                    
                    BusyIndicator {
                        running: parent.visible
                        width: 32
                        height: 32
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    
                    Text {
                        text: "Scanning for networks..."
                        color: MColors.textSecondary
                        font.pixelSize: MTypography.sizeBody
                        font.family: MTypography.fontFamily
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                
                Repeater {
                    model: NetworkManager.availableNetworks
                    visible: !NetworkManager.isScanning && NetworkManager.availableNetworks.length > 0
                    
                    MListItem {
                        title: modelData.ssid
                        subtitle: (modelData.security || "Open") + " • " + (modelData.frequency ? (modelData.frequency + " GHz") : "")
                        leftIconName: "wifi"
                        rightIconName: modelData.secure ? "lock" : "globe"
                        showDivider: index < NetworkManager.availableNetworks.length - 1
                        
                        onClicked: {
                            HapticService.light()
                            Logger.info("WiFiPage", "Connect to: " + modelData.ssid)
                            NetworkManager.connectToWifi(modelData.ssid)
                        }
                    }
                }
                
                Text {
                    width: parent.width
                    text: "No networks found"
                    color: MColors.textSecondary
                    font.pixelSize: MTypography.sizeBody
                    font.family: MTypography.fontFamily
                    horizontalAlignment: Text.AlignHCenter
                    topPadding: MSpacing.xl
                    bottomPadding: MSpacing.xl
                    visible: !NetworkManager.isScanning && NetworkManager.availableNetworks.length === 0
                }
                
                Rectangle {
                    width: parent.width
                    height: 48
                    radius: MRadius.md
                    color: Qt.rgba(0, 102/255, 102/255, 0.12)
                    border.width: 1
                    border.color: Qt.rgba(0, 102/255, 102/255, 0.3)
                    visible: !NetworkManager.isScanning
                    
                    Row {
                        anchors.centerIn: parent
                        spacing: MSpacing.sm
                        
                        Icon {
                            name: "rotate-cw"
                            size: Constants.iconSizeSmall
                            color: MColors.accent
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        
                        Text {
                            text: "Scan for networks"
                            color: MColors.accent
                            font.pixelSize: MTypography.sizeBody
                            font.weight: MTypography.weightMedium
                            font.family: MTypography.fontFamily
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
        }
    }
    
    Component.onCompleted: {
        Logger.info("WiFiPage", "Initialized")
        if (SystemControlStore.isWifiOn) {
            NetworkManager.scanWifi()
        }
    }
}

