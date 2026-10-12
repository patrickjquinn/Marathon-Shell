import MarathonOS.Shell
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Modals
import MarathonUI.Theme
import QtQuick

Rectangle {
    id: contactEditorPage

    property int contactId: -1
    property string contactName: ""
    property string contactPhone: ""
    property string contactEmail: ""
    property bool isNewContact: contactId === -1
    readonly property bool canSave: nameInput.text.trim().length > 0 && MPhoneNumber.digits(phoneInput.text).length > 0
    readonly property bool dirty: nameInput.text !== contactName || MPhoneNumber.format(phoneInput.text) !== MPhoneNumber.format(contactPhone) || emailInput.text !== contactEmail

    signal contactSaved
    signal cancelled

    function saveContact() {
        if (!canSave)
            return;

        if (isNewContact) {
            ContactsManager.addContact(nameInput.text.trim(), phoneInput.text, emailInput.text.trim());
            Logger.info("ContactEditor", "Created contact: " + nameInput.text);
        } else {
            ContactsManager.updateContact(contactId, {
                "name": nameInput.text.trim(),
                "phone": phoneInput.text,
                "email": emailInput.text.trim()
            });
            Logger.info("ContactEditor", "Updated contact: " + nameInput.text);
        }
        HapticService.medium();
        contactSaved();
    }

    function deleteContact() {
        ContactsManager.deleteContact(contactId);
        Logger.info("ContactEditor", "Deleted contact ID: " + contactId);
        HapticService.medium();
        contactSaved();
    }

    function goBack() {
        if (deleteConfirm.showing)
            deleteConfirm.hide();
        else if (discardConfirm.showing)
            discardConfirm.hide();
        else if (dirty)
            discardConfirm.show();
        else
            cancelled();
    }

    color: MColors.background

    Column {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            id: header

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
                    id: closeButton

                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "x"
                    iconSize: 20
                    a11yName: qsTr("Close")
                    onClicked: contactEditorPage.goBack()
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - closeButton.width - parent.spacing
                    text: contactEditorPage.isNewContact ? qsTr("New Contact") : qsTr("Edit Contact")
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeLarge
                    font.weight: Font.Bold
                    color: MColors.text
                    elide: Text.ElideRight
                    Accessible.role: Accessible.Heading
                    Accessible.name: text
                }
            }
        }

        Flickable {
            width: parent.width
            height: parent.height - header.height
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

                    Icon {
                        anchors.centerIn: parent
                        visible: nameInput.text.trim().length === 0
                        name: "user"
                        size: Constants.iconSizeXLarge
                        color: MColors.textSecondary
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: nameInput.text.trim().length > 0
                        text: nameInput.text.trim().charAt(0).toUpperCase()
                        font.family: MTypography.fontFamily
                        font.pixelSize: MTypography.sizeXLarge * 2
                        font.weight: Font.Bold
                        color: MColors.accent
                    }
                }

                MTextField {
                    id: nameInput

                    width: parent.width - parent.padding * 2
                    label: qsTr("Name (required)")
                    placeholder: qsTr("Enter name")
                    text: contactEditorPage.contactName
                }

                MTextField {
                    id: phoneInput

                    width: parent.width - parent.padding * 2
                    label: qsTr("Phone (required)")
                    placeholder: qsTr("Phone number")
                    text: contactEditorPage.contactPhone
                    inputMethodHints: Qt.ImhDialableCharactersOnly
                    onFocusedChanged: {
                        if (!focused)
                            text = MPhoneNumber.format(text);
                    }
                }

                MTextField {
                    id: emailInput

                    width: parent.width - parent.padding * 2
                    label: qsTr("Email")
                    placeholder: "email@example.com"
                    text: contactEditorPage.contactEmail
                    inputMethodHints: Qt.ImhEmailCharactersOnly
                }

                Item {
                    width: 1
                    height: MSpacing.lg
                }

                MButton {
                    width: parent.width - parent.padding * 2
                    text: contactEditorPage.isNewContact ? qsTr("Create Contact") : qsTr("Save Changes")
                    variant: "primary"
                    enabled: contactEditorPage.canSave
                    onClicked: contactEditorPage.saveContact()
                }

                MButton {
                    width: parent.width - parent.padding * 2
                    text: qsTr("Delete Contact")
                    variant: "danger"
                    visible: !contactEditorPage.isNewContact
                    onClicked: deleteConfirm.show()
                }
            }
        }
    }

    MConfirmDialog {
        id: deleteConfirm

        title: qsTr("Delete contact?")
        message: qsTr("%1 will be removed from your contacts. This can't be undone.").arg(contactEditorPage.contactName)
        confirmText: qsTr("Delete contact")
        destructive: true
        onConfirmed: contactEditorPage.deleteContact()
        onCancelled: hide()
    }

    MConfirmDialog {
        id: discardConfirm

        title: qsTr("Discard changes?")
        message: qsTr("Your changes to this contact haven't been saved.")
        confirmText: qsTr("Discard")
        cancelText: qsTr("Keep editing")
        destructive: true
        onConfirmed: contactEditorPage.cancelled()
        onCancelled: hide()
    }
}
