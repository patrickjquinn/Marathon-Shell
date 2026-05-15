import MarathonApp.Messages
import MarathonApp.Messages
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

Rectangle {
    id: chatPage

    property var conversation
    property var messages: []
    property var groupedMessages: []

    signal navigateBack

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
        if (conversation)
            SMSService.markAsRead(conversation.id);
    }

    Connections {
        function onMessageSent(recipient, timestamp) {
            if (conversation)
                loadMessages();
        }

        function onMessageReceived(sender, text, timestamp) {
            if (conversation && sender === conversation.contactNumber) {
                loadMessages();
                scrollToBottom();
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
        return (parts[0].charAt(0) + parts[parts.length - 1].charAt(0)).toUpperCase();
    }

    Column {
        anchors.fill: parent
        spacing: 0

        // ── Header — glass-titlebar w/ back + avatar + name+typing
        //              + phone + more (screens-apps-1.jsx:MessagesThread).
        Rectangle {
            id: header
            width: parent.width
            height: 88
            color: MColors.glassTitlebar

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 1
                color: MColors.borderGlass
            }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 12
                spacing: 14

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "chevron-left"
                    size: 24
                    color: MColors.textSecondary

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -10
                        onClicked: {
                            HapticService.light();
                            chatPage.navigateBack();
                        }
                    }
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36
                    height: 36
                    radius: width / 2
                    color: "#3a6b9c"     // tint per contact (stub)
                    border.width: 1
                    border.color: MColors.whiteOverlay08

                    Text {
                        anchors.centerIn: parent
                        text: chatPage.contactMonogram()
                        color: MColors.textPrimary
                        font.family: MTypography.fontFamily
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 24 - 36 - 20 - 22 - parent.spacing * 4
                    spacing: 0

                    Text {
                        text: (conversation && conversation.contactName) || (conversation && conversation.contactNumber) || ""
                        color: MColors.textPrimary
                        font.family: MTypography.fontFamily
                        font.pixelSize: 17
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                        width: parent.width
                    }
                    // Presence subtitle — "typing…" teal-bright when the
                    // contact is composing. Falls back to last-seen text
                    // when wiring lands; stays hidden when unknown.
                    Text {
                        text: (conversation && conversation.isTyping) ? "typing…" : ""
                        color: MColors.marathonTealBright
                        font.family: MTypography.fontFamily
                        font.pixelSize: MTypography.sizeEyebrow
                        font.weight: Font.Medium
                        visible: text.length > 0
                    }
                }

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "phone"
                    size: 20
                    color: MColors.textPrimary

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8
                        onClicked: {
                            HapticService.light();
                            // Hand off to Phone app once TelephonyService
                            // supports cross-app launch.
                        }
                    }
                }

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "ellipsis-vertical"
                    size: 22
                    color: MColors.textSecondary

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8
                        onClicked: HapticService.light()
                    }
                }
            }
        }

        ListView {
            id: messagesList

            function scrollToBottom() {
                messagesList.positionViewAtBeginning();
            }

            width: parent.width
            height: parent.height - header.height - messageInputBar.height
            clip: true
            verticalLayoutDirection: ListView.BottomToTop
            spacing: 0
            topMargin: MSpacing.md
            bottomMargin: MSpacing.md
            model: groupedMessages

            MEmptyState {
                visible: messagesList.count === 0
                anchors.centerIn: parent
                width: parent.width - MSpacing.xl * 2
                iconName: "message-circle"
                title: "No messages yet"
                message: "Send a message to start the conversation"
            }

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
        }

        MessageInputBar {
            id: messageInputBar

            width: parent.width
            onSendMessage: text => {
                if (text.trim().length > 0 && conversation) {
                    Logger.info("Messages", "Sending message to: " + conversation.contactName);
                    var recipientNumber = conversation.contactNumber || conversation.id.replace("conv_", "");
                    SMSService.sendMessage(recipientNumber, text.trim());
                }
            }
            onAttachPressed: {
                Logger.info("Messages", "Attach pressed");
            }
        }
    }
}
