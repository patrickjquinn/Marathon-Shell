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
    readonly property bool favorite: !!(contact && contact.favorite)

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
                objectName: "editMenuItem"
                text: qsTr("Edit")
                onClicked: root.phone.pageStack.push(Qt.resolvedUrl("ContactEditorDialog.qml"), {
                    contact: root.contact
                })
            }
        }

        Column {
            id: column

            width: parent.width

            PageHeader {
                id: header

                title: root.contact ? root.contact.name : ""
                wrapMode: Text.Wrap

                IconButton {
                    objectName: "favoriteButton"
                    parent: header.extraContent
                    anchors.verticalCenter: parent.verticalCenter
                    icon.source: root.favorite ? "image://theme/icon-m-favorite-selected" : "image://theme/icon-m-favorite"
                    highlighted: down || root.favorite
                    Accessible.role: Accessible.CheckBox
                    Accessible.name: qsTr("Favorite")
                    Accessible.checkable: true
                    Accessible.checked: root.favorite
                    onClicked: Contacts.updateContact(root.contactId, {
                        favorite: !root.favorite
                    })
                }
            }

            ListItem {
                id: phoneRow

                objectName: "phoneItem"
                contentHeight: Theme.itemSizeMedium
                Accessible.name: qsTr("Call %1").arg(phoneValue.text)
                onClicked: root.phone.call(root.contact.phone)

                Icon {
                    id: phoneIcon

                    x: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    source: "image://theme/icon-m-call"
                    highlighted: phoneRow.highlighted
                }
                Column {
                    anchors {
                        left: phoneIcon.right
                        leftMargin: Theme.paddingLarge
                        right: messageButton.left
                        rightMargin: Theme.paddingMedium
                        verticalCenter: parent.verticalCenter
                    }

                    Label {
                        id: phoneValue

                        objectName: "phoneValue"
                        width: parent.width
                        text: root.contact ? Phone.format(root.contact.phone) : ""
                        truncationMode: TruncationMode.Fade
                        color: phoneRow.highlighted ? Theme.highlightColor : Theme.primaryColor
                    }
                    Label {
                        width: parent.width
                        text: qsTr("Phone")
                        font.pixelSize: Theme.fontSizeSmall
                        color: phoneRow.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                    }
                }
                IconButton {
                    id: messageButton

                    objectName: "messageButton"
                    anchors {
                        right: parent.right
                        rightMargin: Theme.horizontalPageMargin - Theme.paddingMedium
                        verticalCenter: parent.verticalCenter
                    }
                    icon.source: "image://theme/icon-m-message"
                    Accessible.name: qsTr("Send message")
                    onClicked: root.phone.sendMessage(root.contact.phone)
                }
            }

            Item {
                width: parent.width
                height: Theme.itemSizeMedium
                visible: !!(root.contact && root.contact.email)

                Icon {
                    id: emailIcon

                    x: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    source: "image://theme/icon-m-mail"
                    color: Theme.highlightColor
                }
                Column {
                    anchors {
                        left: emailIcon.right
                        leftMargin: Theme.paddingLarge
                        right: parent.right
                        rightMargin: Theme.horizontalPageMargin
                        verticalCenter: parent.verticalCenter
                    }

                    Label {
                        objectName: "emailValue"
                        width: parent.width
                        text: root.contact && root.contact.email || ""
                        truncationMode: TruncationMode.Fade
                        color: Theme.highlightColor
                    }
                    Label {
                        width: parent.width
                        text: qsTr("Email")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.secondaryHighlightColor
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
