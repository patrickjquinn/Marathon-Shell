import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Core
import "../components"

Rectangle {
    id: tabsPage
    color: MColors.backgroundDark
    
    signal tabSelected(int tabId)
    signal newTabRequested()
    signal closeTab(int tabId)
    
    property var tabs: []
    property int currentTabId: -1
    
    Column {
        anchors.fill: parent
        spacing: 0
        
        Item {
            width: parent.width
            height: parent.height - (Constants.touchTargetSmall + Constants.spacingMedium)
            
            ListView {
                id: tabsList
                anchors.fill: parent
                clip: true
                spacing: Constants.spacingMedium
                
                model: tabsPage.tabs
                
                delegate: Item {
                    width: tabsList.width
                    height: Constants.cardHeight + Constants.spacingMedium
                    
                    TabCard {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - Constants.spacingLarge * 2
                        tabData: modelData
                        isCurrentTab: modelData.id === tabsPage.currentTabId
                        
                        onClicked: {
                            HapticService.light()
                            tabsPage.tabSelected(modelData.id)
                        }
                        
                        onCloseRequested: {
                            HapticService.light()
                            tabsPage.closeTab(modelData.id)
                        }
                    }
                }
                
                header: Item { height: Constants.spacingMedium }
                footer: Item { height: Constants.spacingMedium }
            }
            
            Text {
                visible: tabsPage.tabs.length === 0
                anchors.centerIn: parent
                text: "No open tabs"
                font.pixelSize: Constants.fontSizeLarge
                color: MColors.textTertiary
            }
        }
        
        Rectangle {
            width: parent.width
            height: Constants.touchTargetSmall + Constants.spacingMedium
            color: MColors.surface
            opacity: tabsPage.tabs.length >= 20 ? 0.5 : 1.0
            
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
                    name: "plus"
                    size: Constants.iconSizeSmall
                    color: tabsPage.tabs.length >= 20 ? MColors.textTertiary : MColors.accent
                }
                
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: tabsPage.tabs.length >= 20 ? "Tab Limit Reached" : "New Tab"
                    font.pixelSize: Constants.fontSizeMedium
                    font.weight: Font.DemiBold
                    color: tabsPage.tabs.length >= 20 ? MColors.textTertiary : MColors.accent
                }
            }
            
            MouseArea {
                anchors.fill: parent
                enabled: tabsPage.tabs.length < 20
                onClicked: {
                    HapticService.light()
                    tabsPage.newTabRequested()
                }
            }
            
            Behavior on opacity {
                NumberAnimation { duration: 200 }
            }
        }
    }
}

