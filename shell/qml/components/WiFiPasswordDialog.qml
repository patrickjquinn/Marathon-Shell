import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

Item {
    id: wifiDialog

    property string networkSsid: ""
    property int signalStrength: 0
    property string securityType: ""
    property bool secured: true
    property bool isConnecting: false
    property string errorMessage: ""
    readonly property bool hiddenMode: networkSsid === ""

    signal connectRequested(string ssid, string password)
    signal cancelled

    function show(ssid, strength, security, isSecured) {
        networkSsid = ssid;
        signalStrength = strength;
        securityType = security || "WPA2";
        secured = isSecured;
        isConnecting = false;
        errorMessage = "";
        passwordInput.text = "";
        ssidInput.text = "";
        if (hiddenMode)
            ssidInput.forceActiveFocus();
        else
            passwordInput.forceActiveFocus();
        wifiDialog.visible = true;
        showAnimation.start();
        HapticManager.light();
        Logger.info("WiFiDialog", "Showing dialog for: " + (ssid === "" ? "(hidden)" : ssid));
    }

    function hide() {
        connectTimeout.stop();
        hideAnimation.start();
    }

    function cancel() {
        if (isConnecting)
            Network.cancelPendingConnection();
        cancelled();
        hide();
    }

    function showError(message) {
        connectTimeout.stop();
        errorMessage = message;
        isConnecting = false;
        HapticManager.medium();
    }

    function showConnecting() {
        isConnecting = true;
        errorMessage = "";
        connectTimeout.restart();
    }

    anchors.fill: parent
    visible: false
    z: Constants.zIndexModalOverlay + 10
    Keys.onEscapePressed: wifiDialog.cancel()

    Timer {
        id: connectTimeout

        objectName: "connectTimeout"
        interval: 30000
        onTriggered: {
            Network.cancelPendingConnection();
            wifiDialog.showError(qsTr("Couldn't connect. Check the password or move closer to the router."));
        }
    }

    // A full-screen Silica dialog on the ambience: Cancel and Connect in the
    // header corners, the network, then its password.
    Item {
        id: overlay

        anchors.fill: parent
        opacity: 0

        KeelAmbienceBackground {
            anchors.fill: parent
            wallpaper: AmbienceService.wallpaperUrl
            light: AmbienceService.light
        }

        // Full-screen dialog: a stray tap must not throw away the password.
        MouseArea {
            anchors.fill: parent
        }

        Item {
            id: header

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: Constants.statusBarHeight
            height: Silica.Theme.itemSizeLarge

            Silica.BackgroundItem {
                objectName: "cancelButton"
                anchors.left: parent.left
                width: parent.width / 2
                height: parent.height
                onClicked: {
                    Logger.info("WiFiDialog", "Cancelled");
                    HapticManager.light();
                    wifiDialog.cancel();
                }

                Silica.Label {
                    anchors.left: parent.left
                    anchors.leftMargin: Silica.Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Cancel")
                    font.pixelSize: Silica.Theme.fontSizeLarge
                    color: parent.highlighted ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                }
            }

            Silica.BackgroundItem {
                id: connectButton

                readonly property bool joinable: !wifiDialog.isConnecting && (!wifiDialog.secured || passwordInput.text.length >= 8) && (!wifiDialog.hiddenMode || ssidInput.text.length > 0)

                function activate() {
                    Logger.info("WiFiDialog", "Connect clicked for: " + wifiDialog.networkSsid);
                    HapticManager.medium();
                    wifiDialog.showConnecting();
                    wifiDialog.connectRequested(wifiDialog.networkSsid, passwordInput.text);
                }

                anchors.right: parent.right
                width: parent.width / 2
                height: parent.height
                enabled: joinable
                onClicked: activate()

                Silica.Label {
                    anchors.right: parent.right
                    anchors.rightMargin: Silica.Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Connect")
                    font.pixelSize: Silica.Theme.fontSizeLarge
                    color: Silica.Theme.highlightColor
                    opacity: connectButton.joinable ? 1 : Silica.Theme.opacityLow
                }
            }
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: header.bottom
            anchors.topMargin: Silica.Theme.paddingLarge
            spacing: Silica.Theme.paddingMedium

            GlyphIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: wifiDialog.secured ? "lock" : "wifi"
                size: Silica.Theme.iconSizeLarge
                color: Silica.Theme.primaryColor
            }

            Silica.Label {
                x: Silica.Theme.horizontalPageMargin
                width: parent.width - 2 * x
                visible: !wifiDialog.hiddenMode
                horizontalAlignment: Text.AlignHCenter
                text: wifiDialog.networkSsid
                color: Silica.Theme.highlightColor
                font.pixelSize: Silica.Theme.fontSizeLarge
                truncationMode: Silica.TruncationMode.Fade
            }

            Silica.Label {
                x: Silica.Theme.horizontalPageMargin
                width: parent.width - 2 * x
                horizontalAlignment: Text.AlignHCenter
                text: {
                    const security = wifiDialog.secured ? wifiDialog.securityType : qsTr("Open");
                    //: %1 is the security type, e.g. WPA2
                    if (wifiDialog.hiddenMode)
                        return qsTr("%1 · Hidden").arg(security);
                    const s = wifiDialog.signalStrength;
                    //: %1 is the security type, %2 the signal quality
                    return qsTr("%1 · %2").arg(security).arg(s >= 75 ? qsTr("Excellent") : s >= 50 ? qsTr("Good") : s >= 25 ? qsTr("Fair") : qsTr("Weak"));
                }
                color: Silica.Theme.secondaryHighlightColor
                font.pixelSize: Silica.Theme.fontSizeSmall
            }

            Item {
                width: parent.width
                height: Silica.Theme.paddingLarge
            }

            Silica.TextField {
                id: ssidInput

                width: parent.width
                visible: wifiDialog.hiddenMode
                label: qsTr("Network name")
                placeholderText: qsTr("Network name")
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                onTextChanged: if (wifiDialog.hiddenMode)
                    wifiDialog.networkSsid = text
                Keys.onReturnPressed: passwordInput.forceActiveFocus()
            }

            Silica.PasswordField {
                id: passwordInput

                objectName: "passwordField"
                width: parent.width
                visible: wifiDialog.secured
                label: qsTr("Password")
                placeholderText: qsTr("Enter password")
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                enabled: !wifiDialog.isConnecting
                errorHighlight: wifiDialog.errorMessage !== ""
                Keys.onReturnPressed: {
                    if (connectButton.joinable)
                        connectButton.activate();
                }
            }

            Silica.Label {
                x: Silica.Theme.horizontalPageMargin
                width: parent.width - 2 * x
                visible: wifiDialog.errorMessage !== "" && !wifiDialog.isConnecting
                text: wifiDialog.errorMessage
                wrapMode: Text.Wrap
                color: Silica.Theme.errorColor
                font.pixelSize: Silica.Theme.fontSizeSmall
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Silica.Theme.paddingMedium
                visible: wifiDialog.isConnecting

                Silica.BusyIndicator {
                    anchors.verticalCenter: parent.verticalCenter
                    size: Silica.BusyIndicatorSize.Small
                    running: wifiDialog.isConnecting
                }

                Silica.Label {
                    anchors.verticalCenter: parent.verticalCenter
                    //: %1 is the Wi-Fi network name
                    text: qsTr("Connecting to %1...").arg(wifiDialog.networkSsid)
                    color: Silica.Theme.highlightColor
                }
            }

            Silica.Label {
                x: Silica.Theme.horizontalPageMargin
                width: parent.width - 2 * x
                visible: !wifiDialog.isConnecting
                text: wifiDialog.secured ? qsTr("Password must be at least 8 characters") : qsTr("This network is not secured")
                wrapMode: Text.Wrap
                color: Silica.Theme.secondaryColor
                font.pixelSize: Silica.Theme.fontSizeExtraSmall
            }
        }
    }

    ParallelAnimation {
        id: showAnimation

        NumberAnimation {
            target: overlay
            property: "opacity"
            from: 0
            to: 1
            duration: MMotion.quick
            easing.type: Easing.OutCubic
        }
    }

    SequentialAnimation {
        id: hideAnimation

        NumberAnimation {
            target: overlay
            property: "opacity"
            to: 0
            duration: MMotion.fast
            easing.type: Easing.InCubic
        }

        ScriptAction {
            script: {
                wifiDialog.visible = false;
                passwordInput.text = "";
                ssidInput.text = "";
                errorMessage = "";
                isConnecting = false;
            }
        }
    }
}
