pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../MessagesLogic.js" as Logic
import "../components"

Page {
    id: root

    property var app
    property var conversation
    property var messages: []
    readonly property string recipientNumber: conversation.contactNumber
    property string contactName: conversation.contactName || ""
    readonly property bool hasModem: Telephony.hasModem
    readonly property bool canSend: hasModem && pendingText === "" && input.text.trim() !== ""
    property string pendingText: ""
    property string sendError: ""

    function load() {
        messages = Logic.messageRows(Sms.getMessages(conversation.id));
        view.positionViewAtEnd();
    }

    function send() {
        if (!canSend)
            return;
        pendingText = input.text.trim();
        sendError = "";
        sendTimeout.restart();
        Sms.sendMessage(recipientNumber, pendingText);
    }

    function failureText(reason) {
        if (/modem/i.test(reason))
            return qsTr("Not sent. No mobile network is available; check the SIM card and signal.");
        return qsTr("Not sent. Check your mobile signal and try again.");
    }

    Component.onCompleted: {
        load();
        if (conversation.unreadCount > 0)
            Sms.markAsRead(conversation.id);
        input.text = app.drafts[conversation.id] || "";
    }

    Timer {
        id: sendTimeout
        interval: 30000
        onTriggered: {
            root.pendingText = "";
            root.sendError = qsTr("Couldn't confirm the message was sent. Check the conversation before sending again.");
        }
    }

    Connections {
        target: Sms

        function onMessageSent(recipient, timestamp) {
            if (root.pendingText !== "" && Logic.sameNumber(recipient, root.recipientNumber)) {
                sendTimeout.stop();
                if (input.text.trim() === root.pendingText)
                    input.text = "";
                root.pendingText = "";
            }
            root.load();
        }

        function onSendFailed(recipient, reason) {
            if (root.pendingText === "" || (recipient !== "" && !Logic.sameNumber(recipient, root.recipientNumber)))
                return;
            console.warn("Messages: send failed:", reason);
            sendTimeout.stop();
            root.pendingText = "";
            root.sendError = root.failureText(reason);
        }

        function onMessageReceived(sender, text, timestamp) {
            if (Logic.sameNumber(sender, root.recipientNumber)) {
                root.load();
                Sms.markAsRead(root.conversation.id);
            }
        }
    }

    SilicaListView {
        id: view
        objectName: "messageList"
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            bottom: composer.top
        }
        clip: true
        model: root.messages

        header: PageHeader {
            title: root.contactName || Logic.formatNumber(root.recipientNumber)
            description: root.contactName ? Logic.formatNumber(root.recipientNumber) : ""
        }

        PullDownMenu {
            MenuItem {
                objectName: "addContactItem"
                visible: root.contactName === ""
                text: qsTr("Add to contacts")
                onClicked: {
                    const dialog = pageStack.push(Qt.resolvedUrl("AddContactDialog.qml"), { number: root.recipientNumber });
                    dialog.accepted.connect(() => root.contactName = dialog.name);
                }
            }
            MenuItem {
                objectName: "callItem"
                text: qsTr("Call")
                onClicked: Navigation.launchAppWithRoute("phone", "/call", JSON.stringify({ number: root.recipientNumber }))
            }
        }

        ViewPlaceholder {
            enabled: view.count === 0
            text: qsTr("No messages yet")
            hintText: qsTr("Write a message below")
        }

        delegate: MessageBubble {
            required property var modelData

            width: view.width
            message: modelData
            onDeleteRequested: {
                Sms.deleteMessage(modelData.id);
                root.load();
            }
        }

        VerticalScrollDecorator {}
    }

    Column {
        id: composer
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }

        Label {
            objectName: "noModem"
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            visible: !root.hasModem
            text: qsTr("No SIM — messages can't be sent")
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryHighlightColor
        }

        Label {
            objectName: "sendStatus"
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            visible: text !== ""
            text: root.sendError !== "" ? root.sendError : root.pendingText !== "" ? qsTr("Sending…") : ""
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeExtraSmall
            color: root.sendError !== "" ? Theme.errorColor : Theme.secondaryHighlightColor
        }

        Item {
            width: parent.width
            height: Math.max(input.height, sendButton.height)

            TextArea {
                id: input

                readonly property var sms: Logic.smsLength(text)

                objectName: "messageField"
                anchors {
                    left: parent.left
                    right: sendButton.left
                    verticalCenter: parent.verticalCenter
                }
                height: Math.min(implicitHeight, root.height / 3)
                placeholderText: qsTr("Type message")
                label: text === "" ? qsTr("SMS") : sms.parts > 1 ? qsTr("SMS (%1) · %2/%3").arg(sms.parts).arg(sms.used).arg(sms.limit) : qsTr("SMS · %1/%2").arg(sms.used).arg(sms.limit)
                EnterKey.enabled: root.canSend
                EnterKey.iconSource: "image://theme/icon-m-send"
                EnterKey.onClicked: root.send()
                onTextChanged: root.app.setDraft(root.conversation.id, text)
            }

            IconButton {
                id: sendButton
                objectName: "sendButton"
                anchors {
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin - Theme.paddingMedium
                    bottom: parent.bottom
                    bottomMargin: Theme.paddingLarge
                }
                enabled: root.canSend
                icon.source: "image://theme/icon-m-send"
                Accessible.name: root.sendError !== "" ? qsTr("Retry") : qsTr("Send")
                Accessible.description: root.hasModem ? "" : qsTr("No SIM — messages can't be sent")
                onClicked: root.send()
            }
        }
    }
}
