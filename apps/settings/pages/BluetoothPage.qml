pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import MarathonOS.Settings 1.0
import "../SettingsLogic.js" as Logic

Page {
    id: page

    // The controller keeps the pairing dialog's state, including PIN requests from the device.
    readonly property bool dialogWanted: SettingsController.bluetoothDialogVisible && !SettingsController.bluetoothDialogPairing
    readonly property var available: Bluetooth.devices.filter(d => !d.paired)
    // The paired device being connected or disconnected, until BlueZ reports the new state.
    property string pendingAddress: ""
    property bool pendingConnect: false

    function showDialog() {
        if (dialogWanted && status === PageStatus.Active)
            pageStack.push(Qt.resolvedUrl("BluetoothPairDialog.qml"));
    }

    function toggleConnection(device) {
        pendingAddress = device.address;
        pendingConnect = !device.connected;
        pendingTimeout.restart();
        if (device.connected)
            Bluetooth.disconnectDevice(device.address);
        else
            Bluetooth.connectDevice(device.address);
    }

    // Scans only while the page is in front, like Jolla Settings.
    function updateScan() {
        const wanted = status === PageStatus.Active && Bluetooth.enabled;
        if (wanted && !Bluetooth.scanning)
            Bluetooth.startScan();
        else if (!wanted && Bluetooth.scanning)
            Bluetooth.stopScan();
    }

    onDialogWantedChanged: Qt.callLater(showDialog)
    onStatusChanged: {
        updateScan();
        Qt.callLater(showDialog);
    }
    Component.onDestruction: {
        if (Bluetooth.scanning)
            Bluetooth.stopScan();
    }

    Timer {
        id: pendingTimeout

        interval: 20000
        onTriggered: page.pendingAddress = ""
    }

    Connections {
        target: Bluetooth

        function onEnabledChanged() {
            page.updateScan();
        }
        function onPairedDevicesChanged() {
            const device = Bluetooth.pairedDevices.find(d => d.address === page.pendingAddress);
            if (!device || !!device.connected === page.pendingConnect)
                page.pendingAddress = "";
        }
    }

    component DeviceItem: ListItem {
        id: item

        required property var modelData
        property string subtitle

        contentHeight: Theme.itemSizeMedium
        Accessible.name: Logic.deviceName(modelData) + ", " + subtitle

        Icon {
            id: icon

            x: Theme.horizontalPageMargin
            anchors.verticalCenter: parent.verticalCenter
            source: Logic.deviceIcon(item.modelData.icon || item.modelData.type)
            color: item.highlighted || item.modelData.connected ? Theme.highlightColor : Theme.primaryColor
        }
        Column {
            anchors {
                left: icon.right
                leftMargin: Theme.paddingLarge
                right: parent.right
                rightMargin: Theme.horizontalPageMargin
                verticalCenter: parent.verticalCenter
            }

            Label {
                width: parent.width
                text: Logic.deviceName(item.modelData)
                truncationMode: TruncationMode.Fade
                color: item.highlighted || item.modelData.connected ? Theme.highlightColor : Theme.primaryColor
            }
            Label {
                width: parent.width
                text: item.subtitle
                font.pixelSize: Theme.fontSizeExtraSmall
                color: item.highlighted || item.modelData.connected ? Theme.secondaryHighlightColor : Theme.secondaryColor
            }
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            visible: Bluetooth.enabled

            MenuItem {
                objectName: "scanItem"
                text: Bluetooth.scanning ? qsTr("Stop scanning") : qsTr("Scan for devices")
                onClicked: Bluetooth.scanning ? Bluetooth.stopScan() : Bluetooth.startScan()
            }
        }

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("Bluetooth")
            }
            TextSwitch {
                objectName: "bluetoothSwitch"
                text: qsTr("Bluetooth")
                description: !Bluetooth.enabled ? qsTr("Turn on to pair and connect devices") : Bluetooth.scanning ? qsTr("Scanning…") : qsTr("Visible to paired devices")
                automaticCheck: false
                checked: Bluetooth.enabled
                onClicked: Bluetooth.enabled = !Bluetooth.enabled
            }

            Row {
                x: Theme.horizontalPageMargin
                height: Theme.itemSizeSmall
                spacing: Theme.paddingMedium
                visible: SettingsController.bluetoothDialogPairing

                BusyIndicator {
                    anchors.verticalCenter: parent.verticalCenter
                    size: BusyIndicatorSize.ExtraSmall
                    running: parent.visible
                }
                Label {
                    objectName: "pairingLabel"
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Pairing with %1…").arg(SettingsController.bluetoothDialogName)
                    color: Theme.highlightColor
                }
            }

            SectionHeader {
                text: qsTr("Paired devices")
                visible: Bluetooth.enabled && Bluetooth.pairedDevices.length > 0
            }
            Repeater {
                objectName: "pairedDevices"
                model: Bluetooth.enabled ? Bluetooth.pairedDevices : []

                DeviceItem {
                    id: paired

                    objectName: "paired-" + modelData.address
                    readonly property bool pending: modelData.address === page.pendingAddress

                    enabled: !pending
                    subtitle: pending ? (page.pendingConnect ? qsTr("Connecting…") : qsTr("Disconnecting…")) : modelData.connected ? qsTr("Connected") : qsTr("Not connected")
                    menu: ContextMenu {
                        MenuItem {
                            text: paired.modelData.connected ? qsTr("Disconnect") : qsTr("Connect")
                            onClicked: page.toggleConnection(paired.modelData)
                        }
                        MenuItem {
                            objectName: "removeItem"
                            text: qsTr("Remove")
                            onClicked: {
                                const address = paired.modelData.address;
                                paired.remorseDelete(() => Bluetooth.unpairDevice(address));
                            }
                        }
                    }
                    onClicked: page.toggleConnection(modelData)
                }
            }

            SectionHeader {
                text: qsTr("Other devices")
                visible: Bluetooth.enabled
            }
            Repeater {
                objectName: "availableDevices"
                model: Bluetooth.enabled ? page.available : []

                DeviceItem {
                    objectName: "device-" + modelData.address
                    subtitle: qsTr("Tap to pair")
                    onClicked: SettingsController.showBluetoothDialog(modelData.name || Logic.deviceName(modelData), modelData.address, modelData.type || "device", "justworks")
                }
            }
            InfoLabel {
                objectName: "noDevices"
                visible: Bluetooth.enabled && page.available.length === 0
                text: Bluetooth.scanning ? qsTr("Looking for devices…") : qsTr("No devices found")
                font.pixelSize: Theme.fontSizeLarge
            }
        }

        VerticalScrollDecorator {}
    }
}
