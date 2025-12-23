import MarathonApp.Phone
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

Rectangle {
    function formatDuration(seconds) {
        var s = Number(seconds);
        if (!Number.isFinite(s) || s <= 0)
            return "";

        var mins = Math.floor(s / 60);
        var secs = Math.floor(s % 60);
        return mins + ":" + (secs < 10 ? "0" : "") + secs;
    }

    function formatTimestamp(timestamp) {
        var now = Date.now();
        var ts = Number(timestamp);
        if (Number.isFinite(ts) && ts > 0 && ts < 1e+11)
            ts = ts * 1000;

        if (!Number.isFinite(ts) || ts <= 0)
            return "";

        var diff = now - ts;
        if (diff < 1000 * 60 * 60)
            return Math.floor(diff / (1000 * 60)) + "m ago";
        else if (diff < 1000 * 60 * 60 * 24)
            return Math.floor(diff / (1000 * 60 * 60)) + "h ago";
        else
            return Math.floor(diff / (1000 * 60 * 60 * 24)) + "d ago";
    }

    color: MColors.background

    ListView {
        id: historyList

        anchors.fill: parent
        anchors.margins: MSpacing.md
        spacing: MSpacing.sm
        clip: true
        topMargin: MSpacing.md
        model: phoneApp.callHistory

        Text {
            anchors.centerIn: parent
            visible: historyList.count === 0
            text: "No call history"
            font.pixelSize: MTypography.sizeLarge
            color: MColors.textSecondary
        }

        delegate: Rectangle {
            width: historyList.width
            height: Constants.touchTargetLarge
            color: MColors.surface
            radius: Constants.borderRadiusSharp
            border.width: Constants.borderWidthThin
            border.color: MColors.border
            antialiasing: Constants.enableAntialiasing

            Row {
                anchors.fill: parent
                anchors.margins: MSpacing.md
                spacing: MSpacing.md

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: (modelData["type"] || modelData.type) === "incoming" ? "phone-incoming" : (modelData["type"] || modelData.type) === "outgoing" ? "phone-outgoing" : "phone-missed"
                    size: Constants.iconSizeMedium
                    color: (modelData["type"] || modelData.type) === "missed" ? MColors.error : MColors.accent
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - parent.spacing * 3 - Constants.iconSizeMedium * 2
                    spacing: MSpacing.xs

                    Text {
                        width: parent.width
                        text: modelData["contactName"] || modelData.contactName || "Unknown"
                        font.pixelSize: MTypography.sizeBody
                        font.weight: Font.DemiBold
                        color: MColors.text
                        elide: Text.ElideRight
                    }

                    Row {
                        spacing: MSpacing.sm

                        Text {
                            text: modelData["number"] || modelData.number || ""
                            font.pixelSize: MTypography.sizeSmall
                            color: MColors.textSecondary
                        }

                        Text {
                            text: "•"
                            font.pixelSize: MTypography.sizeSmall
                            color: MColors.textSecondary
                            visible: Number(modelData["duration"] || modelData.duration) > 0
                        }

                        Text {
                            text: formatDuration(modelData["duration"] || modelData.duration)
                            font.pixelSize: MTypography.sizeSmall
                            color: MColors.textSecondary
                            visible: Number(modelData["duration"] || modelData.duration) > 0
                        }
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: formatTimestamp(modelData["timestamp"] || modelData.timestamp)
                    font.pixelSize: MTypography.sizeSmall
                    color: MColors.textTertiary
                }
            }

            MouseArea {
                anchors.fill: parent
                onPressed: {
                    parent.color = MColors.elevated;
                    HapticService.light();
                }
                onReleased: {
                    parent.color = MColors.surface;
                }
                onCanceled: {
                    parent.color = MColors.surface;
                }
                onClicked: {
                    console.log("Call back:", modelData["number"] || modelData.number || "");
                }
            }
        }
    }
}
