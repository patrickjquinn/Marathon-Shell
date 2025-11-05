import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Core
import "../components"

Rectangle {
    id: tabsPage
    color: MColors.background
    
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
            height: parent.height - (Constants.touchTargetSmall + MSpacing.md)
            
            ListView {
                id: tabsList
                anchors.fill: parent
                clip: true
                spacing: MSpacing.md
                
                model: tabsPage.tabs
                
                delegate: Item {
                    width: tabsList.width
                    height: Constants.cardHeight + MSpacing.md
                    
                    TabCard {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - MSpacing.lg * 2
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
                
                header: Item { height: MSpacing.md }
                footer: Item { height: MSpacing.md }
            }
            
            Text {
                visible: tabsPage.tabs.length === 0
                anchors.centerIn: parent
                text: "No open tabs"
                font.pixelSize: MTypography.sizeLarge
                color: MColors.textTertiary
            }
        }
        
        Rectangle {
            width: parent.width
            height: Constants.touchTargetSmall + MSpacing.md
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
                spacing: MSpacing.sm
                
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "plus"
                    size: Constants.iconSizeSmall
                    color: tabsPage.tabs.length >= 20 ? MColors.textTertiary : MColors.accent
                }
                
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: tabsPage.tabs.length >= 20 ? "Tab Limit Reached" : "New Tab"
                    font.pixelSize: MTypography.sizeBody
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

