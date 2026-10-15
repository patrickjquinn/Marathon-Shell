pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../MessagesLogic.js" as Logic

// Unread messages lead with their count and the latest of them; otherwise
// the most recent conversations.
CoverBackground {
    id: root

    property var conversations: []
    readonly property int unread: Logic.unreadTotal(conversations)
    readonly property var shown: unread > 0 ? conversations.filter(c => c.unreadCount > 0).slice(0, 1) : conversations.slice(0, 3)

    signal newMessageRequested

    CoverPlaceholder {
        objectName: "coverPlaceholder"
        visible: root.conversations.length === 0
        text: qsTr("No messages")
        icon.source: "image://theme/icon-l-message"
    }

    Column {
        x: Theme.paddingLarge
        y: Theme.paddingLarge
        width: parent.width - 2 * Theme.paddingLarge
        spacing: Theme.paddingMedium

        CoverHeadline {
            objectName: "coverUnread"
            width: parent.width
            visible: root.unread > 0
            value: root.unread
            label: qsTr("unread")
        }

        Repeater {
            objectName: "coverConversations"
            model: root.shown

            Column {
                id: conversation

                required property var modelData

                width: parent.width

                Label {
                    objectName: "coverSender"
                    width: parent.width
                    text: Logic.displayName(conversation.modelData)
                    truncationMode: TruncationMode.Fade
                    font.pixelSize: Theme.fontSizeSmall
                }
                Label {
                    width: parent.width
                    text: conversation.modelData.lastMessage
                    wrapMode: Text.WordWrap
                    maximumLineCount: root.unread > 0 ? 2 : 1
                    elide: Text.ElideRight
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: Theme.secondaryColor
                }
            }
        }
    }

    CoverActionList {
        CoverAction {
            objectName: "newMessageAction"
            iconSource: "image://theme/icon-cover-new"
            onTriggered: root.newMessageRequested()
        }
    }
}
