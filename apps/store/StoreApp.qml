import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

// ─────────────────────────────────────────────────────────────────────
//  App Store — current state vs DS target
// ─────────────────────────────────────────────────────────────────────
//
//  StoreFrontPage matches the JSX layout (screens-apps-2.jsx:StoreDiscover):
//  MTopBar + avatar, Editors' Pick hero card, Trending-now 3-up tiles,
//  Updates-available rows. The four bottom tabs (Discover / Apps /
//  Installed / Account) live here at the app shell so any of them can
//  swap in without losing the home tab's StackView state.
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

    property int currentView: 0       // Discover

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

        // Pane swapper. Each tab gets its own area between the top
        // of the content and the bottom MTabBar; the Discover pane
        // keeps a StackView so drill-downs to AppDetailPage stay
        // intact when the user flips tabs and comes back.
        Item {
            id: paneArea
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: tabBar.top

            // 0: Discover (hero + trending + updates)
            StackView {
                id: navigationStack
                anchors.fill: parent
                visible: root.currentView === 0
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

            // 1: Apps — placeholder until a catalog backend lands.
            Item {
                anchors.fill: parent
                visible: root.currentView === 1
                MEmptyState {
                    anchors.centerIn: parent
                    width: parent.width - 48
                    iconName: "grid"
                    iconSize: 64
                    title: "Browse Apps"
                    message: "The full catalog browser will appear here once a Store backend with signed manifests + ratings is wired up."
                }
            }

            // 2: Installed — real list of installed apps from the
            //    same source the launcher reads.
            Loader {
                anchors.fill: parent
                visible: root.currentView === 2
                active: visible
                sourceComponent: installedAppsPage
            }

            // 3: Account — placeholder until identity lands.
            Item {
                anchors.fill: parent
                visible: root.currentView === 3
                MEmptyState {
                    anchors.centerIn: parent
                    width: parent.width - 48
                    iconName: "user"
                    iconSize: 64
                    title: "Marathon Account"
                    message: "Sign-in, billing, and purchase history will appear here once the identity service is wired up."
                }
            }
        }

        MTabBar {
            id: tabBar
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            activeTab: root.currentView
            tabs: [
                {
                    "label": "Discover",
                    "icon": "compass"
                },
                {
                    "label": "Apps",
                    "icon": "grid"
                },
                {
                    "label": "Installed",
                    "icon": "download"
                },
                {
                    "label": "Account",
                    "icon": "user"
                }
            ]
            onTabSelected: index => {
                HapticService.light();
                root.currentView = index;
            }
        }
    }
}
