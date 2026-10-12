pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

CoverBackground {
    id: cover

    property bool available: false
    property int unread: 0
    property string sender: ""

    signal newMessageRequested

    CoverPlaceholder {
        objectName: "coverPlaceholder"
        visible: !cover.available
        text: qsTr("Mail")
        icon.source: "image://theme/icon-m-mail"
    }

    Column {
        objectName: "coverContent"
        x: Theme.paddingLarge
        y: Theme.paddingMedium
        width: parent.width - 2 * Theme.paddingLarge
        visible: cover.available

        Label {
            objectName: "unreadCount"
            text: cover.unread
            font.pixelSize: Theme.fontSizeHuge
            color: cover.unread > 0 ? Theme.highlightColor : Theme.primaryColor
        }
        Label {
            width: parent.width
            text: qsTr("Unread", "", cover.unread)
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeMedium
        }
        Label {
            objectName: "latestSender"
            width: parent.width
            topPadding: Theme.paddingMedium
            visible: text !== ""
            text: cover.sender
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeMedium
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
