import QtQuick
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import MarathonUI.Containers

Item {
    id: root

    property var message
    property bool isOutgoing: message?.isOutgoing || false
    property bool showTimestamp: true
    property bool isFirstInGroup: false
    property bool isLastInGroup: false

    width: parent.width
    height: bubbleContainer.height + MSpacing.xs

    Column {
        id: bubbleContainer
        anchors.left: isOutgoing ? undefined : parent.left
        anchors.right: isOutgoing ? parent.right : undefined
        anchors.leftMargin: MSpacing.md
        anchors.rightMargin: MSpacing.md
        spacing: MSpacing.xs

        Rectangle {
            id: bubble
            width: Math.min(bubbleText.contentWidth + MSpacing.md * 2, root.width * 0.75)
            height: bubbleText.contentHeight + MSpacing.md * 2
            radius: MRadius.lg
            color: isOutgoing ? MColors.marathonTeal : MColors.elevated
            border.width: isOutgoing ? 0 : 1
            border.color: MColors.border

            MLabel {
                id: bubbleText
                anchors.fill: parent
                anchors.margins: MSpacing.md
                text: message?.text || ""
                variant: "primary"
                font.pixelSize: MTypography.sizeBody
                color: isOutgoing ? MColors.textPrimary : MColors.textPrimary
                wrapMode: Text.Wrap
            }

            Row {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: MSpacing.xs
                anchors.bottomMargin: MSpacing.xs
                spacing: MSpacing.xs
                visible: isOutgoing

                Icon {
                    name: getStatusIcon()
                    size: 12
                    color: isOutgoing ? MColors.textSecondary : MColors.textTertiary
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        MLabel {
            id: timestampLabel
            visible: showTimestamp
            text: formatMessageTime(message?.timestamp)
            variant: "tertiary"
            font.pixelSize: MTypography.sizeXSmall
            anchors.left: isOutgoing ? undefined : parent.left
            anchors.right: isOutgoing ? parent.right : undefined
        }
    }

    function formatMessageTime(timestamp) {
        if (!timestamp)
            return "";
        var date = new Date(timestamp);
        return date.toLocaleTimeString(Qt.locale(), "h:mm AP");
    }

    function getStatusIcon() {
        if (!message)
            return "check";

        if (message.isFailed)
            return "x";
        if (message.isRead)
            return "check-check";
        if (message.isDelivered)
            return "check-check";
        return "check";
    }
}
