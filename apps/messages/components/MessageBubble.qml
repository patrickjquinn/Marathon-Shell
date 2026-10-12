import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Item {
    id: root

    property var message
    readonly property bool outgoing: message.isOutgoing
    readonly property real dayHeight: day.visible ? day.implicitHeight : 0

    implicitHeight: dayHeight + bubble.height + (time.visible ? time.height : 0) + Theme.paddingSmall
    Accessible.role: Accessible.StaticText
    Accessible.name: message.text
    Accessible.description: outgoing ? qsTr("Sent") : qsTr("Received")

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

    Rectangle {
        id: bubble
        x: root.outgoing ? parent.width - width - Theme.horizontalPageMargin : Theme.horizontalPageMargin
        y: root.dayHeight
        width: Math.min(text.implicitWidth, root.width * 0.75) + 2 * Theme.paddingMedium
        height: text.height + 2 * Theme.paddingMedium
        radius: Theme.paddingMedium
        color: root.outgoing ? Theme.rgba(Theme.highlightBackgroundColor, Theme.highlightBackgroundOpacity)
                             : Theme.rgba(Theme.primaryColor, 0.1)

        Label {
            id: text
            x: Theme.paddingMedium
            y: Theme.paddingMedium
            width: Math.min(implicitWidth, root.width * 0.75)
            text: root.message.text
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            color: root.outgoing ? Theme.highlightColor : Theme.primaryColor
        }
    }

    Label {
        id: time
        anchors.top: bubble.bottom
        anchors.topMargin: Theme.paddingSmall / 2
        x: root.outgoing ? parent.width - width - Theme.horizontalPageMargin : Theme.horizontalPageMargin
        visible: root.message.showTime
        text: Format.formatDate(new Date(root.message.timestamp), Formatter.TimeValue)
        font.pixelSize: Theme.fontSizeTiny
        color: Theme.secondaryColor
    }
}
