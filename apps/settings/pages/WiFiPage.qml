import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Modals
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
            spacing: MSpacing.xl
            leftPadding: 24
            rightPadding: 24
            topPadding: 24
            
            // WiFi toggle
            MSettingsListItem {
                width: parent.width - 48
                title: "WiFi"
                subtitle: NetworkManager.wifiEnabled ? "Enabled" : "Disabled"
                iconName: "wifi"
                showToggle: true
                toggleValue: NetworkManager.wifiEnabled
                onToggleChanged: {
                    NetworkManager.toggleWifi()
                    if (NetworkManager.wifiEnabled) {
                        // Start scanning when WiFi is turned on
                        Qt.callLater(() => {
                            NetworkManager.scanWifi()
                        })
                    }
                }
            }
            
            // Current network (if connected)
            MSection {
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
                        spacing: MSpacing.md
                        
                        Icon {
                            // Use proper signal bar icons based on current connection strength
                            name: {
                                var strength = NetworkManager.wifiSignalStrength
                                if (strength === 0) return "wifi-zero"
                                if (strength <= 33) return "wifi-low"     // 1-2 bars (weak)
                                if (strength <= 66) return "wifi"         // 2-3 bars (good)
                                return "wifi-high"                        // 3-4 bars (excellent)
                            }
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
                                color: MColors.textPrimary
                                font.pixelSize: MTypography.sizeBody
                                font.weight: Font.DemiBold
                                font.family: MTypography.fontFamily
                                elide: Text.ElideRight
                                width: parent.width
                            }
                            
                            Text {
                                text: "Connected • " + NetworkManager.wifiSignalStrength + "% signal"
                                color: MColors.textSecondary
                                font.pixelSize: MTypography.sizeSmall
                                font.family: MTypography.fontFamily
                            }
                        }
                        
                        Item { width: 1; height: 1 } // Spacer
                        
                        Icon {
                            name: "chevron-down"
                            size: Constants.iconSizeSmall
                            color: MColors.textSecondary
                            rotation: -90
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            HapticService.light()
                            disconnectSheet.show()
                        }
                    }
                }
            }
            
            // Available networks
            MSection {
                title: NetworkManager.wifiEnabled ? "Available Networks" : "Turn on WiFi to see networks"
                width: parent.width - 48
                visible: NetworkManager.wifiEnabled
                
                // Scanning indicator
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
                
                // Network list
                Column {
                    width: parent.width
                    spacing: MSpacing.sm
                    visible: !NetworkManager.isScanning && NetworkManager.availableNetworks.length > 0
                    
                        Repeater {
                            model: NetworkManager.availableNetworks
                            
                            MSettingsListItem {
                                width: parent.width
                                title: modelData.ssid
                                subtitle: (modelData.security || "Open") + " • " + modelData.strength + "% signal" + (modelData.frequency ? (" • " + modelData.frequency + " GHz") : "")
                                // Use proper signal bar icons based on strength, not opacity
                                iconName: {
                                    if (modelData.strength === 0) return "wifi-zero"
                                    if (modelData.strength <= 33) return "wifi-low"     // 1-2 bars (weak)
                                    if (modelData.strength <= 66) return "wifi"         // 2-3 bars (good)
                                    return "wifi-high"                                   // 3-4 bars (excellent)
                                }
                                showChevron: true
                                onSettingClicked: {
                                    HapticService.light()
                                    
                                    // If this is the currently connected network, show disconnect dialog
                                    if (NetworkManager.wifiConnected && modelData.ssid === NetworkManager.wifiSsid) {
                                        Logger.info("WiFiPage", "Show disconnect dialog for: " + modelData.ssid)
                                        disconnectSheet.show()
                                    } else {
                                        Logger.info("WiFiPage", "Connect to: " + modelData.ssid)
                                        // Show password dialog (works for both secured and open networks)
                                        wifiPasswordDialogLoader.show(
                                            modelData.ssid,
                                            modelData.strength,
                                            modelData.security || "Open",
                                            modelData.secured
                                        )
                                    }
                                }
                            }
                        }
                }
                
                // No networks found
                Text {
                    width: parent.width
                    text: "No networks found"
                    color: MColors.textSecondary
                    font.pixelSize: MTypography.sizeBody
                    font.family: MTypography.fontFamily
                    horizontalAlignment: Text.AlignHCenter
                    topPadding: 24
                    bottomPadding: 24
                    visible: !NetworkManager.isScanning && NetworkManager.availableNetworks.length === 0
                }
                
                // Rescan button
                MButton {
                    width: parent.width
                    text: "Scan for networks"
                    iconName: "rotate-cw"
                    variant: "primary"
                    visible: !NetworkManager.isScanning
                    onClicked: {
                        HapticService.medium()
                        NetworkManager.scanWifi()
                    }
                }
            }
            
            Item { height: Constants.navBarHeight }
        }
    }
    
    MSheet {
        id: disconnectSheet
        title: "Disconnect WiFi"
        sheetHeight: 0.35
        onClosed: disconnectSheet.hide()
        
        content: Column {
            width: parent.width
            spacing: MSpacing.xl
            
            Text {
                text: "Are you sure you want to disconnect from " + (NetworkManager.wifiSsid || "this network") + "?"
                font.pixelSize: MTypography.sizeBody
                font.family: MTypography.fontFamily
                color: MColors.textSecondary
                wrapMode: Text.WordWrap
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
            }
            
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: MSpacing.md
                
                MButton {
                    text: "Cancel"
                    variant: "secondary"
                    width: 140
                    onClicked: {
                        disconnectSheet.hide()
                    }
                }
                
                MButton {
                    text: "Disconnect"
                    variant: "primary"
                    width: 140
                    onClicked: {
                        NetworkManager.disconnectWifi()
                        disconnectSheet.hide()
                    }
                }
            }
        }
    }

    // WiFi password dialog loader (using shell component)
    Loader {
        id: wifiPasswordDialogLoader
        anchors.fill: parent
        active: false
        z: 1000
        
        sourceComponent: Component {
            WiFiPasswordDialog {
                id: passwordDialog
                anchors.fill: parent
                
                // Use direct signal handlers instead of .connect()
                onConnectRequested: (ssid, password) => {
                    Logger.info("WiFiPage", "Attempting WiFi connection to:", ssid)
                    NetworkManager.connectToWifi(ssid, password)
                }
                
                onCancelled: {
                    Logger.info("WiFiPage", "WiFi dialog cancelled")
                }
            }
        }
        
        function show(ssid, strength, security, secured) {
            active = true
            if (item) {
                item.show(ssid, strength, security, secured)
            }
        }
    }
    
    // Wire NetworkManager signals to password dialog
    Connections {
        target: NetworkManager
        
        function onConnectionSuccess() {
            Logger.info("WiFiPage", "WiFi connection successful!")
            if (wifiPasswordDialogLoader.active && wifiPasswordDialogLoader.item) {
                wifiPasswordDialogLoader.item.hide()
                wifiPasswordDialogLoader.active = false
            }
            HapticService.medium()
        }
        
        function onConnectionFailed(message) {
            Logger.warn("WiFiPage", "WiFi connection failed: " + message)
            if (wifiPasswordDialogLoader.active && wifiPasswordDialogLoader.item) {
                wifiPasswordDialogLoader.item.showError(message)
            }
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

