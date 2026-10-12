pragma ComponentBehavior: Bound

import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick

Rectangle {
    id: newConversationPage

    property string selectedContact: ""
    property string selectedContactName: ""
    readonly property string typed: recipientInput.text.trim()
    readonly property bool hasLetters: /[A-Za-z]/.test(typed)
    readonly property bool isValidNumber: !hasLetters && /^\+?[\d\s\-().]+$/.test(typed) && MPhoneNumber.digits(typed).length >= 3
    readonly property bool canStart: selectedContact.length > 0 || isValidNumber
    readonly property string helperText: {
        if (selectedContact.length > 0 || typed.length === 0 || isValidNumber)
            return "";
        if (hasLetters)
            return contactsList.count > 0 ? "Choose a contact below, or enter a phone number." : "No contact matches. Enter a phone number instead.";
        return "Enter at least 3 digits. You can use +, spaces, dashes and brackets.";
    }

    signal conversationStarted(string recipient, string recipientName)
    signal navigateBack

    function normalise(number) {
        return (number.charAt(0) === "+" ? "+" : "") + MPhoneNumber.digits(number);
    }

    function startConversation() {
        if (!canStart)
            return;
        const recipient = selectedContact.length > 0 ? selectedContact : normalise(typed);
        const name = selectedContactName.length > 0 ? selectedContactName : MPhoneNumber.format(recipient);
        Logger.info("NewConversation", "Starting conversation with: " + recipient);
        conversationStarted(recipient, name);
    }

    function clearContact() {
        selectedContact = "";
        selectedContactName = "";
        recipientInput.text = "";
    }

    color: MColors.background

    MTopBar {
        id: topBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        title: "New message"
        showBack: true
        onBackClicked: {
            HapticService.light();
            newConversationPage.navigateBack();
        }
    }

    Rectangle {
        id: recipientBar
        anchors.top: topBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: Constants.touchTargetLarge
        color: MColors.surface

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: Constants.borderWidthThin
            color: MColors.border
        }

        Text {
            id: toLabel
            anchors.left: parent.left
            anchors.leftMargin: MSpacing.md
            anchors.verticalCenter: parent.verticalCenter
            text: "To:"
            font.family: MTypography.fontFamily
            font.pixelSize: MTypography.sizeBody
            font.weight: Font.DemiBold
            color: MColors.textPrimary
        }

        MTextInput {
            id: recipientInput
            anchors.left: toLabel.right
            anchors.leftMargin: MSpacing.md
            anchors.right: clearButton.visible ? clearButton.left : startButton.left
            anchors.rightMargin: MSpacing.sm
            anchors.verticalCenter: parent.verticalCenter
            placeholderText: "Name or phone number"
            a11yName: "Recipient"
            visible: newConversationPage.selectedContact.length === 0
            onTextChanged: searchTimer.restart()
            onAccepted: newConversationPage.startConversation()
        }

        Text {
            anchors.left: toLabel.right
            anchors.leftMargin: MSpacing.md
            anchors.right: clearButton.left
            anchors.rightMargin: MSpacing.sm
            anchors.verticalCenter: parent.verticalCenter
            visible: newConversationPage.selectedContact.length > 0
            text: newConversationPage.selectedContactName + "  " + MPhoneNumber.format(newConversationPage.selectedContact)
            color: MColors.textPrimary
            font.family: MTypography.fontFamily
            font.pixelSize: MTypography.sizeBody
            elide: Text.ElideRight
        }

        MIconButton {
            id: clearButton
            anchors.right: startButton.left
            anchors.verticalCenter: parent.verticalCenter
            visible: newConversationPage.selectedContact.length > 0
            iconName: "x"
            a11yName: "Remove recipient"
            onClicked: newConversationPage.clearContact()
        }

        MIconButton {
            id: startButton
            anchors.right: parent.right
            anchors.rightMargin: MSpacing.sm
            anchors.verticalCenter: parent.verticalCenter
            iconName: "chevron-right"
            a11yName: "Start conversation"
            variant: newConversationPage.canStart ? "primary" : "ghost"
            disabled: !newConversationPage.canStart
            onClicked: {
                HapticService.medium();
                newConversationPage.startConversation();
            }
        }
    }

    Text {
        id: helper
        anchors.top: recipientBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: MSpacing.md
        height: visible ? implicitHeight : 0
        visible: text !== ""
        text: newConversationPage.helperText
        color: MColors.textSecondary
        font.family: MTypography.fontFamily
        font.pixelSize: MTypography.sizeFootnote
        wrapMode: Text.WordWrap
    }

    Timer {
        id: searchTimer

        interval: 300
        repeat: false
        onTriggered: contactsList.model = newConversationPage.typed.length > 0 ? ContactsManager.searchContacts(newConversationPage.typed) : ContactsManager.contacts
    }

    ListView {
        id: contactsList

        anchors.top: helper.visible ? helper.bottom : recipientBar.bottom
        anchors.topMargin: helper.visible ? MSpacing.sm : 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        spacing: MSpacing.xs
        topMargin: MSpacing.sm
        visible: newConversationPage.selectedContact.length === 0
        model: ContactsManager.contacts

        MEmptyState {
            visible: contactsList.count === 0 && newConversationPage.hasLetters
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: MSpacing.xl
            width: parent.width - MSpacing.xl * 2
            iconName: "users"
            title: "No contacts found"
            message: "Try a different name or enter a phone number."
        }

        delegate: Item {
            id: contactRow

            required property var modelData

            function select() {
                newConversationPage.selectedContact = contactRow.modelData.phone;
                newConversationPage.selectedContactName = contactRow.modelData.name;
            }

            width: contactsList.width
            height: 72

            MCard {
                anchors.fill: parent
                anchors.margins: MSpacing.xs
                elevation: 0
                radius: MRadius.lg

                MouseArea {
                    anchors.fill: parent
                    Accessible.role: Accessible.Button
                    Accessible.name: contactRow.modelData.name + ", " + MPhoneNumber.format(contactRow.modelData.phone)
                    Accessible.onPressAction: contactRow.select()
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
                    onClicked: contactRow.select()
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
                            text: contactRow.modelData.name ? contactRow.modelData.name.charAt(0).toUpperCase() : "?"
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
                            text: contactRow.modelData.name
                            variant: "primary"
                            font.pixelSize: MTypography.sizeBody
                            font.weight: MTypography.weightMedium
                            elide: Text.ElideRight
                            width: parent.width
                        }

                        MLabel {
                            text: MPhoneNumber.format(contactRow.modelData.phone)
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
