import MarathonApp.Messages
import MarathonApp.Messages
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Feedback
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

Rectangle {
    id: newConversationPage

    property string selectedContact: ""
    property string selectedContactName: ""
    property bool isValidNumber: validatePhoneNumber(recipientInput.text)

    signal conversationStarted(string recipient, string recipientName)
    signal cancelled

    function startConversation() {
        var recipient = selectedContact.length > 0 ? selectedContact : recipientInput.text;
        var name = selectedContactName.length > 0 ? selectedContactName : recipient;
        if (recipient.length > 0 && isValidNumber) {
            Logger.info("NewConversation", "Starting conversation with: " + recipient);
            conversationStarted(recipient, name);
        } else {
            Logger.warn("NewConversation", "Invalid phone number: " + recipient);
        }
    }

    function validatePhoneNumber(number) {
        if (!number || number.length === 0)
            return false;

        var cleaned = number.replace(/\D/g, '');
        return cleaned.length >= 10;
    }

    color: MColors.background

    Column {
        anchors.fill: parent
        spacing: 0

        MActionBar {
            width: parent.width
            showBack: true
            onBackClicked: {
                HapticService.light();
                cancelled();
            }

            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 92
                anchors.verticalCenter: parent.verticalCenter
                width: titleText.width
                height: titleText.height
                color: "transparent"

                MLabel {
                    id: titleText

                    text: "New Message"
                    variant: "primary"
                    font.pixelSize: MTypography.sizeLarge
                    font.weight: MTypography.weightBold
                }
            }
        }

        Column {
            width: parent.width
            height: parent.height - parent.children[0].height
            spacing: 0

            Rectangle {
                width: parent.width
                height: Constants.touchTargetLarge
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

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "To:"
                        font.pixelSize: MTypography.sizeBody
                        font.weight: Font.DemiBold
                        color: MColors.textPrimary
                    }

                    MTextInput {
                        id: recipientInput

                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - parent.children[0].width - parent.children[2].width - parent.spacing * 2
                        placeholderText: "Phone number or contact name"
                        text: selectedContactName || selectedContact
                        enabled: selectedContact.length === 0
                        onTextChanged: {
                            if (selectedContact.length === 0)
                                searchTimer.restart();
                        }
                    }

                    MIconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        iconName: "chevron-right"
                        iconSize: Constants.touchTargetMedium
                        variant: (selectedContact.length > 0 || isValidNumber) ? "primary" : "ghost"
                        enabled: selectedContact.length > 0 || isValidNumber
                        onClicked: {
                            HapticService.medium();
                            startConversation();
                        }
                    }
                }
            }

            Timer {
                id: searchTimer

                interval: 300
                repeat: false
                onTriggered: {
                    if (recipientInput.text.length > 0 && typeof ContactsManager !== 'undefined')
                        contactsList.model = ContactsManager.searchContacts(recipientInput.text);
                }
            }

            MEmptyState {
                visible: contactsList.count === 0 && recipientInput.text.length > 2
                anchors.centerIn: parent
                width: parent.width - MSpacing.xl * 2
                iconName: "users"
                title: "No contacts found"
                message: "Try a different search or enter a phone number"
            }

            ListView {
                id: contactsList

                width: parent.width
                height: parent.height - parent.children[0].height
                clip: true
                spacing: MSpacing.xs
                topMargin: MSpacing.sm
                model: typeof ContactsManager !== 'undefined' ? ContactsManager.contacts : []

                delegate: Item {
                    width: contactsList.width
                    height: 72

                    MCard {
                        anchors.fill: parent
                        anchors.margins: MSpacing.xs
                        elevation: 0
                        radius: MRadius.lg

                        MouseArea {
                            anchors.fill: parent
                            onPressed: {
                                parent.scale = 0.98;
                                HapticService.light();
                            }
                            onReleased: {
                                parent.scale = 1;
                            }
                            onCanceled: {
                                parent.scale = 1;
                            }
                            onClicked: {
                                selectedContact = modelData.phone;
                                selectedContactName = modelData.name;
                                recipientInput.text = modelData.name;
                                Logger.info("NewConversation", "Selected contact: " + modelData.name);
                            }
                        }

                        content: Row {
                            anchors.fill: parent
                            anchors.margins: MSpacing.md
                            spacing: MSpacing.md

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 40
                                height: 40
                                radius: MRadius.full
                                color: MColors.marathonTeal

                                MLabel {
                                    anchors.centerIn: parent
                                    text: modelData.name ? modelData.name.charAt(0).toUpperCase() : "?"
                                    variant: "primary"
                                    font.pixelSize: MTypography.sizeBody
                                    font.weight: MTypography.weightBold
                                }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 56
                                spacing: MSpacing.xs

                                MLabel {
                                    text: modelData.name
                                    variant: "primary"
                                    font.pixelSize: MTypography.sizeBody
                                    font.weight: MTypography.weightMedium
                                    elide: Text.ElideRight
                                    width: parent.width
                                }

                                MLabel {
                                    text: modelData.phone
                                    variant: "secondary"
                                    font.pixelSize: MTypography.sizeSmall
                                }
                            }
                        }

                        Behavior on scale {
                            NumberAnimation {
                                duration: MMotion.fast
                            }
                        }
                    }
                }
            }
        }
    }
}
