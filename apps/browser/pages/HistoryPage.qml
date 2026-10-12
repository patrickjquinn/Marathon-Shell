pragma ComponentBehavior: Bound

import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

Rectangle {
    id: historyPage

    property var history: []

    signal historySelected(string url)
    signal clearHistory

    function getDateGroup(timestamp) {
        var now = Date.now();
        var diff = now - timestamp;
        var dayMs = 24 * 60 * 60 * 1000;
        if (diff < dayMs)
            return "Today";

        if (diff < dayMs * 2)
            return "Yesterday";

        if (diff < dayMs * 7)
            return "This Week";

        return "Older";
    }

    function groupHistoryByDate() {
        var groups = {
            "Today": [],
            "Yesterday": [],
            "This Week": [],
            "Older": []
        };
        for (var i = 0; i < history.length; i++) {
            var item = history[i];
            var group = getDateGroup(item.timestamp);
            groups[group].push(item);
        }
        return groups;
    }

    color: MColors.background

    // Outside the ListView: its children are reparented onto the unbounded contentItem.
    MEmptyState {
        anchors.centerIn: parent
        width: parent.width - MSpacing.lg * 2
        visible: historyPage.history.length === 0
        iconName: "clock"
        title: "No history yet"
        message: "Pages you visit show up here."
    }

    Column {
        anchors.fill: parent

        ListView {
            id: historyList

            width: parent.width
            height: parent.height - clearButton.height
            clip: true
            model: {
                var groups = historyPage.groupHistoryByDate();
                var result = [];
                var order = ["Today", "Yesterday", "This Week", "Older"];
                for (var i = 0; i < order.length; i++) {
                    var groupName = order[i];
                    if (groups[groupName].length > 0) {
                        result.push({
                            "type": "header",
                            "title": groupName
                        });
                        for (var j = 0; j < groups[groupName].length; j++) {
                            result.push({
                                "type": "item",
                                "data": groups[groupName][j]
                            });
                        }
                    }
                }
                return result;
            }

            delegate: Item {
                id: historyDelegate

                required property var modelData

                width: historyList.width
                height: historyDelegate.modelData.type === "header" ? Constants.touchTargetSmall : (Constants.touchTargetLarge + MSpacing.xs)

                MSectionHeader {
                    visible: historyDelegate.modelData.type === "header"
                    anchors.fill: parent
                    text: historyDelegate.modelData.title || ""
                }

                MSettingsListItem {
                    visible: historyDelegate.modelData.type === "item"
                    width: parent.width
                    height: parent.height
                    title: historyDelegate.modelData.data ? (historyDelegate.modelData.data.title || historyDelegate.modelData.data.url) : ""
                    subtitle: historyDelegate.modelData.data ? historyDelegate.modelData.data.url : ""
                    iconName: "clock"
                    showChevron: true
                    value: historyDelegate.modelData.data ? (historyDelegate.modelData.data.visitCount > 1 ? historyDelegate.modelData.data.visitCount + " visits" : "") : ""
                    onSettingClicked: {
                        if (historyDelegate.modelData.data) {
                            Logger.info("HistoryPage", "History clicked: " + historyDelegate.modelData.data.url);
                            historyPage.historySelected(historyDelegate.modelData.data.url);
                        }
                    }
                }
            }
        }

        Rectangle {
            id: clearButton

            width: parent.width
            height: Constants.touchTargetMedium + MSpacing.md * 2
            color: MColors.surface
            visible: historyPage.history.length > 0

            Accessible.role: Accessible.Button
            Accessible.name: "Clear History"
            Accessible.onPressAction: historyPage.clearHistory()

            Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: Constants.borderWidthThin
                color: MColors.border
            }

            Row {
                anchors.centerIn: parent
                spacing: MSpacing.sm

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "trash-2"
                    size: Constants.iconSizeSmall
                    color: MColors.error
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Clear History"
                    font.pixelSize: MTypography.sizeBody
                    font.weight: Font.DemiBold
                    color: MColors.error
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    HapticService.light();
                    historyPage.clearHistory();
                }
            }
        }
    }
}
