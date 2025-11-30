import QtQuick
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme

Rectangle {
    id: contactEditorPage
    color: MColors.background

    property int contactId: -1
    property string contactName: ""
    property string contactPhone: ""
    property string contactEmail: ""
    property bool isNewContact: contactId === -1

    signal contactSaved
    signal cancelled

    Column {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            width: parent.width
            height: Constants.actionBarHeight
            color: MColors.surface

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: Constants.borderWidthThin
                color: MColors.border
            }

            Row {
                anchors.fill: parent
                anchors.margins: MSpacing.md
                spacing: MSpacing.md

                MIconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "x"
                    iconSize: 20
                    onClicked: {
                        cancelled();
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - parent.children[0].width - parent.children[2].width - parent.spacing * 2
                    text: isNewContact ? "New Contact" : "Edit Contact"
                    font.pixelSize: MTypography.sizeLarge
                    font.weight: Font.Bold
                    color: MColors.text
                }

                MIconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "check"
                    iconSize: 20
                    enabled: nameInput.text.length > 0 && phoneInput.text.length > 0
                    onClicked: {
                        saveContact();
                    }
                }
            }
        }

        Flickable {
            width: parent.width
            height: parent.height - parent.children[0].height
            contentHeight: contentColumn.height
            clip: true

            Column {
                id: contentColumn
                width: parent.width
                spacing: MSpacing.lg
                padding: MSpacing.lg

                Rectangle {
                    width: Constants.iconSizeXLarge * 2
                    height: Constants.iconSizeXLarge * 2
                    radius: Constants.iconSizeXLarge
                    color: MColors.surface
                    border.width: Constants.borderWidthThick
                    border.color: MColors.border
                    anchors.horizontalCenter: parent.horizontalCenter

                    Text {
                        anchors.centerIn: parent
                        text: nameInput.text.length > 0 ? nameInput.text.charAt(0).toUpperCase() : "?"
                        font.pixelSize: MTypography.sizeXLarge * 2
                        font.weight: Font.Bold
                        color: MColors.accent
                    }
                }

                Column {
                    width: parent.width - parent.padding * 2
                    spacing: MSpacing.sm

                    Text {
                        text: "Name *"
                        font.pixelSize: MTypography.sizeSmall
                        font.weight: Font.DemiBold
                        color: MColors.textSecondary
                    }

                    MTextInput {
                        id: nameInput
                        width: parent.width
                        placeholderText: "Enter name"
                        text: contactName
                    }
                }

                Column {
                    width: parent.width - parent.padding * 2
                    spacing: MSpacing.sm

                    Text {
                        text: "Phone *"
                        font.pixelSize: MTypography.sizeSmall
                        font.weight: Font.DemiBold
                        color: MColors.textSecondary
                    }

                    MTextInput {
                        id: phoneInput
                        width: parent.width
                        placeholderText: "+1 (555) 123-4567"
                        text: contactPhone
                        Component.onCompleted: {
                            textInput.inputMethodHints = Qt.ImhDialableCharactersOnly;
                        }
                    }
                }

                Column {
                    width: parent.width - parent.padding * 2
                    spacing: MSpacing.sm

                    Text {
                        text: "Email"
                        font.pixelSize: MTypography.sizeSmall
                        font.weight: Font.DemiBold
                        color: MColors.textSecondary
                    }

                    MTextInput {
                        id: emailInput
                        width: parent.width
                        placeholderText: "email@example.com"
                        text: contactEmail
                        Component.onCompleted: {
                            textInput.inputMethodHints = Qt.ImhEmailCharactersOnly;
                        }
                    }
                }

                Item {
                    height: MSpacing.lg
                }

                MButton {
                    width: parent.width - parent.padding * 2
                    text: isNewContact ? "Create Contact" : "Save Changes"
                    variant: "primary"
                    enabled: nameInput.text.length > 0 && phoneInput.text.length > 0
                    onClicked: {
                        saveContact();
                    }
                }

                MButton {
                    width: parent.width - parent.padding * 2
                    text: "Cancel"
                    variant: "secondary"
                    visible: !isNewContact
                    onClicked: {
                        cancelled();
                    }
                }

                MButton {
                    width: parent.width - parent.padding * 2
                    text: "Delete Contact"
                    variant: "secondary"
                    visible: !isNewContact
                    onClicked: {
                        deleteContact();
                    }
                }
            }
        }
    }

    function saveContact() {
        if (nameInput.text.length === 0 || phoneInput.text.length === 0) {
            return;
        }

        if (typeof ContactsManager !== 'undefined') {
            if (isNewContact) {
                ContactsManager.addContact(nameInput.text, phoneInput.text, emailInput.text);
                Logger.info("ContactEditor", "Created contact: " + nameInput.text);
            } else {
                ContactsManager.updateContact(contactId, {
                    "name": nameInput.text,
                    "phone": phoneInput.text,
                    "email": emailInput.text
                });
                Logger.info("ContactEditor", "Updated contact: " + nameInput.text);
            }
        }

        HapticService.medium();
        contactSaved();
    }

    function deleteContact() {
        if (typeof ContactsManager !== 'undefined' && contactId !== -1) {
            ContactsManager.deleteContact(contactId);
            Logger.info("ContactEditor", "Deleted contact ID: " + contactId);
        }
        HapticService.medium();
        contactSaved();
    }
}
