import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import MarathonUI.Containers
import MarathonUI.Navigation
import "../components"

Rectangle {
    id: chatPage
    color: MColors.background

    property var conversation
    property var messages: []
    property var groupedMessages: []

    signal navigateBack

    Component.onCompleted: {
        loadMessages();
        if (typeof SMSService !== 'undefined' && conversation) {
            SMSService.markAsRead(conversation.id);
        }
    }

    Connections {
        target: typeof SMSService !== 'undefined' ? SMSService : null

        function onMessageSent(recipient, timestamp) {
            if (conversation) {
                loadMessages();
            }
        }

        function onMessageReceived(sender, text, timestamp) {
            if (conversation && sender === conversation.contactNumber) {
                loadMessages();
                scrollToBottom();
            }
        }
    }

    Column {
        anchors.fill: parent
        spacing: 0

        MActionBar {
            id: header
            width: parent.width
            showBack: true

            onBackClicked: {
                HapticService.light();
                chatPage.navigateBack();
            }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: header.showBack ? 92 : MSpacing.md
                anchors.verticalCenter: parent.verticalCenter
                spacing: MSpacing.md

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    height: 40
                    radius: 20
                    color: MColors.marathonTeal

                    MLabel {
                        anchors.centerIn: parent
                        text: conversation?.contactName ? conversation.contactName.charAt(0).toUpperCase() : "?"
                        color: MColors.textInverse
                        font.pixelSize: MTypography.sizeBody
                        font.weight: MTypography.weightBold
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    MLabel {
                        text: conversation?.contactName || conversation?.contactNumber || ""
                        variant: "primary"
                        font.pixelSize: MTypography.sizeBody
                        font.weight: MTypography.weightBold
                    }

                    MLabel {
                        text: conversation?.contactNumber || ""
                        variant: "tertiary"
                        font.pixelSize: MTypography.sizeXSmall
                    }
                }
            }
        }

        ListView {
            id: messagesList
            width: parent.width
            height: parent.height - header.height - messageInputBar.height
            clip: true
            verticalLayoutDirection: ListView.BottomToTop
            spacing: 0
            topMargin: MSpacing.md
            bottomMargin: MSpacing.md

            model: groupedMessages

            delegate: Column {
                width: messagesList.width
                spacing: 0

                DateSeparator {
                    visible: modelData.showDate
                    messageDate: modelData.date
                    width: parent.width
                }

                Repeater {
                    model: modelData.messages

                    MessageBubble {
                        message: modelData
                        showTimestamp: modelData.showTime
                        isFirstInGroup: modelData.isFirst
                        isLastInGroup: modelData.isLast
                        width: messagesList.width
                    }
                }
            }

            MEmptyState {
                visible: messagesList.count === 0
                anchors.centerIn: parent
                width: parent.width - MSpacing.xl * 2
                iconName: "message-circle"
                title: "No messages yet"
                message: "Send a message to start the conversation"
            }

            function scrollToBottom() {
                messagesList.positionViewAtBeginning();
            }
        }

        MessageInputBar {
            id: messageInputBar
            width: parent.width

            onSendMessage: text => {
                if (text.trim().length > 0 && conversation) {
                    Logger.info("Messages", "Sending message to: " + conversation.contactName);
                    var recipientNumber = conversation.contactNumber || conversation.id.replace("conv_", "");
                    if (typeof SMSService !== 'undefined') {
                        SMSService.sendMessage(recipientNumber, text.trim());
                    }
                }
            }

            onAttachPressed: {
                Logger.info("Messages", "Attach pressed");
            }
        }
    }

    function loadMessages() {
        if (!conversation)
            return;
        if (typeof SMSService !== 'undefined') {
            messages = SMSService.getMessages(conversation.id);
        } else {
            messages = [];
        }

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
                if (currentGroup) {
                    groups.push(currentGroup);
                }

                currentGroup = {
                    date: msgDate,
                    showDate: true,
                    messages: []
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
}
