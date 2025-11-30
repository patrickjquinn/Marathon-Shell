import QtQuick
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import MarathonUI.Containers
import MarathonUI.Feedback

Item {
    id: root

    property var conversation
    property bool isUnread: conversation?.unreadCount > 0

    signal conversationClicked
    signal conversationDeleted

    width: parent ? parent.width : 0
    height: 80

    Behavior on scale {
        NumberAnimation {
            duration: MMotion.fast
            easing.bezierCurve: MMotion.easingStandardCurve
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: MSpacing.xs
        color: isUnread ? Qt.rgba(0.24, 0.82, 0.73, 0.1) : MColors.surface
        radius: MRadius.lg
        border.width: isUnread ? 1 : 0
        border.color: Qt.rgba(0.24, 0.82, 0.73, 0.3)

        Behavior on color {
            ColorAnimation {
                duration: MMotion.fast
            }
        }

        Behavior on border.color {
            ColorAnimation {
                duration: MMotion.fast
            }
        }

        Row {
            anchors.fill: parent
            anchors.margins: MSpacing.md
            spacing: MSpacing.md

            Rectangle {
                id: avatar
                anchors.verticalCenter: parent.verticalCenter
                width: 48
                height: 48
                radius: width / 2
                color: MColors.marathonTeal

                MLabel {
                    anchors.centerIn: parent
                    text: conversation?.contactName ? conversation.contactName.charAt(0).toUpperCase() : "?"
                    font.pixelSize: MTypography.sizeLarge
                    font.weight: MTypography.weightBold
                }

                Rectangle {
                    visible: isUnread && conversation?.unreadCount > 0
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: -4
                    anchors.topMargin: -4
                    width: 20
                    height: 20
                    radius: 10
                    color: MColors.error

                    Text {
                        anchors.centerIn: parent
                        text: conversation?.unreadCount > 9 ? "9+" : (conversation?.unreadCount.toString() || "")
                        font.pixelSize: MTypography.sizeXSmall
                        font.weight: MTypography.weightBold
                        font.family: MTypography.fontFamily
                    }
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - avatar.width - timestampLabel.width - parent.spacing * 2 - MSpacing.md
                spacing: MSpacing.xs

                MLabel {
                    text: conversation?.contactName || conversation?.contactNumber || "Unknown"
                    font.pixelSize: MTypography.sizeBody
                    font.weight: isUnread ? MTypography.weightBold : MTypography.weightMedium
                    elide: Text.ElideRight
                    width: parent.width
                }

                MLabel {
                    text: conversation?.lastMessage || "No messages yet"
                    variant: isUnread ? "secondary" : "tertiary"
                    font.pixelSize: MTypography.sizeSmall
                    font.weight: isUnread ? MTypography.weightMedium : MTypography.weightRegular
                    elide: Text.ElideRight
                    width: parent.width
                    maximumLineCount: 1
                }
            }

            MLabel {
                id: timestampLabel
                anchors.verticalCenter: parent.verticalCenter
                text: formatTimestamp(conversation?.lastTimestamp || Date.now())
                variant: isUnread ? "secondary" : "tertiary"
                font.pixelSize: MTypography.sizeXSmall
                font.weight: isUnread ? MTypography.weightDemiBold : MTypography.weightRegular
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onPressed: {
            root.scale = 0.98;
            HapticService.light();
        }
        onReleased: {
            root.scale = 1.0;
        }
        onCanceled: {
            root.scale = 1.0;
        }
        onClicked: {
            root.conversationClicked();
        }
    }

    function formatTimestamp(timestamp) {
        if (!timestamp)
            return "";

        var now = Date.now();
        var diff = now - timestamp;
        var date = new Date(timestamp);
        var today = new Date();

        if (diff < 1000 * 60) {
            return "Now";
        } else if (diff < 1000 * 60 * 60) {
            var mins = Math.floor(diff / (1000 * 60));
            return mins + "m";
        } else if (date.toDateString() === today.toDateString()) {
            return date.toLocaleTimeString(Qt.locale(), "h:mm AP");
        } else if (diff < 1000 * 60 * 60 * 24 * 7) {
            var days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
            return days[date.getDay()];
        } else {
            return date.toLocaleDateString(Qt.locale(), "M/d/yy");
        }
    }
}
