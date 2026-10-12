import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Page {
    id: root

    property var store
    property alias tabs: tabs

    // From the cover: Discover, with the search field focused.
    function showSearch() {
        tabs.moveTo(0, PagedView.Immediate);
        if (tabs.currentItem && tabs.currentItem.item)
            tabs.currentItem.item.focusSearch();
    }

    TabView {
        id: tabs

        anchors.fill: parent
        sourceProperty: "page"
        header: TabBar {
            model: tabs.model
        }
        // A ListModel, since TabView's delegate reads the page off `model`,
        // which drops values of a plain JS array.
        model: ListModel {
            Component.onCompleted: {
                append({ title: qsTr("Discover"), page: discoverTab });
                append({ title: qsTr("Apps"), page: appsTab });
                append({ title: qsTr("Installed"), page: installedTab });
            }
        }
    }

    Component {
        id: discoverTab
        DiscoverTab {
            store: root.store
            topMargin: tabs.tabBarHeight
        }
    }
    Component {
        id: appsTab
        AppsTab {
            store: root.store
            topMargin: tabs.tabBarHeight
        }
    }
    Component {
        id: installedTab
        InstalledTab {
            store: root.store
            topMargin: tabs.tabBarHeight
        }
    }
}
