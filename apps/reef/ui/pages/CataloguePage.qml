// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: GPL-3.0-or-later

// The store's home: updates waiting (when there are), the featured apps as
// a banner, the collections as rows (or, from a repository without a store
// index, the newest and most recently updated apps), the categories, and
// every app. Search is in the pull-down menu, as in the Jolla Store, on a
// page of its own. Lists of many apps (a category, all of them, search
// results) are pages built as they scroll; this page holds only rows.
// Untested packages never reach these models (reef-backend hides them).

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Reef 1.0
import "../components"
import "../components/Texts.js" as Texts

Page {
    id: page

    // Categories per row of the grid.
    readonly property int categoryColumns: isLandscape ? 3 : 2

    function openApp(name) {
        pageStack.push(Qt.resolvedUrl("PackagePage.qml"), { packageName: name })
    }

    function browse(kind, browseId, title, subtitle) {
        pageStack.push(Qt.resolvedUrl("BrowsePage.qml"),
                       { kind: kind, browseId: browseId, title: title, subtitle: subtitle || "" })
    }

    // A flickable with one column (as Silica's own mixed pages): the page
    // header, then the banners and rows, then every app. When something near
    // the top appears or grows (the updates banner arrives after the page),
    // what is below moves down and the view stays where the person left it.
    // A ListView header grows upwards instead (Qt keeps the first row in
    // place), which slid the title and the banner under the camera cut-out.
    SilicaFlickable {
        id: list
        anchors.fill: parent
        contentHeight: content.height
        // Every app shown here (the search, on its own page, is cleared
        // when that page closes).
        readonly property int count: Reef.catalogueModel.count

        PullDownMenu {
            busy: Reef.busy
            MenuItem {
                text: qsTr("Settings")
                onClicked: pageStack.push(Qt.resolvedUrl("SettingsPage.qml"))
            }
            MenuItem {
                text: Reef.updateCount > 0
                      ? qsTr("Installed (%n update(s))", "", Reef.updateCount)
                      : qsTr("Installed")
                onClicked: pageStack.push(Qt.resolvedUrl("InstalledPage.qml"))
            }
            MenuItem {
                text: qsTr("Refresh")
                enabled: !Reef.busy
                onClicked: Reef.refresh()
            }
            MenuItem {
                objectName: "searchItem"
                text: qsTr("Search")
                onClicked: pageStack.push(Qt.resolvedUrl("SearchPage.qml"))
            }
        }

        Column {
            id: content
            width: list.width

            PageHeader {
                title: qsTr("Reef")
            }

            // The repository no longer matches the installed release (an OS
            // update happened) or was disabled: offer the fix up front.
            Column {
                width: parent.width
                visible: Reef.repoState !== "pinned"
                spacing: Theme.paddingSmall
                bottomPadding: Theme.paddingLarge

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    color: Theme.highlightColor
                    text: Reef.repoState === "drifted"
                          ? qsTr("Reef is set up for another Sailfish OS version. Repair it to get apps tested on %1.").arg(Reef.installedRelease)
                          : Reef.repoState === "disabled"
                            ? qsTr("Reef's app source is turned off.")
                            : qsTr("Reef's app source is missing.")
                }
                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: qsTr("Repair repository")
                    enabled: !Reef.busy
                    onClicked: Reef.repairRepository()
                }
            }

            // Updates waiting: first, with the one button that does them all.
            // One line says how many; the line under it says what the tap
            // shows, or that some are libraries and services (Update all
            // lists everything before it applies anything).
            BackgroundItem {
                id: updatesCard
                objectName: "updatesCard"
                width: parent.width
                height: (Reef.updateCount > 0) ? Math.max(Theme.itemSizeLarge, updatesText.height + 2 * Theme.paddingMedium) : 0
                visible: Reef.updateCount > 0
                onClicked: pageStack.push(Qt.resolvedUrl("InstalledPage.qml"))

                Rectangle {
                    anchors.fill: parent
                    color: Theme.rgba(Theme.highlightBackgroundColor, Theme.highlightBackgroundOpacity * 0.6)
                }
                Column {
                    id: updatesText
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.horizontalPageMargin
                    anchors.right: updateAll.left
                    anchors.rightMargin: Theme.paddingLarge
                    anchors.verticalCenter: parent.verticalCenter
                    Label {
                        width: parent.width
                        text: qsTr("%n update(s)", "", Reef.updateCount)
                        color: Theme.highlightColor
                        truncationMode: TruncationMode.Fade
                    }
                    Label {
                        width: parent.width
                        text: Reef.appUpdateCount === Reef.updateCount
                              ? qsTr("Tap to see what's new")
                              : qsTr("%n for libraries and services", "", Reef.updateCount - Reef.appUpdateCount)
                        color: Theme.secondaryHighlightColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                        wrapMode: Text.Wrap
                    }
                }
                SecondaryButton {
                    id: updateAll
                    objectName: "updateAllButton"
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    preferredWidth: Theme.buttonWidthExtraSmall
                    text: qsTr("Update all")
                    enabled: !Reef.busy
                    onClicked: Reef.updateAll()
                }
            }

            // The featured apps, one banner at a time, turning every few
            // seconds while the page is in front: one lap each time the page
            // comes to the front, then they stay put. Turning for ever kept
            // the store working while it sat open, a few percent of a core
            // on an Xperia 10 II.
            Item {
                width: parent.width
                height: (Reef.featuredModel.count > 0) ? hero.height + dots.height + Theme.paddingMedium : 0
                visible: Reef.featuredModel.count > 0

                SlideshowView {
                    id: hero
                    objectName: "featured"
                    // Its neighbouring banners wait a page width to either
                    // side; unclipped, they slid across the next page while
                    // the page stack moved this one away (a ghost of the
                    // carousel over Installed).
                    clip: true
                    width: parent.width
                    height: Math.round(Math.min(page.width, page.height) * 0.72)
                    itemWidth: width
                    itemHeight: height
                    model: Reef.featuredModel
                    // Every banner stays built: turning one in otherwise
                    // creates it again and decodes its screenshot again.
                    cacheItemCount: count
                    delegate: HeroCard {
                        width: hero.itemWidth
                        height: hero.itemHeight
                        onClicked: page.openApp(name)
                    }
                }
                Timer {
                    id: turn
                    property int steps
                    readonly property bool shown: page.status === PageStatus.Active
                                                  && Qt.application.state === Qt.ApplicationActive
                    interval: 6000
                    repeat: true
                    running: hero.count > 1 && shown && !hero.moving && steps < hero.count
                    onShownChanged: if (shown) steps = 0
                    onTriggered: {
                        steps++
                        hero.incrementCurrentIndex()
                    }
                }
                Row {
                    id: dots
                    anchors.top: hero.bottom
                    anchors.topMargin: Theme.paddingMedium
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Theme.paddingSmall
                    visible: hero.count > 1
                    height: (hero.count > 1) ? Theme.paddingSmall : 0
                    Repeater {
                        model: hero.count
                        Rectangle {
                            required property int index
                            width: Theme.paddingSmall
                            height: width
                            radius: width / 2
                            color: index === hero.currentIndex ? Theme.highlightColor : Theme.secondaryColor
                            opacity: index === hero.currentIndex ? 1.0 : Theme.opacityLow
                        }
                    }
                }
            }

            // The collections, each a row (the store index's: picked ones,
            // then new and recently updated).
            Repeater {
                objectName: "collections"
                model: Reef.collectionsModel
                delegate: CollectionRow {
                    required property string collectionId
                    required property string subtitle
                    width: content.width
                    onOpenApp: (name) => page.openApp(name)
                    onOpenAll: page.browse("collection", collectionId, title, subtitle)
                }
            }

            // A repository without a store index has no collections: new
            // apps and new versions instead, newest first.
            SectionHeader {
                text: qsTr("New and updated")
                visible: Reef.collectionsModel.count === 0 && Reef.recentModel.count > 0
            }
            SilicaListView {
                objectName: "recent"
                width: parent.width
                height: (Reef.collectionsModel.count === 0 && Reef.recentModel.count > 0) ? Theme.iconSizeLauncher + 2 * Theme.fontSizeExtraSmall * 1.4 + 2 * Theme.paddingMedium : 0
                visible: Reef.collectionsModel.count === 0 && Reef.recentModel.count > 0
                orientation: ListView.Horizontal
                clip: true
                model: Reef.recentModel
                header: Item { width: Theme.horizontalPageMargin - Theme.paddingLarge; height: 1 }
                delegate: FeaturedDelegate {
                    onClicked: page.openApp(name)
                }
            }

            // Every app first, then each category; how many apps each has
            // is on its page.
            SectionHeader {
                text: qsTr("Categories")
                visible: list.count > 0
            }
            Grid {
                objectName: "categories"
                width: parent.width
                columns: page.categoryColumns
                visible: list.count > 0
                CategoryTile {
                    objectName: "allApps"
                    width: content.width / page.categoryColumns
                    categoryId: ""
                    label: qsTr("All apps")
                    icon: "icon-m-menu"
                    onClicked: page.browse("all", "", qsTr("All apps"))
                }
                Repeater {
                    model: Reef.categoriesModel
                    delegate: CategoryTile {
                        width: content.width / page.categoryColumns
                        onClicked: page.browse("category", categoryId, label)
                    }
                }
            }

            Item {
                width: 1
                height: Theme.paddingLarge
            }
        }

        ViewPlaceholder {
            enabled: list.count === 0 && !Reef.busy
            text: Reef.lastError.length > 0 ? qsTr("Couldn't load the apps")
                                             : qsTr("No apps yet")
            hintText: Reef.lastError.length > 0
                      ? Texts.message(Reef.lastError)
                      : qsTr("No apps are tested on Sailfish OS %1 yet. Pull down to refresh.").arg(Reef.installedRelease)
        }

        VerticalScrollDecorator {}
    }

    BusyIndicator {
        anchors.centerIn: parent
        size: BusyIndicatorSize.Large
        running: Reef.busy && list.count === 0
    }
}
