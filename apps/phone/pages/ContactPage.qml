import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../Phone.js" as Phone

Page {
    id: root

    property var phone
    property int contactId: -1
    readonly property var contact: phone.contacts.find(c => c.id === contactId) || null

    function remove() {
        remorse.execute(qsTr("Deleted %1").arg(contact.name), function () {
            Contacts.deleteContact(root.contactId);
            root.phone.pageStack.pop();
        });
    }

    RemorsePopup {
        id: remorse
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem {
                objectName: "deleteMenuItem"
                text: qsTr("Delete")
                onClicked: root.remove()
            }
            MenuItem {
                objectName: "favoriteMenuItem"
                text: root.contact && root.contact.favorite ? qsTr("Remove from favorites") : qsTr("Add to favorites")
                onClicked: Contacts.updateContact(root.contactId, { favorite: !root.contact.favorite })
            }
            MenuItem {
                objectName: "editMenuItem"
                text: qsTr("Edit")
                onClicked: root.phone.pageStack.push(Qt.resolvedUrl("ContactEditorDialog.qml"), { contact: root.contact })
            }
        }

        Column {
            id: column

            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: root.contact ? root.contact.name : ""
                description: root.contact && root.contact.favorite ? qsTr("Favorite") : ""
            }

            Column {
                width: parent.width

                DetailItem {
                    objectName: "phoneDetail"
                    label: qsTr("Phone")
                    value: root.contact ? Phone.format(root.contact.phone) : ""
                }
                DetailItem {
                    objectName: "emailDetail"
                    visible: !!(root.contact && root.contact.email)
                    label: qsTr("Email")
                    value: root.contact && root.contact.email || ""
                }
            }

            Button {
                objectName: "callButton"
                anchors.horizontalCenter: parent.horizontalCenter
                preferredWidth: Theme.buttonWidthLarge
                icon.source: "image://theme/icon-m-call"
                text: qsTr("Call")
                onClicked: root.phone.call(root.contact.phone)
            }
            Button {
                objectName: "messageButton"
                anchors.horizontalCenter: parent.horizontalCenter
                preferredWidth: Theme.buttonWidthLarge
                icon.source: "image://theme/icon-m-message"
                text: qsTr("Send message")
                onClicked: root.phone.sendMessage(root.contact.phone)
            }
        }

        VerticalScrollDecorator {}
    }
}
