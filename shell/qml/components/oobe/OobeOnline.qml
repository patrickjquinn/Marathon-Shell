pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import QtQuick.Layouts
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica
import ".."

Item {
    id: root

    property string pendingSsid: ""
    property bool firstScanDone: Network.availableNetworks.length > 0
    // The scan can predate the connection, so mark the joined network here.
    readonly property var networks: Network.availableNetworks.map(n => Object.assign({}, n, {
                "connected": Network.wifiConnected && n.ssid === Network.wifiSsid
            })).sort((a, b) => b.connected - a.connected)
    readonly property bool compact: Constants.isSquareScreen || Constants.screenHeight < 800
    readonly property bool pageActive: visible && SystemStatusStore.isWifiOn
    readonly property real rowHeight: compact ? Silica.Theme.itemSizeExtraSmall : Silica.Theme.itemSizeSmall

    signal done

    // Return continues, unless something inside the beat (a field) has the keys.
    function continueOnReturn(event) {
        event.accepted = activeFocus;
        if (activeFocus)
            done();
    }

    Keys.onReturnPressed: event => continueOnReturn(event)
    Keys.onEnterPressed: event => continueOnReturn(event)
    onVisibleChanged: {
        if (visible)
            forceActiveFocus();
    }

    function handleBack(): bool {
        return false;
    }

    function rescan() {
        root.firstScanDone = Network.availableNetworks.length > 0;
        Network.scanWifi();
        scanTimeout.restart();
    }

    Component.onCompleted: {
        if (pageActive && !scanTimeout.running)
            rescan();
    }

    onPageActiveChanged: {
        if (pageActive)
            rescan();
    }

    Connections {
        function onConnectionSuccess() {
            root.pendingSsid = "";
            if (passwordDialogLoader.item) {
                passwordDialogLoader.item.hide();
                dialogCleanup.restart();
            }
            HapticManager.medium();
        }

        function onConnectionFailed(message) {
            root.pendingSsid = "";
            if (passwordDialogLoader.item)
                passwordDialogLoader.item.showError(message);
        }

        function onAvailableNetworksChanged() {
            if (Network.availableNetworks.length > 0)
                root.firstScanDone = true;
        }

        target: Network
    }

    // NM scans take several seconds and the device may appear late.
    Timer {
        id: scanTimeout

        interval: 6000
        onTriggered: root.firstScanDone = true
    }

    Timer {
        interval: 8000
        repeat: true
        running: root.pageActive && Network.availableNetworks.length === 0
        onTriggered: Network.scanWifi()
    }

    // Just past the dialog's 250 ms hide animation.
    Timer {
        id: dialogCleanup

        interval: 320
        onTriggered: passwordDialogLoader.active = false
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: Silica.Theme.paddingLarge
        spacing: Silica.Theme.paddingMedium

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Silica.Theme.horizontalPageMargin
            Layout.rightMargin: Silica.Theme.horizontalPageMargin

            Silica.Label {
                Layout.fillWidth: true
                //: Heading of the setup step that connects to Wi-Fi
                text: qsTr("Get online")
                wrapMode: Text.Wrap
                color: Silica.Theme.highlightColor
                font.pixelSize: Silica.Theme.fontSizeLarge
            }

            Silica.IconButton {
                objectName: "oobeRescan"
                visible: SystemStatusStore.isWifiOn
                enabled: root.firstScanDone
                icon.source: "image://theme/icon-m-refresh"
                Accessible.name: qsTr("Rescan networks")
                onClicked: {
                    HapticManager.light();
                    root.rescan();
                }
            }
        }

        Silica.Label {
            Layout.fillWidth: true
            Layout.leftMargin: Silica.Theme.horizontalPageMargin
            Layout.rightMargin: Silica.Theme.horizontalPageMargin
            text: qsTr("So the time, weather and updates look after themselves.")
            wrapMode: Text.Wrap
            color: Silica.Theme.secondaryHighlightColor
            font.pixelSize: Silica.Theme.fontSizeSmall
        }

        Silica.TextSwitch {
            objectName: "oobeWifiSwitch"
            Layout.fillWidth: true
            visible: !SystemStatusStore.isWifiOn
            //: Name of the Wi-Fi on/off switch
            text: qsTr("Wi-Fi")
            checked: SystemStatusStore.isWifiOn
            automaticCheck: false
            onClicked: SystemControlStore.toggleWifi()
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: SystemStatusStore.isWifiOn

            Silica.BusyIndicator {
                anchors.centerIn: parent
                size: Silica.BusyIndicatorSize.Medium
                running: root.visible && !root.firstScanDone
                visible: !root.firstScanDone
            }

            Column {
                x: Silica.Theme.horizontalPageMargin
                width: parent.width - 2 * x
                anchors.verticalCenter: parent.verticalCenter
                spacing: Silica.Theme.paddingMedium
                visible: root.firstScanDone && Network.availableNetworks.length === 0

                Silica.Label {
                    width: parent.width
                    text: qsTr("No networks found")
                    color: Silica.Theme.secondaryHighlightColor
                    font.pixelSize: root.compact ? Silica.Theme.fontSizeLarge : Silica.Theme.fontSizeExtraLarge
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }

                Silica.Label {
                    width: parent.width
                    text: qsTr("Move closer to a router, then scan again.")
                    color: Silica.Theme.secondaryColor
                    font.pixelSize: root.compact ? Silica.Theme.fontSizeSmall : Silica.Theme.fontSizeMedium
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }

                Silica.Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("Scan again")
                    onClicked: {
                        HapticManager.light();
                        root.rescan();
                    }
                }
            }

            Flickable {
                anchors.fill: parent
                contentHeight: networkColumn.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                visible: root.firstScanDone && Network.availableNetworks.length > 0

                Column {
                    id: networkColumn

                    width: parent.width

                    Repeater {
                        model: root.networks

                        Silica.ListItem {
                            id: row

                            required property var modelData

                            readonly property bool connected: modelData.connected
                            readonly property bool isPending: root.pendingSsid === modelData.ssid
                            readonly property bool lit: connected || highlighted

                            objectName: "oobeNetwork-" + modelData.ssid
                            width: parent.width
                            contentHeight: root.rowHeight
                            enabled: !connected && root.pendingSsid === ""
                            onClicked: {
                                HapticManager.light();
                                if (row.modelData.secured) {
                                    root.showPasswordDialog(row.modelData.ssid, row.modelData.strength, row.modelData.security, row.modelData.secured);
                                } else {
                                    root.pendingSsid = row.modelData.ssid;
                                    Network.connectToNetwork(row.modelData.ssid, "");
                                }
                            }

                            GlyphIcon {
                                id: strengthIcon

                                x: Silica.Theme.horizontalPageMargin
                                anchors.verticalCenter: parent.verticalCenter
                                name: {
                                    const s = row.modelData.strength;
                                    if (s >= 75)
                                        return "wifi-high";
                                    if (s >= 50)
                                        return "wifi-medium";
                                    if (s >= 25)
                                        return "wifi-low";
                                    return "wifi-none";
                                }
                                size: Silica.Theme.iconSizeSmall
                                color: row.lit ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                            }

                            Column {
                                anchors.left: strengthIcon.right
                                anchors.leftMargin: Silica.Theme.paddingLarge
                                anchors.right: trail.left
                                anchors.rightMargin: Silica.Theme.paddingMedium
                                anchors.verticalCenter: parent.verticalCenter

                                Silica.Label {
                                    width: parent.width
                                    text: row.modelData.ssid
                                    color: row.lit ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                                    truncationMode: Silica.TruncationMode.Fade
                                }

                                Silica.Label {
                                    objectName: "oobeNetworkStatus"
                                    visible: row.connected || row.isPending
                                    //: Status under a Wi-Fi network while joining it
                                    text: row.isPending ? qsTr("Connecting…") : qsTr("Connected")
                                    color: row.isPending ? Silica.Theme.secondaryColor : Silica.Theme.secondaryHighlightColor
                                    font.pixelSize: Silica.Theme.fontSizeExtraSmall
                                }
                            }

                            Row {
                                id: trail

                                anchors.right: parent.right
                                anchors.rightMargin: Silica.Theme.horizontalPageMargin
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Silica.Theme.paddingSmall

                                Silica.BusyIndicator {
                                    anchors.verticalCenter: parent.verticalCenter
                                    size: Silica.BusyIndicatorSize.ExtraSmall
                                    running: row.isPending
                                    visible: running
                                }

                                GlyphIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: row.modelData.secured && !row.isPending
                                    name: "lock"
                                    size: Silica.Theme.iconSizeExtraSmall
                                    color: Silica.Theme.secondaryColor
                                }
                            }
                        }
                    }
                }
            }
        }

        Silica.ListItem {
            id: joinOther

            objectName: "oobeJoinOther"
            Layout.fillWidth: true
            contentHeight: root.rowHeight
            visible: SystemStatusStore.isWifiOn && root.firstScanDone
            onClicked: {
                HapticManager.light();
                root.showPasswordDialog("", 0, "WPA2", true);
            }

            Silica.Label {
                x: Silica.Theme.horizontalPageMargin
                width: parent.width - 2 * x
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Other network…")
                color: joinOther.highlighted ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                truncationMode: Silica.TruncationMode.Fade
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Silica.Theme.horizontalPageMargin
            Layout.rightMargin: Silica.Theme.horizontalPageMargin
            Layout.bottomMargin: Silica.Theme.paddingMedium
            spacing: Silica.Theme.paddingMedium

            Silica.SecondaryButton {
                objectName: "oobeNotNow"
                Layout.fillWidth: true
                text: qsTr("Not now")
                onClicked: root.done()
            }

            Silica.Button {
                objectName: "oobeContinue"
                Layout.fillWidth: true
                text: qsTr("Continue")
                onClicked: root.done()
            }
        }
    }

    function showPasswordDialog(ssid, strength, security, secured) {
        passwordDialogLoader.pending = {
            "ssid": ssid,
            "strength": strength,
            "security": security,
            "secured": secured
        };
        passwordDialogLoader.active = true;
        passwordDialogLoader.flush();
    }

    Loader {
        id: passwordDialogLoader

        property var pending: null

        function flush() {
            if (item && pending) {
                item.show(pending.ssid, pending.strength, pending.security, pending.secured);
                pending = null;
            }
        }

        anchors.fill: parent
        active: false
        onLoaded: flush()

        sourceComponent: WiFiPasswordDialog {
            onConnectRequested: (ssid, password) => {
                Logger.info("OOBE", "Connecting to WiFi:", ssid);
                Network.connectToNetwork(ssid, password);
            }
            onCancelled: Logger.info("OOBE", "WiFi connection cancelled")
        }
    }
}
