import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

// ─────────────────────────────────────────────────────────────────────
//  App Store — current state vs DS target
// ─────────────────────────────────────────────────────────────────────
//
//  StoreFrontPage matches the JSX layout (screens-apps-2.jsx:StoreDiscover):
//  MTopBar + avatar, Editors' Pick hero card, Trending-now 3-up tiles,
//  Updates-available rows, Discover / Apps / Installed / Account tabs.
//
//  HOWEVER all surface content (featured pick, trending apps, updates
//  list) is currently HARDCODED in StoreFrontPage.qml — there is no
//  app-discovery backend yet. A real Store needs:
//    • Catalog API (signed manifests, screenshots, ratings, versions)
//    • Featured / Editorial pipeline
//    • Update check + delta-package distribution
//    • Sandboxed install hooks (already partially in MarathonAppInstaller)
//
//  Treat this file as a visual specimen until that infra lands. The DS
//  chrome is right; the data is placeholder.
// ─────────────────────────────────────────────────────────────────────

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
