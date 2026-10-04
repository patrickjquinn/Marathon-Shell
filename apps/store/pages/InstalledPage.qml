import MarathonApp.Store
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

// Pending updates first, then everything installed from Flathub.
Flickable {
    id: page

    required property var store

    contentWidth: width
    contentHeight: column.height + MSpacing.xl
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    Component.onCompleted: store.refreshState()

    Column {
        id: column
        width: page.width
        topPadding: page.store.dp(14)
        spacing: MSpacing.xl

        Column {
            width: parent.width
            spacing: page.store.dp(10)
            visible: page.store.updateApps.length > 0

            SectionHeader {
                width: parent.width
                title: "Updates"
                subtitle: page.store.updateApps.length === 1 ? "1 app" : page.store.updateApps.length + " apps"
                actionText: "Update all"
                onActionClicked: page.store.updateAll()
            }
            AppListCard {
                x: MSpacing.md
                width: parent.width - MSpacing.md * 2
                store: page.store
                model: page.store.updateApps
            }
        }

        Column {
            width: parent.width
            spacing: page.store.dp(10)
            visible: page.store.installedApps.length > 0

            SectionHeader {
                width: parent.width
                title: "On this phone"
                subtitle: page.store.installedApps.length === 1 ? "1 app" : page.store.installedApps.length + " apps"
            }
            AppListCard {
                x: MSpacing.md
                width: parent.width - MSpacing.md * 2
                store: page.store
                model: page.store.installedApps
            }
        }
    }

    MEmptyState {
        anchors.centerIn: parent
        width: parent.width - MSpacing.xxl
        visible: page.store.installedApps.length === 0
        iconName: "download"
        iconSize: page.store.dp(64)
        title: "No apps installed yet"
        message: "Apps you get from the Store appear here, with their updates."
    }
}
