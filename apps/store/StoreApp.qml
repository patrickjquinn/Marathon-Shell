import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

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
            onDepthChanged: {
                root.navigationDepth = depth - 1;
            }

            Connections {
                function onBackPressed() {
                    if (navigationStack.depth > 1)
                        navigationStack.pop();
                }

                target: root
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
    }
}
