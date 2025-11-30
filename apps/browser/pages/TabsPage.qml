import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Core
import MarathonUI.Containers
import "../components"

Rectangle {
    id: tabsPage
    color: MColors.background

    signal tabSelected(int tabId)
    signal newTabRequested
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

                        onTabClicked: {
                            HapticService.light();
                            tabsPage.tabSelected(modelData.id);
                        }

                        onCloseRequested: {
                            HapticService.light();
                            tabsPage.closeTab(modelData.id);
                        }
                    }
                }

                header: Item {
                    height: MSpacing.md
                }
                footer: Item {
                    height: MSpacing.md
                }
            }

            MEmptyState {
                visible: tabsPage.tabs.length === 0
                anchors.centerIn: parent
                title: "No open tabs"
                message: "Tap the button below to create a new tab"
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

            MButton {
                anchors.centerIn: parent
                text: tabsPage.tabs.length >= 20 ? "Tab Limit Reached" : "New Tab"
                iconName: "plus"
                variant: "primary"
                disabled: tabsPage.tabs.length >= 20

                onClicked: {
                    tabsPage.newTabRequested();
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 200
                }
            }
        }
    }
}
