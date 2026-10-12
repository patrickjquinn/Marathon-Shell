pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import MarathonApp.Settings
import "../SettingsLogic.js" as Logic

Page {
    id: page

    property bool scanning: false
    // The controller keeps the password dialog's state; it is shown again after a failed attempt.
    readonly property bool dialogWanted: SettingsController.wifiDialogVisible && !SettingsController.wifiDialogConnecting
    readonly property var others: Network.availableNetworks.filter(n => !(Network.wifiConnected && n.ssid === Network.wifiSsid))

    function scan() {
        scanning = true;
        scanTimeout.restart();
        Network.scanWifi();
    }

    function select(network) {
        SettingsController.showWifiDialog(network.ssid, network.strength, network.security || "Open", !!network.secured);
    }

    function showDialog() {
        if (!dialogWanted || status !== PageStatus.Active)
            return;
        pageStack.push(Qt.resolvedUrl("WiFiDialog.qml"));
    }

    onDialogWantedChanged: Qt.callLater(showDialog)
    onStatusChanged: Qt.callLater(showDialog)
    Component.onCompleted: {
        if (Network.wifiEnabled)
            scan();
    }

    Timer {
        id: scanTimeout

        interval: 15000
        onTriggered: page.scanning = false
    }

    Connections {
        target: Network

        function onAvailableNetworksChanged() {
            page.scanning = false;
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem {
                objectName: "scanItem"
                text: qsTr("Scan")
                enabled: Network.wifiEnabled && !page.scanning
                onClicked: page.scan()
            }
        }

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("Wi-Fi")
            }
            TextSwitch {
                objectName: "wifiSwitch"
                text: qsTr("Wi-Fi")
                description: Network.wifiEnabled ? qsTr("Connect to wireless networks") : qsTr("Turn on to see networks")
                automaticCheck: false
                checked: Network.wifiEnabled
                onClicked: {
                    Network.toggleWifi();
                    if (Network.wifiEnabled)
                        Qt.callLater(page.scan);
                }
            }

            Row {
                x: Theme.horizontalPageMargin
                height: Theme.itemSizeSmall
                spacing: Theme.paddingMedium
                visible: SettingsController.wifiDialogConnecting

                BusyIndicator {
                    anchors.verticalCenter: parent.verticalCenter
                    size: BusyIndicatorSize.ExtraSmall
                    running: parent.visible
                }
                Label {
                    objectName: "connectingLabel"
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Connecting to %1…").arg(SettingsController.wifiDialogSsid)
                    color: Theme.highlightColor
                }
            }

            SectionHeader {
                text: qsTr("Connected")
                visible: current.visible
            }
            ListItem {
                id: current

                objectName: "currentNetwork"
                visible: Network.wifiEnabled && Network.wifiConnected
                contentHeight: Theme.itemSizeMedium
                Accessible.name: qsTr("Connected to %1").arg(Network.wifiSsid)
                menu: ContextMenu {
                    MenuItem {
                        objectName: "disconnectItem"
                        text: qsTr("Disconnect")
                        onClicked: Network.disconnectWifi()
                    }
                }
                onClicked: openMenu()

                Icon {
                    id: currentIcon

                    x: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    source: Logic.wlanIcon(Network.wifiSignalStrength)
                    color: Theme.highlightColor
                }
                Column {
                    anchors {
                        left: currentIcon.right
                        leftMargin: Theme.paddingLarge
                        right: parent.right
                        rightMargin: Theme.horizontalPageMargin
                        verticalCenter: parent.verticalCenter
                    }

                    Label {
                        width: parent.width
                        text: Network.wifiSsid || qsTr("Connected")
                        color: Theme.highlightColor
                        truncationMode: TruncationMode.Fade
                    }
                    Label {
                        width: parent.width
                        text: SettingsController.wifiConnectionStatusText(Network.wifiSignalStrength)
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.secondaryHighlightColor
                    }
                }
            }

            SectionHeader {
                text: qsTr("Available networks")
                visible: Network.wifiEnabled
            }
            Repeater {
                objectName: "networks"
                model: Network.wifiEnabled ? page.others : []

                ListItem {
                    id: item

                    required property var modelData

                    objectName: "network-" + modelData.ssid
                    contentHeight: Theme.itemSizeMedium
                    Accessible.name: modelData.ssid + ", " + SettingsController.availableNetworkSubtitle(modelData.security || "", modelData.strength, modelData.frequency)
                    onClicked: page.select(modelData)

                    Icon {
                        id: icon

                        x: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        source: Logic.wlanIcon(item.modelData.strength)
                        color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
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
                            text: item.modelData.ssid
                            truncationMode: TruncationMode.Fade
                            color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
                        }
                        Label {
                            width: parent.width
                            text: SettingsController.availableNetworkSubtitle(item.modelData.security || "", item.modelData.strength, item.modelData.frequency)
                            font.pixelSize: Theme.fontSizeExtraSmall
                            truncationMode: TruncationMode.Fade
                            color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                        }
                    }
                }
            }

            Row {
                x: Theme.horizontalPageMargin
                height: Theme.itemSizeSmall
                spacing: Theme.paddingMedium
                visible: Network.wifiEnabled && page.scanning && page.others.length === 0

                BusyIndicator {
                    anchors.verticalCenter: parent.verticalCenter
                    size: BusyIndicatorSize.ExtraSmall
                    running: parent.visible
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Scanning for networks…")
                    color: Theme.secondaryHighlightColor
                }
            }
            InfoLabel {
                objectName: "noNetworks"
                visible: Network.wifiEnabled && !page.scanning && page.others.length === 0
                text: qsTr("No networks found")
                font.pixelSize: Theme.fontSizeLarge
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: Network.wifiEnabled && !page.scanning && page.others.length === 0
                text: qsTr("Move closer to a router, or pull down to scan again.")
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
            }
        }

        VerticalScrollDecorator {}
    }
}
