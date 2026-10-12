import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

Item {
    id: bluetoothPairDialog

    property string deviceName: ""
    property string deviceAddress: ""
    property string deviceType: ""
    property string pairingMode: ""
    property string displayedPasskey: ""
    property bool isPairing: false
    property string errorMessage: ""

    signal pairRequested(string pin)
    signal pairConfirmed(bool accepted)
    signal cancelled

    function show(name, address, type, mode) {
        deviceName = name;
        deviceAddress = address;
        deviceType = type || "device";
        pairingMode = mode || "justworks";
        isPairing = false;
        errorMessage = "";
        pinInput.text = "";
        passkeyInput.text = "";
        if (pairingMode === "pin" || pairingMode === "passkey") {
            if (pairingMode === "pin")
                pinInput.forceActiveFocus();
            else
                passkeyInput.forceActiveFocus();
        }
        bluetoothPairDialog.visible = true;
        showAnimation.start();
        HapticManager.light();
        Logger.info("BluetoothPairDialog", "Showing pairing dialog for: " + name);
    }

    function showPasskeyConfirmation(name, address, type, passkey) {
        deviceName = name;
        deviceAddress = address;
        deviceType = type || "device";
        pairingMode = "confirm";
        displayedPasskey = passkey;
        isPairing = false;
        errorMessage = "";
        bluetoothPairDialog.visible = true;
        showAnimation.start();
        HapticManager.light();
        Logger.info("BluetoothPairDialog", "Showing passkey confirmation: " + passkey);
    }

    function hide() {
        hideAnimation.start();
    }

    function showError(message) {
        errorMessage = message;
        isPairing = false;
        HapticManager.medium();
    }

    function showPairing() {
        isPairing = true;
        errorMessage = "";
    }

    function getDeviceIcon(type) {
        switch (type.toLowerCase()) {
        case "headphones":
        case "headset":
            return "headphones";
        case "keyboard":
            return "keyboard";
        case "mouse":
            return "mouse";
        case "phone":
        case "smartphone":
            return "smartphone";
        case "computer":
        case "laptop":
            return "monitor";
        case "speaker":
            return "volume-2";
        default:
            return "bluetooth";
        }
    }

    function getPairingModeText(mode) {
        switch (mode) {
        case "pin":
            return "Enter PIN to pair";
        case "passkey":
            return "Enter passkey displayed on device";
        case "confirm":
            return "Confirm pairing code";
        case "justworks":
        default:
            return "Ready to pair";
        }
    }

    function getHelpText(mode) {
        switch (mode) {
        case "pin":
            return "Enter the PIN shown on your device (usually 0000 or 1234)";
        case "passkey":
            return "Type the 6-digit passkey displayed on the device";
        case "confirm":
            return "Make sure the code above matches what's shown on your device";
        case "justworks":
        default:
            return "No PIN required for this device";
        }
    }

    function canPair() {
        if (pairingMode === "confirm" || pairingMode === "justworks")
            return true;

        if (pairingMode === "pin")
            return pinInput.text.length >= 4;

        if (pairingMode === "passkey")
            return passkeyInput.text.length === 6;

        return false;
    }

    anchors.fill: parent
    visible: false
    z: Constants.zIndexModalOverlay + 10
    Keys.onEscapePressed: {
        if (!isPairing)
            bluetoothPairDialog.hide();
    }

    // A full-screen Silica dialog on the ambience: Cancel/Reject and
    // Pair/Accept in the header corners, the device, then its code.
    Item {
        id: overlay

        anchors.fill: parent
        opacity: 0

        KeelAmbienceBackground {
            anchors.fill: parent
            wallpaper: AmbienceService.wallpaperUrl
            light: AmbienceService.light
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (!bluetoothPairDialog.isPairing)
                    bluetoothPairDialog.hide();
            }
        }

        Item {
            id: header

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: Constants.statusBarHeight
            height: Silica.Theme.itemSizeLarge
            visible: !bluetoothPairDialog.isPairing

            Silica.BackgroundItem {
                anchors.left: parent.left
                width: parent.width / 2
                height: parent.height
                onClicked: {
                    Logger.info("BluetoothPairDialog", "Pairing cancelled/rejected");
                    HapticManager.light();
                    if (bluetoothPairDialog.pairingMode === "confirm")
                        bluetoothPairDialog.pairConfirmed(false);
                    else
                        bluetoothPairDialog.cancelled();
                    bluetoothPairDialog.hide();
                }

                Silica.Label {
                    anchors.left: parent.left
                    anchors.leftMargin: Silica.Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    text: bluetoothPairDialog.pairingMode === "confirm" ? "Reject" : "Cancel"
                    font.pixelSize: Silica.Theme.fontSizeLarge
                    color: parent.highlighted ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                }
            }

            Silica.BackgroundItem {
                id: pairButton

                function activate() {
                    Logger.info("BluetoothPairDialog", "Pair/Accept clicked");
                    HapticManager.medium();
                    bluetoothPairDialog.showPairing();
                    if (bluetoothPairDialog.pairingMode === "confirm")
                        bluetoothPairDialog.pairConfirmed(true);
                    else if (bluetoothPairDialog.pairingMode === "pin")
                        bluetoothPairDialog.pairRequested(pinInput.text);
                    else if (bluetoothPairDialog.pairingMode === "passkey")
                        bluetoothPairDialog.pairRequested(passkeyInput.text);
                    else
                        bluetoothPairDialog.pairRequested("");
                }

                anchors.right: parent.right
                width: parent.width / 2
                height: parent.height
                enabled: bluetoothPairDialog.canPair()
                onClicked: activate()

                Silica.Label {
                    anchors.right: parent.right
                    anchors.rightMargin: Silica.Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    text: bluetoothPairDialog.pairingMode === "confirm" ? "Accept" : "Pair"
                    font.pixelSize: Silica.Theme.fontSizeLarge
                    color: Silica.Theme.highlightColor
                    opacity: pairButton.enabled ? 1 : Silica.Theme.opacityLow
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
                name: bluetoothPairDialog.getDeviceIcon(bluetoothPairDialog.deviceType)
                size: Silica.Theme.iconSizeLarge
                color: Silica.Theme.primaryColor
            }

            Silica.Label {
                x: Silica.Theme.horizontalPageMargin
                width: parent.width - 2 * x
                horizontalAlignment: Text.AlignHCenter
                text: bluetoothPairDialog.deviceName
                color: Silica.Theme.highlightColor
                font.pixelSize: Silica.Theme.fontSizeLarge
                truncationMode: Silica.TruncationMode.Fade
            }

            Silica.Label {
                x: Silica.Theme.horizontalPageMargin
                width: parent.width - 2 * x
                horizontalAlignment: Text.AlignHCenter
                text: bluetoothPairDialog.getPairingModeText(bluetoothPairDialog.pairingMode)
                wrapMode: Text.Wrap
                color: Silica.Theme.secondaryHighlightColor
                font.pixelSize: Silica.Theme.fontSizeSmall
            }

            Item {
                width: parent.width
                height: Silica.Theme.paddingLarge
            }

            Silica.TextField {
                id: pinInput

                width: parent.width
                visible: bluetoothPairDialog.pairingMode === "pin"
                label: "PIN"
                placeholderText: "Enter PIN (4-6 digits)"
                inputMethodHints: Qt.ImhDigitsOnly
                maximumLength: 6
                enabled: !bluetoothPairDialog.isPairing
                errorHighlight: bluetoothPairDialog.errorMessage !== ""
                Keys.onReturnPressed: {
                    if (pinInput.text.length >= 4)
                        pairButton.activate();
                }
            }

            Silica.TextField {
                id: passkeyInput

                width: parent.width
                visible: bluetoothPairDialog.pairingMode === "passkey"
                label: "Passkey"
                placeholderText: "Enter 6-digit passkey"
                inputMethodHints: Qt.ImhDigitsOnly
                maximumLength: 6
                enabled: !bluetoothPairDialog.isPairing
                errorHighlight: bluetoothPairDialog.errorMessage !== ""
                Keys.onReturnPressed: {
                    if (passkeyInput.text.length === 6)
                        pairButton.activate();
                }
            }

            Column {
                width: parent.width
                spacing: Silica.Theme.paddingSmall
                visible: bluetoothPairDialog.pairingMode === "confirm"

                Silica.Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: bluetoothPairDialog.displayedPasskey
                    color: Silica.Theme.highlightColor
                    font.family: Silica.Theme.fontFamilyHeading
                    font.pixelSize: Silica.Theme.fontSizeHuge
                    font.weight: Font.Light
                    font.letterSpacing: Silica.Theme.paddingSmall
                }

                Silica.Label {
                    x: Silica.Theme.horizontalPageMargin
                    width: parent.width - 2 * x
                    horizontalAlignment: Text.AlignHCenter
                    text: "Verify this code matches on " + bluetoothPairDialog.deviceName
                    wrapMode: Text.Wrap
                    color: Silica.Theme.secondaryHighlightColor
                    font.pixelSize: Silica.Theme.fontSizeSmall
                }
            }

            Silica.Label {
                x: Silica.Theme.horizontalPageMargin
                width: parent.width - 2 * x
                visible: bluetoothPairDialog.errorMessage !== "" && !bluetoothPairDialog.isPairing
                text: bluetoothPairDialog.errorMessage
                wrapMode: Text.Wrap
                color: Silica.Theme.errorColor
                font.pixelSize: Silica.Theme.fontSizeSmall
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Silica.Theme.paddingMedium
                visible: bluetoothPairDialog.isPairing

                Silica.BusyIndicator {
                    anchors.verticalCenter: parent.verticalCenter
                    size: Silica.BusyIndicatorSize.Small
                    running: bluetoothPairDialog.isPairing
                }

                Silica.Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Pairing with " + bluetoothPairDialog.deviceName + "..."
                    color: Silica.Theme.highlightColor
                }
            }

            Silica.Label {
                x: Silica.Theme.horizontalPageMargin
                width: parent.width - 2 * x
                visible: !bluetoothPairDialog.isPairing
                text: bluetoothPairDialog.getHelpText(bluetoothPairDialog.pairingMode)
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
                bluetoothPairDialog.visible = false;
                pinInput.text = "";
                passkeyInput.text = "";
                errorMessage = "";
                isPairing = false;
            }
        }
    }
}
