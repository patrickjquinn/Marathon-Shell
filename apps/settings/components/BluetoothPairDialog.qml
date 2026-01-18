import MarathonApp.Settings
import MarathonApp.Settings
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

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
        HapticService.light();
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
        HapticService.light();
        Logger.info("BluetoothPairDialog", "Showing passkey confirmation: " + passkey);
    }

    function hide() {
        hideAnimation.start();
    }

    function showError(message) {
        errorMessage = message;
        isPairing = false;
        HapticService.medium();
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

    Rectangle {
        id: overlay

        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.6)
        opacity: 0

        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (!isPairing)
                    bluetoothPairDialog.hide();
            }
        }
    }

    Rectangle {
        id: dialogCard

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 0
        width: Math.min(parent.width, Math.round(500 * Constants.scaleFactor))
        height: contentColumn.height + MSpacing.xxl
        radius: Constants.borderRadiusLarge
        color: MColors.surface
        border.width: Constants.borderWidthThin
        border.color: MColors.border
        layer.enabled: true

        Column {
            id: contentColumn

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: MSpacing.lg
            spacing: MSpacing.lg

            Row {
                width: parent.width
                spacing: MSpacing.md

                Rectangle {
                    width: Constants.touchTargetMedium
                    height: Constants.touchTargetMedium
                    radius: Constants.borderRadiusSmall
                    color: Qt.rgba(MColors.marathonTeal.r, MColors.marathonTeal.g, MColors.marathonTeal.b, 0.15)
                    anchors.verticalCenter: parent.verticalCenter

                    Icon {
                        name: getDeviceIcon(bluetoothPairDialog.deviceType)
                        size: Constants.iconSizeMedium
                        color: MColors.marathonTeal
                        anchors.centerIn: parent
                    }
                }

                Column {
                    width: parent.width - Constants.touchTargetMedium - MSpacing.md
                    spacing: MSpacing.xs
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        text: bluetoothPairDialog.deviceName
                        font.pixelSize: MTypography.sizeLarge
                        font.weight: Font.Medium
                        font.family: MTypography.fontFamily
                        color: MColors.textPrimary
                        elide: Text.ElideRight
                        width: parent.width
                    }

                    Text {
                        text: getPairingModeText(bluetoothPairDialog.pairingMode)
                        font.pixelSize: MTypography.sizeSmall
                        font.family: MTypography.fontFamily
                        color: MColors.textSecondary
                        width: parent.width
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: Constants.inputHeight
                radius: Constants.borderRadiusSmall
                color: MColors.background || Qt.darker(MColors.background, 1.05)
                border.width: pinInput.activeFocus || passkeyInput.activeFocus ? Constants.borderWidthMedium : Constants.borderWidthThin
                border.color: errorMessage !== "" ? MColors.error : ((pinInput.activeFocus || passkeyInput.activeFocus) ? MColors.marathonTeal : MColors.border)
                visible: pairingMode === "pin" || pairingMode === "passkey"

                Row {
                    anchors.fill: parent
                    anchors.margins: MSpacing.md
                    spacing: MSpacing.md

                    Icon {
                        name: "key"
                        size: Constants.iconSizeMedium
                        color: (pinInput.activeFocus || passkeyInput.activeFocus) ? MColors.marathonTeal : MColors.textSecondary
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    TextInput {
                        id: pinInput

                        visible: pairingMode === "pin"
                        width: parent.width - Constants.iconSizeMedium - MSpacing.md
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: MTypography.sizeBody
                        font.family: MTypography.fontFamily
                        color: MColors.textPrimary
                        inputMethodHints: Qt.ImhDigitsOnly
                        maximumLength: 6
                        enabled: !isPairing
                        selectByMouse: true
                        Keys.onReturnPressed: {
                            if (pinInput.text.length >= 4)
                                pairButton.clicked();
                        }

                        Text {
                            text: "Enter PIN (4-6 digits)"
                            font: pinInput.font
                            color: MColors.textTertiary
                            visible: pinInput.text.length === 0 && !pinInput.activeFocus
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    TextInput {
                        id: passkeyInput

                        visible: pairingMode === "passkey"
                        width: parent.width - Constants.iconSizeMedium - MSpacing.md
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: MTypography.sizeBody
                        font.family: MTypography.fontFamily
                        color: MColors.textPrimary
                        inputMethodHints: Qt.ImhDigitsOnly
                        maximumLength: 6
                        enabled: !isPairing
                        selectByMouse: true
                        Keys.onReturnPressed: {
                            if (passkeyInput.text.length === 6)
                                pairButton.clicked();
                        }

                        Text {
                            text: "Enter 6-digit passkey"
                            font: passkeyInput.font
                            color: MColors.textTertiary
                            visible: passkeyInput.text.length === 0 && !passkeyInput.activeFocus
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                Behavior on border.color {
                    ColorAnimation {
                        duration: 150
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: Math.round(100 * Constants.scaleFactor)
                radius: Constants.borderRadiusLarge
                color: Qt.rgba(MColors.marathonTeal.r, MColors.marathonTeal.g, MColors.marathonTeal.b, 0.1)
                border.width: Constants.borderWidthMedium
                border.color: MColors.marathonTeal
                visible: pairingMode === "confirm"

                Column {
                    anchors.centerIn: parent
                    spacing: MSpacing.sm

                    Text {
                        text: displayedPasskey
                        font.pixelSize: MTypography.sizeGigantic
                        font.weight: Font.Light
                        font.family: MTypography.fontMonospace || "monospace"
                        font.letterSpacing: 8
                        color: MColors.marathonTeal
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Text {
                        text: "Verify this code matches on " + deviceName
                        font.pixelSize: MTypography.sizeSmall
                        font.family: MTypography.fontFamily
                        color: MColors.textSecondary
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: errorText.height + MSpacing.md
                radius: Constants.borderRadiusSmall
                color: Qt.rgba(MColors.error.r, MColors.error.g, MColors.error.b, 0.15)
                border.width: Constants.borderWidthThin
                border.color: MColors.error
                visible: errorMessage !== "" && !isPairing

                Row {
                    anchors.fill: parent
                    anchors.margins: MSpacing.sm
                    spacing: MSpacing.sm

                    Icon {
                        name: "alert-circle"
                        size: Constants.iconSizeSmall
                        color: MColors.error
                        anchors.top: parent.top
                        anchors.topMargin: Math.round(2 * Constants.scaleFactor)
                    }

                    Text {
                        id: errorText

                        text: errorMessage
                        font.pixelSize: MTypography.sizeSmall
                        font.family: MTypography.fontFamily
                        color: MColors.error
                        wrapMode: Text.WordWrap
                        width: parent.width - Constants.iconSizeSmall - MSpacing.sm
                    }
                }
            }

            Column {
                width: parent.width
                spacing: MSpacing.sm
                visible: isPairing

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: MSpacing.md

                    BusyIndicator {
                        width: Constants.iconSizeMedium
                        height: Constants.iconSizeMedium
                        running: isPairing
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "Pairing with " + deviceName + "..."
                        font.pixelSize: MTypography.sizeBody
                        font.family: MTypography.fontFamily
                        color: MColors.textSecondary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            Row {
                width: parent.width
                height: Constants.touchTargetMedium
                spacing: MSpacing.md
                visible: !isPairing

                Rectangle {
                    width: (parent.width - MSpacing.md) / 2
                    height: parent.height
                    radius: Constants.borderRadiusSmall
                    color: "transparent"
                    border.width: Constants.borderWidthThin
                    border.color: MColors.border

                    Text {
                        text: pairingMode === "confirm" ? "Reject" : "Cancel"
                        font.pixelSize: MTypography.sizeLarge
                        font.family: MTypography.fontFamily
                        color: MColors.textPrimary
                        anchors.centerIn: parent
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            Logger.info("BluetoothPairDialog", "Pairing cancelled/rejected");
                            HapticService.light();
                            bluetoothPairDialog.hide();
                            if (pairingMode === "confirm")
                                bluetoothPairDialog.pairConfirmed(false);
                            else
                                bluetoothPairDialog.cancelled();
                        }
                    }
                }

                Rectangle {
                    id: pairButton

                    signal clicked

                    width: (parent.width - MSpacing.md) / 2
                    height: parent.height
                    radius: Constants.borderRadiusSmall
                    color: canPair() ? MColors.marathonTeal : Qt.darker(MColors.marathonTeal, 1.5)
                    opacity: canPair() ? 1 : 0.5

                    Text {
                        text: pairingMode === "confirm" ? "Accept" : "Pair"
                        font.pixelSize: MTypography.sizeLarge
                        font.weight: Font.Medium
                        font.family: MTypography.fontFamily
                        color: MColors.background
                        anchors.centerIn: parent
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: canPair()
                        onClicked: {
                            Logger.info("BluetoothPairDialog", "Pair/Accept clicked");
                            HapticService.medium();
                            bluetoothPairDialog.showPairing();
                            if (pairingMode === "confirm")
                                bluetoothPairDialog.pairConfirmed(true);
                            else if (pairingMode === "pin")
                                bluetoothPairDialog.pairRequested(pinInput.text);
                            else if (pairingMode === "passkey")
                                bluetoothPairDialog.pairRequested(passkeyInput.text);
                            else
                                bluetoothPairDialog.pairRequested("");
                        }
                    }
                }
            }

            Text {
                text: getHelpText(pairingMode)
                font.pixelSize: MTypography.sizeXSmall
                font.family: MTypography.fontFamily
                color: MColors.textTertiary
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
                wrapMode: Text.WordWrap
                visible: !isPairing
            }
        }

        transform: Translate {
            id: translateTransform

            y: dialogCard.height
        }

        layer.effect: ShaderEffect {
            property real blur: 32
        }
    }

    ParallelAnimation {
        id: showAnimation

        NumberAnimation {
            target: overlay
            property: "opacity"
            from: 0
            to: 1
            duration: 250
            easing.type: Easing.OutQuad
        }

        NumberAnimation {
            target: translateTransform
            property: "y"
            from: dialogCard.height
            to: 0
            duration: 300
            easing.type: Easing.OutCubic
        }
    }

    SequentialAnimation {
        id: hideAnimation

        ParallelAnimation {
            NumberAnimation {
                target: overlay
                property: "opacity"
                to: 0
                duration: 200
                easing.type: Easing.InQuad
            }

            NumberAnimation {
                target: translateTransform
                property: "y"
                to: dialogCard.height
                duration: 250
                easing.type: Easing.InCubic
            }
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
