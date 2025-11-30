import QtQuick
import QtQuick.Layouts
import MarathonOS.Shell
import MarathonUI.Theme
import MarathonUI.Core
import MarathonUI.Navigation
import "../pages"

Rectangle {
    id: drawer
    anchors.fill: parent
    color: MColors.background

    signal closed
    signal tabSelected(int tabId)
    signal newTabRequested
    signal bookmarkSelected(string url)
    signal historySelected(string url)

    property int selectedTabIndex: 0
    property alias contentStack: contentStack
    property alias tabsPage: tabsPage
    property alias bookmarksPage: bookmarksPage
    property alias historyPage: historyPage
    property alias settingsPage: settingsPage

    Column {
        anchors.fill: parent
        spacing: 0

        MTabBar {
            id: drawerTabs
            width: parent.width
            activeTab: drawer.selectedTabIndex
            tabs: [
                {
                    label: "Tabs",
                    icon: "layers"
                },
                {
                    label: "Bookmarks",
                    icon: "star"
                },
                {
                    label: "History",
                    icon: "clock"
                },
                {
                    label: "Settings",
                    icon: "settings"
                }
            ]

            onTabSelected: index => {
                drawer.selectedTabIndex = index;
                Logger.info("BrowserDrawer", "Switched to tab: " + index);
            }
        }

        StackLayout {
            id: contentStack
            width: parent.width
            height: parent.height - drawerTabs.height
            currentIndex: drawer.selectedTabIndex

            TabsPage {
                id: tabsPage
                onTabSelected: tabId => drawer.tabSelected(tabId)
                onNewTabRequested: drawer.newTabRequested()
            }

            BookmarksPage {
                id: bookmarksPage
                onBookmarkSelected: url => {
                    drawer.bookmarkSelected(url);
                    drawer.closed();
                }
            }

            HistoryPage {
                id: historyPage
                onHistorySelected: url => {
                    drawer.historySelected(url);
                    drawer.closed();
                }
            }

            BrowserSettingsPage {
                id: settingsPage
            }
        }
    }
}
