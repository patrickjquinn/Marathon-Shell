import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

ListItem {
    id: root

    property var message
    readonly property bool outgoing: message.isOutgoing
    readonly property real dayHeight: day.visible ? day.implicitHeight : 0
    readonly property real textWidth: width * 0.8 - Theme.horizontalPageMargin

    signal deleteRequested

    contentHeight: dayHeight + body.height + (time.visible ? time.height : 0) + Theme.paddingMedium
    Accessible.name: message.text
    Accessible.description: outgoing ? qsTr("Sent") : qsTr("Received")
    menu: ContextMenu {
        MenuItem {
            objectName: "copyItem"
            text: qsTr("Copy")
            onClicked: Clipboard.text = root.message.text
        }
        MenuItem {
            objectName: "deleteItem"
            text: qsTr("Delete")
            onClicked: root.remorseDelete(() => root.deleteRequested())
        }
    }

    Label {
        id: day
        width: parent.width
        visible: root.message.showDay
        topPadding: Theme.paddingLarge
        bottomPadding: Theme.paddingMedium
        horizontalAlignment: Text.AlignHCenter
        text: Format.formatDate(new Date(root.message.timestamp), Formatter.TimepointSectionRelative)
        font.pixelSize: Theme.fontSizeExtraSmall
        color: Theme.highlightColor
    }

    Label {
        id: body
        objectName: "messageText"
        x: root.outgoing ? parent.width - width - Theme.horizontalPageMargin : Theme.horizontalPageMargin
        y: root.dayHeight + Theme.paddingSmall
        width: Math.min(implicitWidth, root.textWidth)
        text: root.message.text
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        horizontalAlignment: root.outgoing ? Text.AlignRight : Text.AlignLeft
        color: root.outgoing && !root.highlighted ? Theme.primaryColor : Theme.highlightColor
    }

    Label {
        id: time
        anchors.top: body.bottom
        x: root.outgoing ? parent.width - width - Theme.horizontalPageMargin : Theme.horizontalPageMargin
        visible: root.message.showTime
        text: Format.formatDate(new Date(root.message.timestamp), Formatter.TimeValue)
        font.pixelSize: Theme.fontSizeTiny
        color: root.outgoing && !root.highlighted ? Theme.secondaryColor : Theme.secondaryHighlightColor
    }
}
