import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../MessagesLogic.js" as Logic

CoverBackground {
    id: root

    property var conversations: []
    readonly property int unread: Logic.unreadTotal(conversations)
    readonly property var latest: conversations.length > 0 ? conversations[0] : null

    signal newMessageRequested

    CoverPlaceholder {
        objectName: "coverPlaceholder"
        visible: root.latest === null
        text: qsTr("No messages")
        icon.source: "image://theme/icon-l-message"
    }

    Column {
        x: Theme.paddingLarge
        y: Theme.paddingMedium
        width: parent.width - 2 * Theme.paddingLarge
        visible: root.latest !== null
        spacing: Theme.paddingSmall

        Label {
            objectName: "coverUnread"
            width: parent.width
            text: root.unread > 0 ? qsTr("%n unread", "", root.unread) : qsTr("No new messages")
            color: root.unread > 0 ? Theme.highlightColor : Theme.primaryColor
            font.pixelSize: root.unread > 0 ? Theme.fontSizeLarge : Theme.fontSizeMedium
            wrapMode: Text.Wrap
        }
        Label {
            objectName: "coverSender"
            width: parent.width
            text: root.latest ? Logic.displayName(root.latest) : ""
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeMedium
        }
        Label {
            width: parent.width
            text: root.latest ? root.latest.lastMessage : ""
            truncationMode: TruncationMode.Fade
            maximumLineCount: 2
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.secondaryColor
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
