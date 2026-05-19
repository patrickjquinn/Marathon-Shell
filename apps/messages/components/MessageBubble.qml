import MarathonApp.Messages
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Effects
import MarathonUI.Theme
import QtQuick

// Marathon DS · Thread bubble (screens-apps-1.jsx:ThreadBubble).
//
// Incoming: elev-2 fill, w-04 hairline border, 16 px radius.
// Outgoing: teal-bright gradient fill, black text, inset white highlight.
// Status (✓ / ✓✓ READ / ✓✓ DELIVERED) sits on a row beneath the last
// outgoing bubble — eyebrow size, secondary tint, tabular nums.
Item {
    id: root

    property var message
    property bool isOutgoing: (message && message.isOutgoing) || false
    property bool showTimestamp: true
    property bool isFirstInGroup: false
    property bool isLastInGroup: false

    function statusText() {
        if (!message)
            return "";
        if (message.isFailed)
            return "FAILED";
        if (message.isRead)
            return "READ";
        if (message.isDelivered)
            return "DELIVERED";
        return "SENT";
    }

    function statusGlyph() {
        if (!message)
            return "check";
        if (message.isFailed)
            return "x";
        if (message.isRead || message.isDelivered)
            return "check-check";
        return "check";
    }

    width: parent ? parent.width : 0
    height: bubbleContainer.height + (statusRow.visible ? statusRow.height + 4 : 0) + 4

    Item {
        id: bubbleContainer
        anchors.left: isOutgoing ? undefined : parent.left
        anchors.right: isOutgoing ? parent.right : undefined
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        width: bubble.width
        height: bubble.height

        Rectangle {
            id: bubble

            width: Math.min(bubbleText.contentWidth + 28, root.width * 0.78)
            height: bubbleText.contentHeight + 24
            radius: 16
            color: "transparent"
            border.width: isOutgoing ? 0 : 1
            border.color: MColors.whiteOverlay04

            // Outgoing: teal-bright gradient. Incoming: elev-2 fill.
            gradient: isOutgoing ? outgoingGradient : null
            Gradient {
                id: outgoingGradient
                GradientStop {
                    position: 0
                    color: MColors.marathonTealBright
                }
                GradientStop {
                    position: 1
                    color: MColors.marathonTealDark
                }
            }
            // Use plain color for incoming rather than gradient.
            Component.onCompleted: if (!isOutgoing)
                color = MColors.elev2

            // Inner inset highlight — top arc only, follows bubble radius.
            MTopHairline {
                visible: isOutgoing
                radius: parent.radius
                color: Qt.rgba(1, 1, 1, 0.2)
                lineWidth: 1
            }

            Text {
                id: bubbleText
                anchors.fill: parent
                anchors.margins: 14
                anchors.topMargin: 12
                anchors.bottomMargin: 12
                text: (message && message.text) || ""
                color: isOutgoing ? "#000000" : MColors.textPrimary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeBody
                font.weight: Font.Normal
                wrapMode: Text.Wrap
            }
        }
    }

    // Status row — only under last outgoing bubble.
    Row {
        id: statusRow
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.top: bubbleContainer.bottom
        anchors.topMargin: 4
        spacing: 4
        visible: isOutgoing && root.isLastInGroup && root.showTimestamp

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.statusGlyph()
            size: 10
            color: MColors.textSecondary
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.statusText()
            color: MColors.textSecondary
            font.family: MTypography.fontFamily
            font.pixelSize: MTypography.sizeEyebrow
            font.weight: Font.Medium
            font.letterSpacing: MTypography.trackingEyebrow
            font.capitalization: Font.AllUppercase
        }
    }
}
