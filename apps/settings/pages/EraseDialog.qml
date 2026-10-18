import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0

Dialog {
    id: dialog

    property alias secret: secretField.text
    property string error: ""

    canAccept: secret.length > 0

    Column {
        width: parent.width

        DialogHeader {
            acceptText: qsTr("Erase")
            title: qsTr("Erase this phone?")
        }
        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            bottomPadding: Theme.paddingLarge
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.secondaryHighlightColor
            text: qsTr("All content and settings are deleted, and this can't be undone.")
        }
        PasswordField {
            id: secretField

            objectName: "secretField"
            width: parent.width
            label: Security.hasQuickPIN ? qsTr("PIN") : qsTr("System password")
            placeholderText: label
            description: dialog.error !== "" ? dialog.error : Security.hasQuickPIN ? qsTr("Enter your PIN to erase") : qsTr("Enter your system password to erase")
            errorHighlight: dialog.error !== ""
            onTextChanged: dialog.error = ""
            inputMethodHints: Security.hasQuickPIN ? Qt.ImhDigitsOnly | Qt.ImhSensitiveData : Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
            focus: true
            EnterKey.enabled: dialog.canAccept
            EnterKey.iconSource: "image://theme/icon-m-enter-accept"
            EnterKey.onClicked: dialog.accept()
        }
    }
}
