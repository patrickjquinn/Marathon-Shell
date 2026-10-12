import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../Phone.js" as Phone

Dialog {
    id: root

    property var contact: null

    canAccept: nameField.text.trim().length > 0 && Phone.digits(phoneField.text).length > 0
    onAccepted: {
        const name = nameField.text.trim();
        const email = emailField.text.trim();
        if (contact)
            Contacts.updateContact(contact.id, { name: name, phone: phoneField.text, email: email });
        else
            Contacts.addContact(name, phoneField.text, email);
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column

            width: parent.width

            DialogHeader {
                title: root.contact ? qsTr("Edit contact") : qsTr("New contact")
                acceptText: qsTr("Save")
            }
            TextField {
                id: nameField

                objectName: "nameField"
                width: parent.width
                label: qsTr("Name")
                placeholderText: qsTr("Name")
                text: root.contact ? root.contact.name || "" : ""
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: phoneField.focus = true
            }
            TextField {
                id: phoneField

                objectName: "phoneField"
                width: parent.width
                label: qsTr("Phone")
                placeholderText: qsTr("Phone")
                text: root.contact ? root.contact.phone || "" : ""
                inputMethodHints: Qt.ImhDialableCharactersOnly
                EnterKey.iconSource: "image://theme/icon-m-enter-next"
                EnterKey.onClicked: emailField.focus = true
            }
            TextField {
                id: emailField

                objectName: "emailField"
                width: parent.width
                label: qsTr("Email")
                placeholderText: qsTr("Email")
                text: root.contact ? root.contact.email || "" : ""
                inputMethodHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: if (root.canAccept) root.accept()
            }
        }

        VerticalScrollDecorator {}
    }
}
