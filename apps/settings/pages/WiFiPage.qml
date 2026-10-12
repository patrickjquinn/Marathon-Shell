pragma ComponentBehavior: Bound

import MarathonApp.Settings
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Feedback
import MarathonUI.Modals
import MarathonUI.Theme
import QtQuick

SettingsPageTemplate {
    id: wifiPage

    property string pageName: "wifi"
    property bool scanning: false

    function scan() {
        scanning = true;
        scanTimeout.restart();
        NetworkManagerCpp.scanWifi();
    }

    pageTitle: "Wi-Fi"
    overlayOpen: disconnectSheet.showing || SettingsController.wifiDialogVisible
    onCloseOverlayRequested: {
        if (SettingsController.wifiDialogVisible) {
            if (!SettingsController.wifiDialogConnecting)
                SettingsController.dismissWifiDialog();
        } else {
            disconnectSheet.hide();
        }
    }
    Component.onCompleted: {
        Logger.info("WiFiPage", "Initialized");
        if (NetworkManagerCpp.wifiEnabled)
            scan();
    }

    Timer {
        id: scanTimeout

        interval: 15000
        onTriggered: wifiPage.scanning = false
    }

    Connections {
        target: NetworkManagerCpp

        function onAvailableNetworksChanged() {
            wifiPage.scanning = false;
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
                text: "Are you sure you want to disconnect from " + (NetworkManagerCpp.wifiSsid || "this network") + "?"
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
                        disconnectSheet.hide();
                    }
                }

                MButton {
                    text: "Disconnect"
                    variant: "danger"
                    width: 140
                    onClicked: {
                        NetworkManagerCpp.disconnectWifi();
                        disconnectSheet.hide();
                    }
                }
            }
        }
    }

    SettingsWiFiDialog {
        id: passwordDialog
        anchors.fill: parent
    }

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

            MSettingsListItem {
                width: parent.width - 48
                title: "Wi-Fi"
                subtitle: NetworkManagerCpp.wifiEnabled ? "Enabled" : "Disabled"
                iconName: "wifi"
                showToggle: true
                toggleValue: NetworkManagerCpp.wifiEnabled
                onToggleChanged: {
                    NetworkManagerCpp.toggleWifi();

                    if (NetworkManagerCpp.wifiEnabled)
                        Qt.callLater(wifiPage.scan);
                }
            }

            MSection {
                title: "Current Network"
                width: parent.width - 48
                visible: NetworkManagerCpp.wifiConnected && NetworkManagerCpp.wifiEnabled

                Rectangle {
                    width: parent.width
                    height: Constants.hubHeaderHeight
                    radius: MRadius.sm
                    color: MColors.marathonTealGlowMid
                    border.width: 1
                    border.color: MColors.tealBorder
                    Accessible.role: Accessible.Button
                    Accessible.name: "Connected to " + (NetworkManagerCpp.wifiSsid || "Wi-Fi") + ". Tap to disconnect"
                    Accessible.onPressAction: disconnectSheet.show()

                    Row {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: MSpacing.md

                        Icon {
                            name: SettingsController.wifiSignalIcon(NetworkManagerCpp.wifiSignalStrength)
                            size: 28
                            color: MColors.marathonTeal
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            width: parent.width - 100

                            Text {
                                text: NetworkManagerCpp.wifiSsid || "Connected"
                                color: MColors.textPrimary
                                font.pixelSize: MTypography.sizeBody
                                font.weight: Font.DemiBold
                                font.family: MTypography.fontFamily
                                elide: Text.ElideRight
                                width: parent.width
                            }

                            Text {
                                text: SettingsController.wifiConnectionStatusText(NetworkManagerCpp.wifiSignalStrength)
                                color: MColors.textSecondary
                                font.pixelSize: MTypography.sizeSmall
                                font.family: MTypography.fontFamily
                            }
                        }

                        Item {
                            width: 1
                            height: 1
                        }

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
                            HapticService.light();
                            disconnectSheet.show();
                        }
                    }
                }
            }

            MSection {
                title: NetworkManagerCpp.wifiEnabled ? "Available Networks" : "Turn on WiFi to see networks"
                width: parent.width - 48
                visible: NetworkManagerCpp.wifiEnabled

                Row {
                    width: parent.width
                    height: MSpacing.touchTargetMin
                    leftPadding: MSpacing.md
                    spacing: MSpacing.md
                    visible: wifiPage.scanning && NetworkManagerCpp.availableNetworks.length === 0

                    MActivityIndicator {
                        running: parent.visible
                        size: 24
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

                Column {
                    width: parent.width
                    spacing: MSpacing.sm
                    visible: NetworkManagerCpp.availableNetworks.length > 0

                    Repeater {
                        model: NetworkManagerCpp.availableNetworks

                        MSettingsListItem {
                            required property var modelData
                            width: parent.width
                            title: modelData.ssid
                            subtitle: SettingsController.availableNetworkSubtitle(modelData.security || "", modelData.strength, modelData.frequency)
                            iconName: SettingsController.wifiSignalIcon(modelData.strength)
                            showChevron: true
                            onSettingClicked: {
                                HapticService.light();
                                if (NetworkManagerCpp.wifiConnected && modelData.ssid === NetworkManagerCpp.wifiSsid) {
                                    Logger.info("WiFiPage", "Show disconnect dialog for: " + modelData.ssid);
                                    disconnectSheet.show();
                                } else {
                                    Logger.info("WiFiPage", "Connect to: " + modelData.ssid);
                                    SettingsController.showWifiDialog(modelData.ssid, modelData.strength, modelData.security || "Open", modelData.secured);
                                }
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: "No networks found. Move closer to a router or scan again."
                    color: MColors.textSecondary
                    font.pixelSize: MTypography.sizeBody
                    font.family: MTypography.fontFamily
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    topPadding: MSpacing.lg
                    bottomPadding: MSpacing.lg
                    visible: !wifiPage.scanning && NetworkManagerCpp.availableNetworks.length === 0
                }

                MButton {
                    width: parent.width
                    visible: !wifiPage.scanning
                    text: "Scan for networks"
                    iconName: "rotate-cw"
                    variant: "primary"
                    onClicked: {
                        HapticService.medium();
                        wifiPage.scan();
                    }
                }
            }

            Item {
                height: Constants.navBarHeight
            }
        }
    }
}
