import MarathonApp.Settings
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Modals
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

SettingsPageTemplate {
    id: wifiPage

    property string pageName: "wifi"
    property WiFiPasswordDialog activePasswordDialog: null
    property var pendingPasswordRequest: null

    pageTitle: "WiFi"
    Component.onCompleted: {
        Logger.info("WiFiPage", "Initialized");
        if (typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp && NetworkManagerCpp.wifiEnabled)
            NetworkManagerCpp.scanWifi();
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
                text: "Are you sure you want to disconnect from " + (((typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp) ? NetworkManagerCpp.wifiSsid : "") || "this network") + "?"
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
                    variant: "primary"
                    width: 140
                    onClicked: {
                        if (typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp)
                            NetworkManagerCpp.disconnectWifi();

                        disconnectSheet.hide();
                    }
                }
            }
        }
    }

    Loader {
        id: wifiPasswordDialogLoader

        function show(ssid, strength, security, secured) {
            active = true;
            wifiPage.pendingPasswordRequest = {
                "ssid": ssid,
                "strength": strength,
                "security": security,
                "secured": secured
            };
            if (wifiPage.activePasswordDialog) {
                wifiPage.activePasswordDialog.show(ssid, strength, security, secured);
                wifiPage.pendingPasswordRequest = null;
            }
        }

        anchors.fill: parent
        active: false
        z: 1000
        onLoaded: {
            wifiPage.activePasswordDialog = item;
            if (wifiPage.pendingPasswordRequest) {
                var request = wifiPage.pendingPasswordRequest;
                wifiPage.pendingPasswordRequest = null;
                wifiPage.activePasswordDialog.show(request.ssid, request.strength, request.security, request.secured);
            }
        }
        onActiveChanged: {
            if (!active)
                wifiPage.activePasswordDialog = null;
        }

        sourceComponent: Component {
            WiFiPasswordDialog {
                id: passwordDialog

                anchors.fill: parent
                onConnectRequested: (ssid, password) => {
                    Logger.info("WiFiPage", "Attempting WiFi connection to:", ssid);
                    if (typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp)
                        NetworkManagerCpp.connectToNetwork(ssid, password);
                }
                onCancelled: {
                    Logger.info("WiFiPage", "WiFi dialog cancelled");
                }
            }
        }
    }

    Connections {
        function onConnectionSuccess() {
            Logger.info("WiFiPage", "WiFi connection successful!");
            if (wifiPage.activePasswordDialog)
                wifiPage.activePasswordDialog.hide();
            wifiPasswordDialogLoader.active = false;
            HapticService.medium();
        }

        function onConnectionFailed(message) {
            Logger.warn("WiFiPage", "WiFi connection failed: " + message);
            if (wifiPage.activePasswordDialog)
                wifiPage.activePasswordDialog.showError(message);
        }

        target: typeof NetworkManagerCpp !== "undefined" ? NetworkManagerCpp : null
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
                title: "WiFi"
                subtitle: (typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp && NetworkManagerCpp.wifiEnabled) ? "Enabled" : "Disabled"
                iconName: "wifi"
                showToggle: true
                toggleValue: (typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp) ? NetworkManagerCpp.wifiEnabled : false
                onToggleChanged: {
                    if (typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp)
                        NetworkManagerCpp.toggleWifi();

                    if (typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp && NetworkManagerCpp.wifiEnabled)
                        Qt.callLater(() => {
                            if (typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp)
                                NetworkManagerCpp.scanWifi();
                        });
                }
            }

            MSection {
                title: "Current Network"
                width: parent.width - 48
                visible: (typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp) ? (NetworkManagerCpp.wifiConnected && NetworkManagerCpp.wifiEnabled) : false

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
                            name: {
                                var strength = (typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp) ? NetworkManagerCpp.wifiSignalStrength : 0;
                                if (strength === 0)
                                    return "wifi-zero";

                                if (strength <= 33)
                                    return "wifi-low";

                                if (strength <= 66)
                                    return "wifi";

                                return "wifi-high";
                            }
                            size: 28
                            color: Qt.rgba(20, 184, 166, 1)
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            width: parent.width - 100

                            Text {
                                text: ((typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp) ? NetworkManagerCpp.wifiSsid : "") || "Connected"
                                color: MColors.textPrimary
                                font.pixelSize: MTypography.sizeBody
                                font.weight: Font.DemiBold
                                font.family: MTypography.fontFamily
                                elide: Text.ElideRight
                                width: parent.width
                            }

                            Text {
                                text: "Connected • " + ((typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp) ? NetworkManagerCpp.wifiSignalStrength : 0) + "% signal"
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
                title: (typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp && NetworkManagerCpp.wifiEnabled) ? "Available Networks" : "Turn on WiFi to see networks"
                width: parent.width - 48
                visible: (typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp) ? NetworkManagerCpp.wifiEnabled : false

                Row {
                    width: parent.width
                    height: 48
                    spacing: MSpacing.md
                    visible: false

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

                Column {
                    width: parent.width
                    spacing: MSpacing.sm
                    visible: (typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp) ? (NetworkManagerCpp.availableNetworks.length > 0) : false

                    Repeater {
                        model: (typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp) ? NetworkManagerCpp.availableNetworks : []

                        MSettingsListItem {
                            width: parent.width
                            title: modelData.ssid
                            subtitle: (modelData.security || "Open") + " • " + modelData.strength + "% signal" + (modelData.frequency ? (" • " + modelData.frequency + " GHz") : "")
                            iconName: {
                                if (modelData.strength === 0)
                                    return "wifi-zero";

                                if (modelData.strength <= 33)
                                    return "wifi-low";

                                if (modelData.strength <= 66)
                                    return "wifi";

                                return "wifi-high";
                            }
                            showChevron: true
                            onSettingClicked: {
                                HapticService.light();
                                if ((typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp) && NetworkManagerCpp.wifiConnected && modelData.ssid === NetworkManagerCpp.wifiSsid) {
                                    Logger.info("WiFiPage", "Show disconnect dialog for: " + modelData.ssid);
                                    disconnectSheet.show();
                                } else {
                                    Logger.info("WiFiPage", "Connect to: " + modelData.ssid);
                                    wifiPasswordDialogLoader.show(modelData.ssid, modelData.strength, modelData.security || "Open", modelData.secured);
                                }
                            }
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
                    topPadding: 24
                    bottomPadding: 24
                    visible: (typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp) ? (NetworkManagerCpp.availableNetworks.length === 0) : true
                }

                MButton {
                    width: parent.width
                    text: "Scan for networks"
                    iconName: "rotate-cw"
                    variant: "primary"
                    visible: true
                    onClicked: {
                        HapticService.medium();
                        if (typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp)
                            NetworkManagerCpp.scanWifi();
                    }
                }
            }

            Item {
                height: Constants.navBarHeight
            }
        }
    }
}
