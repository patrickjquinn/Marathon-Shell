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

        // NOTE: Components must be declared BEFORE the StackView that references
        // them via initialItem. QML resolves the Component id at parse time of
        // the StackView property, and a forward reference produces an undefined
        // QQmlComponent* that segfaults on instantiation -- see Qt bug fix
        // codereview.qt-project.org/c/qt/qtquickcontrols2/+/223692.
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
    }
}
