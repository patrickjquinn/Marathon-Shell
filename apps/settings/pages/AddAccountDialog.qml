import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Dialog {
    id: dialog

    property alias displayName: nameField.text
    property alias baseUrl: urlField.text
    property alias username: userField.text
    property alias secret: secretField.text

    canAccept: baseUrl.trim() !== "" && username.trim() !== ""

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column

            width: parent.width

            DialogHeader {
                acceptText: qsTr("Add")
                title: qsTr("New account")
            }
            TextField {
                id: urlField

                objectName: "urlField"
                width: parent.width
                label: qsTr("Server URL")
                placeholderText: qsTr("https://cloud.example.com")
                inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                focus: true
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: userField.focus = true
            }
            TextField {
                id: userField

                objectName: "userField"
                width: parent.width
                label: qsTr("Username")
                placeholderText: qsTr("you@example.com")
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: secretField.focus = true
            }
            PasswordField {
                id: secretField

                objectName: "secretField"
                width: parent.width
                label: qsTr("Password or app password")
                placeholderText: qsTr("Password or app password")
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: nameField.focus = true
            }
            TextField {
                id: nameField

                objectName: "nameField"
                width: parent.width
                label: qsTr("Name (optional)")
                placeholderText: qsTr("My Nextcloud")
                EnterKey.enabled: dialog.canAccept
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: dialog.accept()
            }
        }
    }
}
