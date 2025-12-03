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

    property var tabs: null // ListModel
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
                        tabData: model
                        isCurrentTab: model.tabId === tabsPage.currentTabId

                        onTabClicked: {
                            HapticService.light();
                            tabsPage.tabSelected(model.tabId);
                        }

                        onCloseRequested: {
                            HapticService.light();
                            tabsPage.closeTab(model.tabId);
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
                visible: tabsPage.tabs ? tabsPage.tabs.count === 0 : true
                anchors.centerIn: parent
                title: "No open tabs"
                message: "Tap the button below to create a new tab"
            }
        }

        Rectangle {
            width: parent.width
            height: Constants.touchTargetSmall + MSpacing.md
            color: MColors.surface
            opacity: (tabsPage.tabs && tabsPage.tabs.count >= 20) ? 0.5 : 1.0

            Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: Constants.borderWidthThin
                color: MColors.border
            }

            MButton {
                anchors.centerIn: parent
                text: (tabsPage.tabs && tabsPage.tabs.count >= 20) ? "Tab Limit Reached" : "New Tab"
                iconName: "plus"
                variant: "primary"
                disabled: tabsPage.tabs && tabsPage.tabs.count >= 20

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
