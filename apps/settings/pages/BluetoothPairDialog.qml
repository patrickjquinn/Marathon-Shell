import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import MarathonOS.Settings 1.0
import "../SettingsLogic.js" as Logic

Dialog {
    id: dialog

    readonly property string mode: SettingsController.bluetoothDialogMode
    property alias pin: pinField.text
    property alias passkey: passkeyField.text

    canAccept: SettingsController.bluetoothCanPair(mode, pin, passkey)
    onAccepted: {
        if (mode === "confirm")
            SettingsController.confirmBluetoothPairing(true);
        else if (mode === "passkey")
            SettingsController.submitBluetoothPasskey(passkey);
        else
            SettingsController.submitBluetoothPin(mode === "pin" ? pin : "");
    }
    onRejected: {
        if (mode === "confirm")
            SettingsController.confirmBluetoothPairing(false);
        else
            SettingsController.cancelBluetoothPairing();
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column

            width: parent.width
            spacing: Theme.paddingMedium

            DialogHeader {
                acceptText: dialog.mode === "confirm" ? qsTr("Accept") : qsTr("Pair")
                cancelText: dialog.mode === "confirm" ? qsTr("Reject") : qsTr("Cancel")
                title: SettingsController.bluetoothDialogName
            }
            Row {
                x: Theme.horizontalPageMargin
                spacing: Theme.paddingMedium

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    source: Logic.deviceIcon(SettingsController.bluetoothDialogType)
                    color: Theme.highlightColor
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: SettingsController.bluetoothPairingModeText(dialog.mode)
                    color: Theme.highlightColor
                }
            }
            Label {
                objectName: "errorLabel"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: text !== ""
                text: SettingsController.bluetoothDialogError
                wrapMode: Text.Wrap
                color: Theme.errorColor
            }
            TextField {
                id: pinField

                objectName: "pinField"
                width: parent.width
                visible: dialog.mode === "pin"
                label: qsTr("PIN")
                placeholderText: qsTr("PIN")
                inputMethodHints: Qt.ImhPreferNumbers | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                // Legacy pairing PINs are up to 16 characters and may contain letters.
                validator: RegularExpressionValidator {
                    regularExpression: /[0-9A-Za-z]{0,16}/
                }
                focus: visible
                EnterKey.enabled: dialog.canAccept
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: dialog.accept()
            }
            TextField {
                id: passkeyField

                objectName: "passkeyField"
                width: parent.width
                visible: dialog.mode === "passkey"
                label: qsTr("Passkey")
                placeholderText: qsTr("6 digits")
                inputMethodHints: Qt.ImhDigitsOnly
                validator: RegularExpressionValidator {
                    regularExpression: /[0-9]{0,6}/
                }
                focus: visible
                EnterKey.enabled: dialog.canAccept
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: dialog.accept()
            }
            Label {
                objectName: "passkeyLabel"
                width: parent.width
                visible: dialog.mode === "confirm"
                text: SettingsController.bluetoothDialogPasskey
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Theme.fontSizeHuge
                font.letterSpacing: Theme.paddingSmall
                color: Theme.highlightColor
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: SettingsController.bluetoothHelpText(dialog.mode)
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
            }
        }
    }
}
