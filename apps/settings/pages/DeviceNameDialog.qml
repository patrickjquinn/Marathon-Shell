import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Dialog {
    id: dialog

    property alias name: nameField.text

    canAccept: name.trim() !== ""

    Column {
        width: parent.width

        DialogHeader {
            acceptText: qsTr("Save")
            title: qsTr("Device name")
        }
        TextField {
            id: nameField

            objectName: "nameField"
            width: parent.width
            label: qsTr("Name for this device")
            placeholderText: qsTr("Name for this device")
            description: dialog.canAccept ? "" : qsTr("Enter a name")
            focus: true
            EnterKey.enabled: dialog.canAccept
            EnterKey.iconSource: "image://theme/icon-m-enter-accept"
            EnterKey.onClicked: dialog.accept()
        }
    }
}
