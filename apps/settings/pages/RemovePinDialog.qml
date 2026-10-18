import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Dialog {
    id: dialog

    property alias password: passwordField.text
    // The PIN locks the data partition at startup.
    property bool dataLocked: false

    canAccept: password.trim().length > 0

    Column {
        width: parent.width

        DialogHeader {
            acceptText: qsTr("Remove")
            title: qsTr("Remove quick PIN?")
        }
        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            bottomPadding: Theme.paddingLarge
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.secondaryHighlightColor
            text: dialog.dataLocked ? qsTr("You'll unlock with your system password, and your phone will start without asking for a PIN, so anyone who has it can read your data. Enter your password to confirm.") : qsTr("You'll unlock with your system password. Enter it to confirm.")
        }
        PasswordField {
            id: passwordField

            objectName: "passwordField"
            width: parent.width
            label: qsTr("System password")
            placeholderText: qsTr("System password")
            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
            focus: true
            EnterKey.enabled: dialog.canAccept
            EnterKey.iconSource: "image://theme/icon-m-enter-accept"
            EnterKey.onClicked: dialog.accept()
        }
    }
}
