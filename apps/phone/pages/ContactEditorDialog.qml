pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../Phone.js" as Phone

Dialog {
    id: root

    property var contact: null

    // Numbers or addresses, each in its own field with its kind under it.
    component Details: Column {
        id: details

        property var entries: []
        property var kinds: []
        property string fieldName
        property string placeholder
        property string addText
        property int hints
        property int filled: values().length

        function values() {
            return entries.filter(e => e.value.trim() !== "").map(e => ({
                        type: e.type,
                        value: e.value.trim()
                    }));
        }

        function focusField(index) {
            fields.itemAt(index).forceActiveFocus();
        }

        function add() {
            entries = entries.concat([
                {
                    type: kinds[0],
                    value: ""
                }
            ]);
            focusField(fields.count - 1);
        }

        width: parent.width

        Repeater {
            id: fields

            model: details.entries.length

            TextField {
                id: field

                required property int index
                readonly property var entry: details.entries[index]

                objectName: details.fieldName
                width: details.width
                text: details.entries[index].value
                placeholderText: details.placeholder
                inputMethodHints: details.hints
                labelComponent: Component {
                    MiniComboBox {
                        id: kind

                        // Its own field's entry: field.index read 0 here for every field.
                        readonly property var entry: _textField ? _textField.entry : null

                        menu: ContextMenu {
                            MenuItem {
                                text: Phone.kindName(Phone.kinds[0])
                                visible: details.kinds.indexOf(Phone.kinds[0]) !== -1
                                onClicked: kind.entry.type = Phone.kinds[0]
                            }
                            MenuItem {
                                text: Phone.kindName(Phone.kinds[1])
                                visible: details.kinds.indexOf(Phone.kinds[1]) !== -1
                                onClicked: kind.entry.type = Phone.kinds[1]
                            }
                            MenuItem {
                                text: Phone.kindName(Phone.kinds[2])
                                visible: details.kinds.indexOf(Phone.kinds[2]) !== -1
                                onClicked: kind.entry.type = Phone.kinds[2]
                            }
                            MenuItem {
                                text: Phone.kindName(Phone.kinds[3])
                                visible: details.kinds.indexOf(Phone.kinds[3]) !== -1
                                onClicked: kind.entry.type = Phone.kinds[3]
                            }
                            MenuItem {
                                text: Phone.kindName(Phone.kinds[4])
                                visible: details.kinds.indexOf(Phone.kinds[4]) !== -1
                                onClicked: kind.entry.type = Phone.kinds[4]
                            }
                        }
                        // Set, not bound: the combo box clears its index until its field is found.
                        onEntryChanged: currentIndex = entry ? Phone.kinds.indexOf(entry.type) : -1
                    }
                }
                onTextChanged: {
                    details.entries[index].value = text;
                    details.filled = details.values().length;
                }
            }
        }

        BackgroundItem {
            id: addItem

            objectName: details.fieldName + "Add"
            onClicked: details.add()

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x
                anchors.verticalCenter: parent.verticalCenter
                text: details.addText
                color: addItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                truncationMode: TruncationMode.Fade
            }
        }
    }

    canAccept: nameField.text.trim().length > 0 && phones.filled > 0
    onAcceptBlocked: Notices.show(nameField.text.trim().length === 0 ? qsTr("Add a name first") : qsTr("Add a phone number first"))
    onAccepted: {
        const data = {
            name: nameField.text.trim(),
            phones: phones.values(),
            emails: emails.values(),
            note: noteField.text.trim()
        };
        if (contact)
            Contacts.updateContact(contact.id, data);
        else
            Contacts.createContact(data);
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
                EnterKey.onClicked: phones.focusField(0)
            }
            Details {
                id: phones

                entries: Phone.contactEntries(root.contact, "phones", "phone", "mobile")
                kinds: Phone.kinds
                fieldName: "phoneField"
                placeholder: qsTr("Phone")
                addText: qsTr("Add phone number")
                hints: Qt.ImhDialableCharactersOnly
            }
            Details {
                id: emails

                entries: Phone.contactEntries(root.contact, "emails", "email", "home")
                kinds: ["home", "work", "other"]
                fieldName: "emailField"
                placeholder: qsTr("Email")
                addText: qsTr("Add email address")
                hints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase
            }
            TextArea {
                id: noteField

                objectName: "noteField"
                width: parent.width
                label: qsTr("Notes")
                placeholderText: qsTr("Notes")
                text: root.contact ? root.contact.note || "" : ""
            }
        }

        VerticalScrollDecorator {}
    }
}
