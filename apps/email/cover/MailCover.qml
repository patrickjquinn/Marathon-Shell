pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

// The unread count, then the newest message in the inbox.
CoverBackground {
    id: cover

    property bool available: false
    property int unread: 0
    property string sender: ""
    property string subject: ""

    signal newMessageRequested

    CoverPlaceholder {
        objectName: "coverPlaceholder"
        visible: !cover.available
        text: qsTr("No accounts")
        icon.source: "image://theme/icon-l-mail"
    }

    Column {
        objectName: "coverContent"
        x: Theme.paddingLarge
        y: Theme.paddingLarge
        width: parent.width - 2 * Theme.paddingLarge
        visible: cover.available
        spacing: Theme.paddingMedium

        CoverHeadline {
            objectName: "unreadCount"
            width: parent.width
            visible: cover.unread > 0
            value: cover.unread
            label: qsTr("unread")
        }
        Label {
            objectName: "noUnread"
            width: parent.width
            visible: cover.unread === 0
            text: qsTr("No unread mail")
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.secondaryColor
        }
        Column {
            width: parent.width
            visible: cover.sender !== ""

            Label {
                objectName: "latestSender"
                width: parent.width
                text: cover.sender
                truncationMode: TruncationMode.Fade
                font.pixelSize: Theme.fontSizeSmall
            }
            Label {
                objectName: "latestSubject"
                width: parent.width
                visible: text !== ""
                text: cover.subject
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
            }
        }
    }

    CoverActionList {
        enabled: cover.available

        CoverAction {
            objectName: "newMessageAction"
            iconSource: "image://theme/icon-cover-new"
            onTriggered: cover.newMessageRequested()
        }
    }
}
