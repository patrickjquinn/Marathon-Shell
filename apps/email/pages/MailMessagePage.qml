pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../MailLogic.js" as Logic

Page {
    id: page

    property var app
    property string messageId: ""
    readonly property var msg: messageId !== "" ? app.mail.openMessage(messageId) : ({})
    readonly property string subject: msg.subject || ""
    readonly property var toList: msg.to || []
    readonly property var ccList: msg.cc || []
    readonly property string dateText: msg.date ? Qt.formatDateTime(msg.date, Qt.locale().dateTimeFormat(Locale.ShortFormat)) : ""
    readonly property string bodyHtml: msg.bodyHtml || ""
    readonly property string bodyPlain: msg.bodyPlain || ""
    readonly property var attachments: msg.attachments || []
    property var savedPaths: ({})
    // Location of the attachment being fetched, and whether to open it after.
    property string fetching: ""
    property bool openWhenSaved: false

    function openAttachment(location) {
        if (savedPaths[location]) {
            Qt.openUrlExternally("file://" + savedPaths[location]);
            return;
        }
        saveAttachment(location, true);
    }

    function saveAttachment(location, open) {
        if (fetching !== "")
            return;
        if (!app.mail.saveAttachment(messageId, location)) {
            Notices.show(qsTr("Couldn't save the attachment."));
            return;
        }
        fetching = location;
        openWhenSaved = open;
    }

    function size(bytes) {
        return bytes >= 1048576 ? qsTr("%1 MB").arg((bytes / 1048576).toFixed(1)) : qsTr("%1 kB").arg(Math.max(1, Math.round(bytes / 1024)));
    }

    Connections {
        target: page.app.mail
        ignoreUnknownSignals: true
        function onAttachmentSaved(messageId, location, path) {
            if (messageId !== page.messageId || location !== page.fetching)
                return;
            page.fetching = "";
            page.savedPaths = Object.assign({}, page.savedPaths, { [location]: path });
            if (page.openWhenSaved)
                Qt.openUrlExternally("file://" + path);
            else
                Notices.show(qsTr("Saved to Downloads"));
        }
        function onAttachmentFailed(messageId, location) {
            if (messageId !== page.messageId || location !== page.fetching)
                return;
            page.fetching = "";
            Notices.show(qsTr("Couldn't download the attachment. Check your connection and try again."));
        }
    }

    SilicaFlickable {
        id: flick

        objectName: "messageFlick"
        anchors.fill: parent
        // The HTML view scrolls itself, so it takes the rest of the page.
        contentHeight: column.height + (page.bodyHtml !== "" ? Math.max(0, page.height - column.height) : Theme.paddingLarge)

        PullDownMenu {
            MenuItem {
                objectName: "deleteItem"
                text: qsTr("Delete")
                onClicked: page.app.requestMove(page.messageId, "trash")
            }
            MenuItem {
                objectName: "archiveItem"
                text: qsTr("Archive")
                onClicked: page.app.requestMove(page.messageId, "archive")
            }
            MenuItem {
                objectName: "forwardItem"
                text: qsTr("Forward")
                onClicked: page.app.compose(Object.assign(Logic.forwardPrefill(page.msg, page.dateText), { draftKey: "forward-" + page.messageId }))
            }
            MenuItem {
                objectName: "replyItem"
                text: qsTr("Reply")
                onClicked: page.app.compose(Object.assign(Logic.replyPrefill(page.msg), { draftKey: "reply-" + page.messageId }))
            }
        }

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: page.subject !== "" ? page.subject : qsTr("(No subject)")
                wrapMode: Text.Wrap
            }
            Label {
                objectName: "fromLabel"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: text !== ""
                text: page.msg.from || ""
                wrapMode: Text.Wrap
                color: Theme.highlightColor
            }
            Label {
                objectName: "toLabel"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: page.toList.length > 0
                text: qsTr("To: %1").arg(page.toList.join(", "))
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
            }
            Label {
                objectName: "ccLabel"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: page.ccList.length > 0
                text: qsTr("Cc: %1").arg(page.ccList.join(", "))
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: text !== ""
                text: page.dateText
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryHighlightColor
            }

            Column {
                objectName: "attachments"
                width: parent.width
                visible: page.attachments.length > 0

                SectionHeader {
                    text: page.attachments.length === 1 ? qsTr("1 attachment") : qsTr("%1 attachments").arg(page.attachments.length)
                }
                Repeater {
                    model: page.attachments

                    ListItem {
                        id: attachment

                        required property var modelData
                        readonly property string location: modelData.location || ""
                        readonly property bool busy: page.fetching !== "" && page.fetching === location

                        objectName: "attachment-" + (modelData.name || "")
                        contentHeight: Theme.itemSizeSmall
                        enabled: location !== ""
                        Accessible.name: (modelData.name || qsTr("Attachment")) + ", " + page.size(modelData.size || 0)
                        onClicked: page.openAttachment(location)
                        menu: ContextMenu {
                            MenuItem {
                                objectName: "saveItem"
                                text: qsTr("Save to Downloads")
                                onClicked: page.saveAttachment(attachment.location, false)
                            }
                        }

                        Icon {
                            id: attachIcon

                            x: Theme.horizontalPageMargin
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !attachment.busy
                            source: "image://theme/icon-s-attach"
                            color: attachment.highlighted ? Theme.highlightColor : Theme.primaryColor
                        }
                        BusyIndicator {
                            anchors.centerIn: attachIcon
                            size: BusyIndicatorSize.ExtraSmall
                            running: attachment.busy
                        }
                        Label {
                            anchors {
                                left: attachIcon.right
                                leftMargin: Theme.paddingMedium
                                right: sizeLabel.left
                                rightMargin: Theme.paddingMedium
                                verticalCenter: parent.verticalCenter
                            }
                            text: attachment.modelData.name || qsTr("Attachment")
                            truncationMode: TruncationMode.Fade
                            font.pixelSize: Theme.fontSizeSmall
                            color: attachment.highlighted ? Theme.highlightColor : Theme.primaryColor
                        }
                        Label {
                            id: sizeLabel

                            anchors {
                                right: parent.right
                                rightMargin: Theme.horizontalPageMargin
                                verticalCenter: parent.verticalCenter
                            }
                            text: page.size(attachment.modelData.size || 0)
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: attachment.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                        }
                    }
                }
            }

            Separator {
                width: parent.width
                color: Theme.primaryColor
                horizontalAlignment: Qt.AlignHCenter
            }
            Item {
                width: parent.width
                height: Theme.paddingLarge
            }
            Label {
                objectName: "plainBody"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: page.bodyHtml === ""
                text: page.bodyPlain !== "" ? page.bodyPlain : qsTr("This message has no text.")
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: page.bodyPlain !== "" ? Theme.primaryColor : Theme.secondaryHighlightColor
            }
        }

        Loader {
            objectName: "htmlBody"
            y: column.height
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            height: Math.max(0, page.height - column.height)
            active: page.bodyHtml !== ""
            source: "MailHtmlBody.qml"
            onLoaded: item.html = Qt.binding(() => page.bodyHtml)
        }

        VerticalScrollDecorator {}
    }
}
