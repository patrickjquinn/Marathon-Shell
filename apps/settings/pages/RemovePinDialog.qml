import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Dialog {
    id: dialog

    property alias password: passwordField.text

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
            text: qsTr("You'll unlock with your system password. Enter it to confirm.")
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
