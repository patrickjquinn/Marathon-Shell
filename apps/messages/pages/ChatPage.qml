pragma ComponentBehavior: Bound

import MarathonApp.Messages
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick

Rectangle {
    id: chatPage

    required property var app
    property var conversation
    property var messages: []
    property var groupedMessages: []
    readonly property string recipientNumber: conversation ? (conversation.contactNumber || conversation.id.replace("conv_", "")) : ""
    property string pendingText: ""
    property string sendError: ""

    signal navigateBack

    function send(text) {
        pendingText = text.trim();
        sendError = "";
        sendTimeout.restart();
        SMSService.sendMessage(recipientNumber, pendingText);
    }

    function failureText(reason) {
        if (/modem/i.test(reason))
            return "Message not sent. No mobile network is available. Check that a SIM card is inserted and signal is on.";
        return "Message not sent. Check your mobile signal and try again.";
    }

    function loadMessages() {
        if (!conversation)
            return;

        messages = SMSService.getMessages(conversation.id);
        groupMessages();
    }

    function groupMessages() {
        var groups = [];
        var currentGroup = null;
        var currentDate = null;
        var lastSender = null;
        var lastTime = 0;
        var sortedMessages = messages.slice().reverse();
        for (var i = 0; i < sortedMessages.length; i++) {
            var msg = sortedMessages[i];
            var msgDate = new Date(msg.timestamp);
            var msgDateStr = msgDate.toDateString();
            if (msgDateStr !== currentDate) {
                if (currentGroup)
                    groups.push(currentGroup);

                currentGroup = {
                    "date": msgDate,
                    "showDate": true,
                    "messages": []
                };
                currentDate = msgDateStr;
                lastSender = null;
                lastTime = 0;
            }
            var timeDiff = msg.timestamp - lastTime;
            var isNewGroup = (msg.isOutgoing !== (lastSender === "me")) || (timeDiff > 5 * 60 * 1000);
            if (isNewGroup && currentGroup.messages.length > 0) {
                currentGroup.messages[currentGroup.messages.length - 1].isLast = true;
                currentGroup.messages[currentGroup.messages.length - 1].showTime = true;
            }
            var msgCopy = Object.assign({}, msg);
            msgCopy.isFirst = isNewGroup;
            msgCopy.isLast = false;
            msgCopy.showTime = false;
            currentGroup.messages.push(msgCopy);
            lastSender = msg.isOutgoing ? "me" : msg.sender;
            lastTime = msg.timestamp;
        }
        if (currentGroup && currentGroup.messages.length > 0) {
            currentGroup.messages[currentGroup.messages.length - 1].isLast = true;
            currentGroup.messages[currentGroup.messages.length - 1].showTime = true;
            groups.push(currentGroup);
        }
        groupedMessages = groups;
    }

    function scrollToBottom() {
        messagesList.positionViewAtBeginning();
    }

    color: MColors.background
    Component.onCompleted: {
        loadMessages();
        if (conversation) {
            SMSService.markAsRead(conversation.id);
            messageInputBar.text = chatPage.app.drafts[conversation.id] || "";
        }
    }

    Timer {
        id: sendTimeout
        interval: 30000
        onTriggered: {
            chatPage.pendingText = "";
            chatPage.sendError = "Couldn't confirm the message was sent. Check the conversation before sending again.";
        }
    }

    Connections {
        function onMessageSent(recipient, timestamp) {
            if (chatPage.pendingText !== "" && MPhoneNumber.sameNumber(recipient, chatPage.recipientNumber)) {
                sendTimeout.stop();
                if (messageInputBar.text.trim() === chatPage.pendingText)
                    messageInputBar.text = "";
                chatPage.pendingText = "";
            }
            if (chatPage.conversation)
                chatPage.loadMessages();
        }

        function onSendFailed(recipient, reason) {
            if (chatPage.pendingText === "" || (recipient !== "" && !MPhoneNumber.sameNumber(recipient, chatPage.recipientNumber)))
                return;
            Logger.warn("Messages", "Send failed: " + reason);
            sendTimeout.stop();
            chatPage.pendingText = "";
            chatPage.sendError = chatPage.failureText(reason);
        }

        function onMessageReceived(sender, text, timestamp) {
            if (chatPage.conversation && MPhoneNumber.sameNumber(sender, chatPage.conversation.contactNumber)) {
                chatPage.loadMessages();
                chatPage.scrollToBottom();
            }
        }

        target: SMSService
    }

    function contactMonogram() {
        const n = (conversation && conversation.contactName) || (conversation && conversation.contactNumber) || "?";
        const parts = n.split(/\s+/).filter(p => p.length > 0);
        if (parts.length === 0)
            return "·";
        if (parts.length === 1)
            return parts[0].substring(0, 2).toUpperCase();
        return String(parts[0].charAt(0) + parts[parts.length - 1].charAt(0)).toUpperCase();
    }

    Column {
        anchors.fill: parent
        spacing: 0

        MTopBar {
            id: header
            width: parent.width
            title: ""                     // name lives in leadingContent
            showBack: true
            onBackClicked: {
                HapticService.light();
                chatPage.navigateBack();
            }

            leadingContent: [
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36
                    height: 36
                    radius: width / 2
                    color: chatPage.app.tintFor((chatPage.conversation && (chatPage.conversation.contactName || chatPage.conversation.contactNumber)) || "?")
                    border.width: 1
                    border.color: MColors.whiteOverlay08

                    Text {
                        anchors.centerIn: parent
                        text: chatPage.contactMonogram()
                        color: MColors.textPrimary
                        font.family: MTypography.fontFamily
                        font.pixelSize: MTypography.sizeFootnote
                        font.weight: Font.DemiBold
                    }
                },
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    Text {
                        text: (chatPage.conversation && chatPage.conversation.contactName) || (chatPage.conversation && MPhoneNumber.format(chatPage.conversation.contactNumber)) || ""
                        color: MColors.textPrimary
                        font.family: MTypography.fontFamily
                        font.pixelSize: MTypography.sizeHeadline
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    // Presence subtitle — "typing…" teal-bright when the
                    // contact is composing.
                    Text {
                        text: (chatPage.conversation && chatPage.conversation.isTyping) ? "typing…" : ""
                        color: MColors.marathonTealBright
                        font.family: MTypography.fontFamily
                        font.pixelSize: MTypography.sizeEyebrow
                        font.weight: Font.Medium
                        visible: text.length > 0
                    }
                }
            ]
        }

        ListView {
            id: messagesList

            function scrollToBottom() {
                messagesList.positionViewAtBeginning();
            }

            width: parent.width
            height: parent.height - header.height - statusStrip.height - messageInputBar.height
            clip: true
            verticalLayoutDirection: ListView.BottomToTop
            spacing: 0
            topMargin: MSpacing.md
            bottomMargin: MSpacing.md
            model: chatPage.groupedMessages

            MEmptyState {
                visible: messagesList.count === 0
                anchors.centerIn: parent
                width: parent.width - MSpacing.xl * 2
                iconName: "message-circle"
                title: "No messages yet"
                message: "Send a message to start the conversation."
            }

            delegate: Column {
                id: dayGroup

                required property var modelData

                width: messagesList.width
                spacing: 0

                DateSeparator {
                    visible: dayGroup.modelData.showDate
                    messageDate: dayGroup.modelData.date
                    width: parent.width
                }

                Repeater {
                    model: dayGroup.modelData.messages

                    MessageBubble {
                        required property var modelData

                        message: modelData
                        showTimestamp: modelData.showTime
                        isFirstInGroup: modelData.isFirst
                        isLastInGroup: modelData.isLast
                        width: messagesList.width
                    }
                }
            }
        }

        Rectangle {
            id: statusStrip
            width: parent.width
            height: visible ? statusRow.implicitHeight + MSpacing.sm * 2 : 0
            visible: chatPage.sendError !== "" || chatPage.pendingText !== ""
            color: MColors.bb10Elevated

            Row {
                id: statusRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: MSpacing.md
                anchors.rightMargin: MSpacing.sm
                spacing: MSpacing.sm

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - (retryButton.visible ? retryButton.width + parent.spacing : 0)
                    text: chatPage.sendError !== "" ? chatPage.sendError : "Sending…"
                    color: chatPage.sendError !== "" ? MColors.error : MColors.textSecondary
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeFootnote
                    wrapMode: Text.WordWrap
                }
                MButton {
                    id: retryButton
                    anchors.verticalCenter: parent.verticalCenter
                    visible: chatPage.sendError !== "" && messageInputBar.text.trim() !== ""
                    text: "Retry"
                    size: "compact"
                    onClicked: chatPage.send(messageInputBar.text)
                }
            }
        }

        MessageInputBar {
            id: messageInputBar

            width: parent.width
            sending: chatPage.pendingText !== ""
            onTextChanged: if (chatPage.conversation)
                chatPage.app.setDraft(chatPage.conversation.id, text)
            onSendMessage: text => {
                if (chatPage.conversation)
                    chatPage.send(text);
            }
        }
    }
}
