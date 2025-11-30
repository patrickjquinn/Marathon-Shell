import QtQuick
import QtQuick.Controls
import MarathonUI.Core
import MarathonUI.Containers
import MarathonUI.Theme
import MarathonOS.Shell
import "./pages"
import "./components"

MApp {
    id: root
    appId: "store"
    appName: "App Store"
    appIcon: "assets/icon.svg"

    content: Rectangle {
        anchors.fill: parent
        color: MColors.background

        StackView {
            id: navigationStack
            anchors.fill: parent
            initialItem: storeFrontPage

            // Update parent's navigationDepth when stack changes
            onDepthChanged: {
                root.navigationDepth = depth - 1;
            }

            // Handle back button
            Connections {
                target: root
                function onBackPressed() {
                    if (navigationStack.depth > 1) {
                        navigationStack.pop();
                    }
                }
            }
        }

        Component {
            id: storeFrontPage
            StoreFrontPage {}
        }

        Component {
            id: appDetailPage
            AppDetailPage {}
        }

        Component {
            id: installedAppsPage
            InstalledAppsPage {}
        }

        Component {
            id: updatesPage
            UpdatesPage {}
        }

        // Refresh catalog on startup
        // Component.onCompleted: {
        //     if (!AppStoreService.catalogLoaded) {
        //         AppStoreService.refreshCatalog();
        //     }
        // }
    }
}
