import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import MarathonApp.Settings

Dialog {
    id: dialog

    property bool changing: false
    // The data partition is encrypted, so this PIN is asked for at startup.
    property bool startupPin: false
    property alias pin: pinField.text
    property alias confirmation: confirmField.text
    property alias password: passwordField.text
    property string error: ""
    readonly property bool mismatch: confirmation.length >= pin.length && confirmation.length > 0 && confirmation !== pin

    canAccept: SettingsController.quickPinValidationError(pin, password) === "" && confirmation === pin

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column

            width: parent.width

            DialogHeader {
                acceptText: qsTr("Save")
                title: dialog.changing ? qsTr("Change quick PIN") : qsTr("Set quick PIN")
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                bottomPadding: Theme.paddingLarge
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: dialog.startupPin ? qsTr("Your phone asks for this PIN when it starts. After that your system password works too.") : qsTr("The quick PIN is a shortcut. Your system password always works too.")
            }
            PasswordField {
                id: pinField

                objectName: "pinField"
                width: parent.width
                label: qsTr("New PIN")
                placeholderText: qsTr("4–6 digits")
                description: text.length > 0 && text.length < 4 ? qsTr("Use 4 to 6 digits") : ""
                inputMethodHints: Qt.ImhDigitsOnly
                validator: RegularExpressionValidator {
                    regularExpression: /[0-9]{0,6}/
                }
                focus: dialog.error === ""
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: confirmField.focus = true
            }
            PasswordField {
                id: confirmField

                objectName: "confirmField"
                width: parent.width
                label: qsTr("Confirm PIN")
                placeholderText: qsTr("Enter the PIN again")
                description: dialog.mismatch ? qsTr("The PINs don't match") : ""
                errorHighlight: dialog.mismatch
                inputMethodHints: Qt.ImhDigitsOnly
                validator: RegularExpressionValidator {
                    regularExpression: /[0-9]{0,6}/
                }
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: passwordField.focus = true
            }
            PasswordField {
                id: passwordField

                objectName: "passwordField"
                width: parent.width
                label: qsTr("System password")
                placeholderText: qsTr("System password")
                description: dialog.error !== "" ? dialog.error : qsTr("Needed to change the PIN")
                errorHighlight: dialog.error !== ""
                focus: dialog.error !== ""
                onTextChanged: dialog.error = ""
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                EnterKey.enabled: dialog.canAccept
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: dialog.accept()
            }
        }
    }
}
