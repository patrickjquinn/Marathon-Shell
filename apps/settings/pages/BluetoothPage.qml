import MarathonApp.Settings
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

SettingsPageTemplate {
    id: bluetoothPage

    property string pageName: "bluetooth"
    property BluetoothPairDialog activePairDialog: null
    property var pendingPairRequest: null

    pageTitle: "Bluetooth"
    Component.onCompleted: {
        Logger.info("BluetoothPage", "Initialized");
        if (BluetoothManagerCpp.enabled)
            BluetoothManagerCpp.startScan();
    }

    Loader {
        id: bluetoothPairDialogLoader

        function show(name, address, type, mode) {
            active = true;
            bluetoothPage.pendingPairRequest = {
                "name": name,
                "address": address,
                "type": type,
                "mode": mode
            };
            if (bluetoothPage.activePairDialog) {
                bluetoothPage.activePairDialog.show(name, address, type, mode);
                bluetoothPage.pendingPairRequest = null;
            }
        }

        anchors.fill: parent
        active: false
        z: 1000
        onLoaded: {
            bluetoothPage.activePairDialog = item;
            if (bluetoothPage.pendingPairRequest) {
                var request = bluetoothPage.pendingPairRequest;
                bluetoothPage.pendingPairRequest = null;
                bluetoothPage.activePairDialog.show(request.name, request.address, request.type, request.mode);
            }
        }
        onActiveChanged: {
            if (!active)
                bluetoothPage.activePairDialog = null;
        }

        sourceComponent: Component {
            BluetoothPairDialog {
                id: pairDialog

                anchors.fill: parent
                onPairRequested: pin => {
                    Logger.info("BluetoothPage", "Pairing requested with PIN: " + (pin ? "****" : "none"));
                    BluetoothManagerCpp.pairDevice(deviceAddress, pin);
                }
                onPairConfirmed: accepted => {
                    Logger.info("BluetoothPage", "Pairing confirmation: " + accepted);
                    if (accepted) {
                        BluetoothManagerCpp.confirmPairing(deviceAddress, true);
                    } else {
                        BluetoothManagerCpp.confirmPairing(deviceAddress, false);
                        bluetoothPairDialogLoader.item.hide();
                    }
                }
                onCancelled: {
                    Logger.info("BluetoothPage", "Pairing cancelled");
                    BluetoothManagerCpp.cancelPairing(deviceAddress);
                }
            }
        }
    }

    Connections {
        function onEnabledChanged() {
            if (BluetoothManagerCpp.enabled)
                BluetoothManagerCpp.startScan();
            else
                BluetoothManagerCpp.stopScan();
        }

        function onPairingSucceeded(address) {
            Logger.info("BluetoothPage", "✓ Successfully paired with: " + address);
            if (bluetoothPage.activePairDialog)
                bluetoothPage.activePairDialog.hide();

            HapticService.medium();
        }

        function onPairingFailed(address, error) {
            Logger.error("BluetoothPage", "✗ Failed to pair with " + address + ": " + error);
            if (bluetoothPage.activePairDialog)
                bluetoothPage.activePairDialog.showError(error || "Pairing failed. Try again.");
        }

        function onPinRequested(address, deviceName) {
            Logger.info("BluetoothPage", "PIN requested for device: " + deviceName);
            if (bluetoothPage.activePairDialog)
                bluetoothPage.activePairDialog.show(deviceName, address, "device", "pin");
        }

        function onPasskeyRequested(address, deviceName) {
            Logger.info("BluetoothPage", "Passkey requested for device: " + deviceName);
            if (bluetoothPage.activePairDialog)
                bluetoothPage.activePairDialog.show(deviceName, address, "device", "passkey");
        }

        function onPasskeyConfirmation(address, deviceName, passkey) {
            Logger.info("BluetoothPage", "Passkey confirmation requested: " + passkey);
            if (bluetoothPage.activePairDialog)
                bluetoothPage.activePairDialog.showPasskeyConfirmation(deviceName, address, "device", passkey);
        }

        target: BluetoothManagerCpp
    }

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
                        BluetoothManagerCpp.enabled = !BluetoothManagerCpp.enabled;
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
                                    ColorAnimation {
                                        duration: Constants.animationDurationFast
                                    }
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
                                    if (modelData.connected)
                                        BluetoothManagerCpp.disconnectDevice(modelData.address);
                                    else
                                        BluetoothManagerCpp.connectDevice(modelData.address);
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
                        text: BluetoothManagerCpp.scanning ? "Stop Scanning" : "Scan for Devices"
                        variant: BluetoothManagerCpp.scanning ? "primary" : "default"
                        onClicked: {
                            if (BluetoothManagerCpp.scanning)
                                BluetoothManagerCpp.stopScan();
                            else
                                BluetoothManagerCpp.startScan();
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
                                        ColorAnimation {
                                            duration: Constants.animationDurationFast
                                        }
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
                                        Logger.info("BluetoothPage", "Selected device for pairing: " + modelData.name);
                                        HapticService.light();
                                        bluetoothPairDialogLoader.show(modelData.name, modelData.address, modelData.type || "device", "justworks");
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

            Item {
                height: Constants.navBarHeight
            }
        }
    }
}
