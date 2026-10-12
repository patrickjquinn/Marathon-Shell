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

    function size(bytes) {
        return bytes >= 1048576 ? qsTr("%1 MB").arg((bytes / 1048576).toFixed(1)) : qsTr("%1 kB").arg(Math.max(1, Math.round(bytes / 1024)));
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
                onClicked: page.app.compose(Logic.forwardPrefill(page.msg, page.dateText))
            }
            MenuItem {
                objectName: "replyItem"
                text: qsTr("Reply")
                onClicked: page.app.compose(Logic.replyPrefill(page.msg))
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

                    Item {
                        id: attachment

                        required property var modelData

                        width: parent.width
                        height: Theme.itemSizeExtraSmall

                        Icon {
                            id: attachIcon

                            x: Theme.horizontalPageMargin
                            anchors.verticalCenter: parent.verticalCenter
                            source: "image://theme/icon-s-attach"
                            color: Theme.highlightColor
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
                            color: Theme.highlightColor
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
                            color: Theme.secondaryHighlightColor
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
