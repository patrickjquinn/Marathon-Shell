import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Lists
import MarathonUI.Core

Rectangle {
    id: historyPage
    color: MColors.backgroundDark
    
    signal historySelected(string url)
    signal clearHistory()
    
    property var history: []
    
    function getDateGroup(timestamp) {
        var now = Date.now()
        var diff = now - timestamp
        var dayMs = 24 * 60 * 60 * 1000
        
        if (diff < dayMs) return "Today"
        if (diff < dayMs * 2) return "Yesterday"
        if (diff < dayMs * 7) return "This Week"
        return "Older"
    }
    
    function groupHistoryByDate() {
        var groups = {
            "Today": [],
            "Yesterday": [],
            "This Week": [],
            "Older": []
        }
        
        for (var i = 0; i < history.length; i++) {
            var item = history[i]
            var group = getDateGroup(item.timestamp)
            groups[group].push(item)
        }
        
        return groups
    }
    
    Column {
        anchors.fill: parent
        
        ListView {
            id: historyList
            width: parent.width
            height: parent.height - clearButton.height
            clip: true
            
            model: {
                var groups = historyPage.groupHistoryByDate()
                var result = []
                
                var order = ["Today", "Yesterday", "This Week", "Older"]
                for (var i = 0; i < order.length; i++) {
                    var groupName = order[i]
                    if (groups[groupName].length > 0) {
                        result.push({ type: "header", title: groupName })
                        for (var j = 0; j < groups[groupName].length; j++) {
                            result.push({ type: "item", data: groups[groupName][j] })
                        }
                    }
                }
                
                return result
            }
            
            delegate: Item {
                width: historyList.width
                height: modelData.type === "header" ? Constants.touchTargetSmall : (Constants.touchTargetLarge + Constants.spacingXSmall)
                
                MSectionHeader {
                    visible: modelData.type === "header"
                    anchors.fill: parent
                    title: modelData.title || ""
                }
                
                SettingsListItem {
                    visible: modelData.type === "item"
                    anchors.fill: parent
                    title: modelData.data ? (modelData.data.title || modelData.data.url) : ""
                    subtitle: modelData.data ? modelData.data.url : ""
                    iconName: "clock"
                    showChevron: true
                    value: modelData.data ? (modelData.data.visitCount > 1 ? modelData.data.visitCount + " visits" : "") : ""
                    
                    onSettingClicked: {
                        if (modelData.data) {
                            Logger.info("HistoryPage", "History clicked: " + modelData.data.url)
                            historyPage.historySelected(modelData.data.url)
                        }
                    }
                }
            }
            
            Text {
                visible: historyPage.history.length === 0
                anchors.centerIn: parent
                text: "No history yet"
                font.pixelSize: Constants.fontSizeLarge
                color: MColors.textTertiary
            }
        }
        
        Rectangle {
            id: clearButton
            width: parent.width
            height: Constants.touchTargetMedium + Constants.spacingMedium * 2
            color: MColors.surface
            visible: historyPage.history.length > 0
            
            Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: Constants.borderWidthThin
                color: MColors.border
            }
            
            Row {
                anchors.centerIn: parent
                spacing: Constants.spacingSmall
                
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "trash-2"
                    size: Constants.iconSizeSmall
                    color: MColors.error
                }
                
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Clear History"
                    font.pixelSize: Constants.fontSizeMedium
                    font.weight: Font.DemiBold
                    color: MColors.error
                }
            }
            
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    HapticService.light()
                    historyPage.clearHistory()
                }
            }
        }
    }
}
