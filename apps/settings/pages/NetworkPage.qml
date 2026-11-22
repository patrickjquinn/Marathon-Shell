pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0

// One saved Wi-Fi network: joining it, its password, its private address,
// and its IP and DNS settings.
Page {
    id: page

    property string ssid
    property var details: ({})
    // Shown once the owner's PIN has been checked.
    property string password: ""
    readonly property bool connected: !!details.connected
    readonly property bool manualIp: !!details.ipv4Manual
    readonly property bool manualDns: !!details.dnsManual
    // Manual picked, not yet saved: the fields show.
    property bool editIp: false
    property bool editDns: false

    function load() {
        details = Network.networkDetails(ssid);
    }

    // Applies a change; joining again for one, then reads the network back.
    function apply(key, value) {
        const error = Network.setNetworkOption(ssid, key, value);
        if (error !== "")
            Notices.show(qsTr("Couldn't save: %1").arg(error));
        else if (key === "ipv4")
            editIp = false;
        else if (key === "dns")
            editDns = false;
        load();
        if (key !== "autoJoin" && key !== "lowData")
            reload.restart();
    }

    function revealPassword() {
        const dialog = pageStack.push(Qt.resolvedUrl("RemotePinDialog.qml"), {
            title: qsTr("Show password"),
            message: qsTr("Enter your PIN to see the password for %1.").arg(page.ssid),
            acceptText: qsTr("Show")
        });
        dialog.accepted.connect(() => {
            const key = Security.wifiPassword(page.ssid, dialog.pin);
            if (key === "")
                Notices.show(qsTr("Wrong PIN"));
            page.password = key;
        });
    }

    function band(mhz) {
        return mhz >= 5925 ? qsTr("6 GHz") : mhz >= 4900 ? qsTr("5 GHz") : qsTr("2.4 GHz");
    }

    onStatusChanged: if (status === PageStatus.Active)
        load()

    // Joining again takes a moment; read the new addresses once it has.
    Timer {
        id: reload

        interval: 4000
        onTriggered: page.load()
    }
    Connections {
        target: Network

        function onWifiConnectedChanged() {
            page.load();
        }
        function onWifiSsidChanged() {
            page.load();
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem {
                objectName: "forgetItem"
                text: qsTr("Forget network")
                onClicked: {
                    const ssid = page.ssid;
                    Remorse.popupAction(page, qsTr("Forgot %1").arg(ssid), () => {
                        Network.forgetNetwork(ssid);
                        pageStack.pop();
                    });
                }
            }
            MenuItem {
                objectName: "joinItem"
                text: page.connected ? qsTr("Disconnect") : qsTr("Connect")
                onClicked: {
                    if (page.connected)
                        Network.disconnectWifi();
                    else
                        Network.connectToNetwork(page.ssid, "");
                    reload.restart();
                }
            }
        }

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: page.ssid
                description: page.connected ? qsTr("Connected") : qsTr("Saved")
            }

            TextSwitch {
                objectName: "autoJoinSwitch"
                text: qsTr("Auto-join")
                description: qsTr("Join this network when it's in range")
                automaticCheck: false
                checked: page.details.autoJoin !== false
                onClicked: page.apply("autoJoin", checked ? "false" : "true")
            }

            TextSwitch {
                objectName: "lowDataSwitch"
                text: qsTr("Low Data Mode")
                description: qsTr("On this network, system and app updates, Pilot's downloads and background work wait for another network")
                automaticCheck: false
                checked: page.details.lowData === true
                onClicked: page.apply("lowData", checked ? "false" : "true")
            }

            ListItem {
                objectName: "passwordItem"
                visible: !!page.details.secured
                contentHeight: Theme.itemSizeMedium
                onClicked: if (page.password === "")
                    page.revealPassword()

                Column {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter

                    Label {
                        text: qsTr("Password")
                        color: Theme.primaryColor
                    }
                    Label {
                        objectName: "passwordText"
                        width: parent.width
                        text: page.password !== "" ? page.password : qsTr("Tap to show")
                        font.pixelSize: Theme.fontSizeSmall
                        color: page.password !== "" ? Theme.highlightColor : Theme.secondaryColor
                        truncationMode: TruncationMode.Fade
                    }
                }
            }
            Column {
                objectName: "shareCode"
                width: parent.width
                visible: page.password !== ""
                spacing: Theme.paddingMedium

                Image {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width - 2 * Theme.horizontalPageMargin, Theme.itemSizeHuge * 2)
                    height: width
                    source: page.password !== "" ? Network.wifiQr(page.ssid, page.password) : ""
                    sourceSize: Qt.size(width, height)
                    smooth: false
                }
                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                    text: qsTr("Scan with another phone's camera to join %1").arg(page.ssid)
                }
            }

            ComboBox {
                id: privateAddressBox

                function indexOf(choice) {
                    return ({
                            off: 0,
                            fixed: 1,
                            rotating: 2
                        })[choice || "fixed"];
                }

                objectName: "privateAddressBox"
                label: qsTr("Private Wi-Fi address")
                description: currentIndex === 0 ? qsTr("Uses this phone's own address. Networks can track it.") : currentIndex === 1 ? qsTr("A different address for each network, the same every time.") : qsTr("A new address each time you join.")
                currentIndex: indexOf(page.details.privateAddress)
                menu: ContextMenu {
                    MenuItem {
                        text: qsTr("Off")
                        onClicked: page.apply("privateAddress", "off")
                    }
                    MenuItem {
                        text: qsTr("Fixed")
                        onClicked: page.apply("privateAddress", "fixed")
                    }
                    MenuItem {
                        text: qsTr("Rotating")
                        onClicked: page.apply("privateAddress", "rotating")
                    }
                }
            }
            DetailItem {
                objectName: "macAddress"
                visible: page.connected && !!page.details.macAddress
                label: qsTr("Wi-Fi address")
                value: (page.details.macAddress || "").toUpperCase()
            }
            DetailItem {
                visible: page.connected && !!page.details.frequency
                label: qsTr("Band")
                value: page.band(page.details.frequency || 0) + (page.details.bitrate ? " · " + qsTr("%1 Mbit/s").arg(page.details.bitrate) : "")
            }

            SectionHeader {
                text: qsTr("IPv4")
            }
            ComboBox {
                id: ipBox

                objectName: "ipBox"
                label: qsTr("Configure IP")
                currentIndex: page.manualIp || page.editIp ? 1 : 0
                menu: ContextMenu {
                    MenuItem {
                        text: qsTr("Automatic")
                        onClicked: {
                            page.editIp = false;
                            if (page.manualIp)
                                page.apply("ipv4", "auto");
                        }
                    }
                    MenuItem {
                        text: qsTr("Manual")
                        onClicked: page.editIp = true
                    }
                }
            }
            DetailItem {
                objectName: "ipAddress"
                visible: page.connected && !!page.details.ipv4Address
                label: qsTr("IP address")
                value: page.details.ipv4Address || ""
            }
            DetailItem {
                visible: page.connected && !!page.details.subnetMask
                label: qsTr("Subnet mask")
                value: page.details.subnetMask || ""
            }
            DetailItem {
                visible: page.connected && !!page.details.router
                label: qsTr("Router")
                value: page.details.router || ""
            }
            Column {
                id: manualIp

                objectName: "manualIp"
                width: parent.width
                visible: page.manualIp || page.editIp

                TextField {
                    id: addressField

                    objectName: "addressField"

                    width: parent.width
                    label: qsTr("IP address")
                    placeholderText: "192.168.1.20"
                    text: page.details.manualAddress || page.details.ipv4Address || ""
                    inputMethodHints: Qt.ImhPreferNumbers | Qt.ImhNoPredictiveText
                    EnterKey.onClicked: maskField.focus = true
                }
                TextField {
                    id: maskField

                    objectName: "maskField"

                    width: parent.width
                    label: qsTr("Subnet mask")
                    placeholderText: "255.255.255.0"
                    text: page.details.manualMask || page.details.subnetMask || "255.255.255.0"
                    inputMethodHints: Qt.ImhPreferNumbers | Qt.ImhNoPredictiveText
                    EnterKey.onClicked: routerField.focus = true
                }
                TextField {
                    id: routerField

                    width: parent.width
                    label: qsTr("Router")
                    placeholderText: "192.168.1.1"
                    text: page.details.manualRouter || page.details.router || ""
                    inputMethodHints: Qt.ImhPreferNumbers | Qt.ImhNoPredictiveText
                }
                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("Save")
                    enabled: addressField.text.trim() !== "" && maskField.text.trim() !== ""
                    onClicked: page.apply("ipv4", [addressField.text.trim(), maskField.text.trim(), routerField.text.trim()].join("/"))
                }
            }

            SectionHeader {
                text: qsTr("IPv6")
                visible: page.connected && !!page.details.ipv6Addresses
            }
            DetailItem {
                visible: page.connected && !!page.details.ipv6Addresses
                label: qsTr("IP address")
                value: page.details.ipv6Addresses || ""
            }
            DetailItem {
                visible: page.connected && !!page.details.ipv6Router
                label: qsTr("Router")
                value: page.details.ipv6Router || ""
            }

            SectionHeader {
                text: qsTr("DNS")
            }
            ComboBox {
                id: dnsBox

                objectName: "dnsBox"
                label: qsTr("Configure DNS")
                currentIndex: page.manualDns || page.editDns ? 1 : 0
                menu: ContextMenu {
                    MenuItem {
                        text: qsTr("Automatic")
                        onClicked: {
                            page.editDns = false;
                            if (page.manualDns)
                                page.apply("dns", "auto");
                        }
                    }
                    MenuItem {
                        text: qsTr("Manual")
                        onClicked: page.editDns = true
                    }
                }
            }
            DetailItem {
                visible: page.connected && !!page.details.dns
                label: qsTr("Servers")
                value: page.details.dns || ""
            }
            Column {
                id: manualDns

                objectName: "manualDns"
                width: parent.width
                visible: page.manualDns || page.editDns

                TextField {
                    id: dnsField

                    width: parent.width
                    label: qsTr("DNS servers, separated by commas")
                    placeholderText: "1.1.1.1, 9.9.9.9"
                    text: page.details.manualDns || page.details.dns || ""
                    inputMethodHints: Qt.ImhPreferNumbers | Qt.ImhNoPredictiveText
                    EnterKey.onClicked: page.apply("dns", dnsField.text)
                }
                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("Save")
                    enabled: dnsField.text.trim() !== ""
                    onClicked: page.apply("dns", dnsField.text)
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
