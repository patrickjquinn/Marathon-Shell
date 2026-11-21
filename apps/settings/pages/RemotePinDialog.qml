import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Dialog {
    id: dialog

    property alias pin: pinField.text
    property string title: qsTr("Remote connection")
    property string message: qsTr("Enter your PIN to let a computer log in with this password.")
    property string acceptText: qsTr("Allow")

    canAccept: pin.length >= 4

    Column {
        width: parent.width

        DialogHeader {
            acceptText: dialog.acceptText
            title: dialog.title
        }
        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            bottomPadding: Theme.paddingLarge
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.secondaryColor
            text: dialog.message
        }
        PasswordField {
            id: pinField

            objectName: "pinField"
            width: parent.width
            label: qsTr("PIN")
            placeholderText: label
            inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhSensitiveData
            focus: true
            EnterKey.enabled: dialog.canAccept
            EnterKey.iconSource: "image://theme/icon-m-enter-accept"
            EnterKey.onClicked: dialog.accept()
        }
    }
}
