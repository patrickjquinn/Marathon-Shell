import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../MessagesLogic.js" as Logic

Dialog {
    id: root

    property string number
    readonly property string name: nameField.text.trim()

    canAccept: name !== ""
    onAcceptBlocked: Notices.show(qsTr("Add a name first"))
    onAccepted: Contacts.addContact(name, number)
    onStatusChanged: if (status === PageStatus.Active && Window.activeFocusItem === root)
        nameField.forceActiveFocus()

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column

            width: parent.width

            DialogHeader {
                title: qsTr("New contact")
                acceptText: qsTr("Save")
            }
            TextField {
                id: nameField

                objectName: "nameField"
                width: parent.width
                label: qsTr("Name")
                placeholderText: qsTr("Name")
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: root.accept()
            }
            DetailItem {
                label: qsTr("Phone")
                value: Logic.formatNumber(root.number)
                alignment: Qt.AlignLeft
            }
        }
    }
}
