pragma ComponentBehavior: Bound

import MarathonApp.Settings
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

Item {
    id: bluetoothPairDialog

    property string deviceName: SettingsController.bluetoothDialogName
    property string deviceAddress: SettingsController.bluetoothDialogAddress
    property string deviceType: SettingsController.bluetoothDialogType
    property string pairingMode: SettingsController.bluetoothDialogMode
    property string displayedPasskey: SettingsController.bluetoothDialogPasskey
    property bool isPairing: SettingsController.bluetoothDialogPairing
    property string errorMessage: SettingsController.bluetoothDialogError
    property bool dialogVisible: SettingsController.bluetoothDialogVisible
    property bool internalVisible: false

    anchors.fill: parent
    visible: internalVisible
    z: Constants.zIndexModalOverlay + 10
    Keys.onEscapePressed: {
        if (!bluetoothPairDialog.isPairing)
            SettingsController.cancelBluetoothPairing();
    }
    onDialogVisibleChanged: {
        if (bluetoothPairDialog.dialogVisible) {
            internalVisible = true;
            pinInput.text = "";
            passkeyInput.text = "";
            if (bluetoothPairDialog.pairingMode === "pin")
                pinInput.forceActiveFocus();
            else if (bluetoothPairDialog.pairingMode === "passkey")
                passkeyInput.forceActiveFocus();
            showAnimation.restart();
            HapticService.light();
        } else if (internalVisible) {
            hideAnimation.restart();
        }
    }
    onErrorMessageChanged: {
        if (bluetoothPairDialog.errorMessage.length > 0)
            HapticService.medium();
    }

    Rectangle {
        id: overlay

        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.6)
        opacity: 0

        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (!bluetoothPairDialog.isPairing)
                    SettingsController.cancelBluetoothPairing();
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
                        name: SettingsController.bluetoothDeviceIcon(bluetoothPairDialog.deviceType)
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
                        text: SettingsController.bluetoothPairingModeText(bluetoothPairDialog.pairingMode)
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
                border.color: bluetoothPairDialog.errorMessage !== "" ? MColors.error : ((pinInput.activeFocus || passkeyInput.activeFocus) ? MColors.marathonTeal : MColors.border)
                visible: bluetoothPairDialog.pairingMode === "pin" || bluetoothPairDialog.pairingMode === "passkey"

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

                        visible: bluetoothPairDialog.pairingMode === "pin"
                        width: parent.width - Constants.iconSizeMedium - MSpacing.md
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: MTypography.sizeBody
                        font.family: MTypography.fontFamily
                        color: MColors.textPrimary
                        inputMethodHints: Qt.ImhDigitsOnly
                        maximumLength: 6
                        enabled: !bluetoothPairDialog.isPairing
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

                        visible: bluetoothPairDialog.pairingMode === "passkey"
                        width: parent.width - Constants.iconSizeMedium - MSpacing.md
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: MTypography.sizeBody
                        font.family: MTypography.fontFamily
                        color: MColors.textPrimary
                        inputMethodHints: Qt.ImhDigitsOnly
                        maximumLength: 6
                        enabled: !bluetoothPairDialog.isPairing
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
                visible: bluetoothPairDialog.pairingMode === "confirm"

                Column {
                    anchors.centerIn: parent
                    spacing: MSpacing.sm

                    Text {
                        text: bluetoothPairDialog.displayedPasskey
                        font.pixelSize: MTypography.sizeGigantic
                        font.weight: Font.Light
                        font.family: MTypography.fontMonospace || "monospace"
                        font.letterSpacing: 8
                        color: MColors.marathonTeal
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Text {
                        text: "Verify this code matches on " + bluetoothPairDialog.deviceName
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
                visible: bluetoothPairDialog.errorMessage !== "" && !bluetoothPairDialog.isPairing

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

                        text: bluetoothPairDialog.errorMessage
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
                visible: bluetoothPairDialog.isPairing

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: MSpacing.md

                    BusyIndicator {
                        width: Constants.iconSizeMedium
                        height: Constants.iconSizeMedium
                        running: bluetoothPairDialog.isPairing
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "Pairing with " + bluetoothPairDialog.deviceName + "..."
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
                visible: !bluetoothPairDialog.isPairing

                Rectangle {
                    width: (parent.width - MSpacing.md) / 2
                    height: parent.height
                    radius: Constants.borderRadiusSmall
                    color: "transparent"
                    border.width: Constants.borderWidthThin
                    border.color: MColors.border

                    Text {
                        text: bluetoothPairDialog.pairingMode === "confirm" ? "Reject" : "Cancel"
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
                            if (bluetoothPairDialog.pairingMode === "confirm")
                                SettingsController.confirmBluetoothPairing(false);
                            else
                                SettingsController.cancelBluetoothPairing();
                        }
                    }
                }

                Rectangle {
                    id: pairButton

                    signal clicked

                    width: (parent.width - MSpacing.md) / 2
                    height: parent.height
                    radius: Constants.borderRadiusSmall
                    color: SettingsController.bluetoothCanPair(bluetoothPairDialog.pairingMode, pinInput.text, passkeyInput.text) ? MColors.marathonTeal : Qt.darker(MColors.marathonTeal, 1.5)
                    opacity: SettingsController.bluetoothCanPair(bluetoothPairDialog.pairingMode, pinInput.text, passkeyInput.text) ? 1 : 0.5

                    Text {
                        text: bluetoothPairDialog.pairingMode === "confirm" ? "Accept" : "Pair"
                        font.pixelSize: MTypography.sizeLarge
                        font.weight: Font.Medium
                        font.family: MTypography.fontFamily
                        color: MColors.background
                        anchors.centerIn: parent
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: SettingsController.bluetoothCanPair(bluetoothPairDialog.pairingMode, pinInput.text, passkeyInput.text)
                        onClicked: {
                            Logger.info("BluetoothPairDialog", "Pair/Accept clicked");
                            HapticService.medium();
                            if (bluetoothPairDialog.pairingMode === "confirm")
                                SettingsController.confirmBluetoothPairing(true);
                            else if (bluetoothPairDialog.pairingMode === "pin")
                                SettingsController.submitBluetoothPin(pinInput.text);
                            else if (bluetoothPairDialog.pairingMode === "passkey")
                                SettingsController.submitBluetoothPasskey(passkeyInput.text);
                            else
                                SettingsController.submitBluetoothPin("");
                        }
                    }
                }
            }

            Text {
                text: SettingsController.bluetoothHelpText(bluetoothPairDialog.pairingMode)
                font.pixelSize: MTypography.sizeXSmall
                font.family: MTypography.fontFamily
                color: MColors.textTertiary
                horizontalAlignment: Text.AlignHCenter
                width: parent.width
                wrapMode: Text.WordWrap
                visible: !bluetoothPairDialog.isPairing
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
                bluetoothPairDialog.internalVisible = false;
                pinInput.text = "";
                passkeyInput.text = "";
            }
        }
    }
}
