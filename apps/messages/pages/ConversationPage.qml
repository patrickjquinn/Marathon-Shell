pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import Sailfish.Pickers 1.0
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
    readonly property bool canSend: hasModem && pendingText === "" && (input.text.trim() !== "" || attachments.length > 0)
    property string pendingText: ""
    property string sendError: ""
    // Pictures to send with the text, as MMS: [{contentType, filePath, name}].
    property var attachments: []

    function load() {
        messages = Logic.messageRows(Sms.getMessages(conversation.id));
        view.positionViewAtEnd();
    }

    function send() {
        if (!canSend)
            return;
        if (attachments.length > 0) {
            sendError = "";
            Sms.sendMms([recipientNumber], input.text.trim(), attachments);
            attachments = [];
            input.text = "";
            load();
            return;
        }
        pendingText = input.text.trim();
        sendError = "";
        sendTimeout.restart();
        Sms.sendMessage(recipientNumber, pendingText);
    }

    // A message that failed goes again, with its pictures read back from
    // where Messages stored them, and the failed one goes.
    function retry(message) {
        const parts = (message.attachments || []).map(a => ({
                    contentType: a.contentType,
                    filePath: Sms.openAttachment(a.id, a.name),
                    name: a.name
                }));
        if (parts.some(p => p.filePath === "")) {
            sendError = qsTr("The picture couldn't be read again.");
            return;
        }
        if (parts.length > 0)
            Sms.sendMms([recipientNumber], message.text, parts);
        else
            Sms.sendMessage(recipientNumber, message.text);
        Sms.deleteMessage(message.id);
        load();
    }

    function attach() {
        if (!Sms.mmsAvailable) {
            sendError = qsTr("Pictures go as MMS, which isn't available on this phone.");
            return;
        }
        pageStack.push(pickerComponent);
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

        function onMessageStatusChanged(id, status) {
            root.load();
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
            onRetryRequested: root.retry(modelData)
            onPictureOpened: path => pageStack.push(pictureComponent, { source: "file://" + path })
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

        Flow {
            objectName: "composerAttachments"
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * x
            spacing: Theme.paddingSmall
            visible: root.attachments.length > 0

            Repeater {
                model: root.attachments

                delegate: Item {
                    id: attached

                    required property var modelData
                    required property int index

                    objectName: "composerAttachment-" + modelData.name
                    width: Theme.itemSizeLarge
                    height: width

                    Image {
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: width
                        sourceSize.height: height
                        asynchronous: true
                        source: "file://" + attached.modelData.filePath
                    }

                    IconButton {
                        objectName: "removeAttachment"
                        anchors.top: parent.top
                        anchors.right: parent.right
                        icon.source: "image://theme/icon-m-clear"
                        Accessible.name: qsTr("Remove %1").arg(attached.modelData.name)
                        onClicked: root.attachments = root.attachments.filter((a, i) => i !== attached.index)
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: Math.max(input.height, sendButton.height)

            IconButton {
                id: attachButton

                objectName: "attachButton"
                anchors {
                    left: parent.left
                    leftMargin: Theme.horizontalPageMargin - Theme.paddingMedium
                    bottom: parent.bottom
                    bottomMargin: Theme.paddingLarge
                }
                icon.source: "image://theme/icon-m-attach"
                Accessible.name: qsTr("Attach a picture")
                onClicked: root.attach()
            }

            TextArea {
                id: input

                readonly property var sms: Logic.smsLength(text)

                objectName: "messageField"
                anchors {
                    left: attachButton.right
                    right: sendButton.left
                    verticalCenter: parent.verticalCenter
                }
                height: Math.min(implicitHeight, root.height / 3)
                placeholderText: qsTr("Type message")
                label: root.attachments.length > 0 ? qsTr("MMS") : text === "" ? qsTr("SMS") : sms.parts > 1 ? qsTr("SMS (%1) · %2/%3").arg(sms.parts).arg(sms.used).arg(sms.limit) : qsTr("SMS · %1/%2").arg(sms.used).arg(sms.limit)
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

    Component {
        id: pickerComponent

        ImagePickerPage {
            onSelectedContentPropertiesChanged: {
                const picked = selectedContentProperties;
                root.attachments = root.attachments.concat([{
                        contentType: picked.mimeType,
                        filePath: picked.filePath,
                        name: picked.fileName
                    }]);
            }
        }
    }

    Component {
        id: pictureComponent

        Page {
            property alias source: picture.source

            allowedOrientations: Orientation.All

            Image {
                id: picture

                objectName: "pictureViewer"
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }
        }
    }
}
