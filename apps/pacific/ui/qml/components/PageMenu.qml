// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// The page menu: the toolbar's own sheet, full width on the same flat
// surface, rising from the toolbar with the glow line on its top edge. Rows
// in two columns (new tabs, find, add to the app grid, share; desktop
// version, the browser's places), one on a narrow screen, and the stock
// footer of four buttons as discs: close the tab, forward, bookmark,
// reload. Drag the sheet down or tap the page to close it. Taller than the
// screen allows, the rows scroll. Back is on the toolbar; the site's page
// opens from the lock.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Sailfish.Share 1.0
import Shipwright.Pacific 1.0

Item {
    id: menu

    property var browser
    property var tab: browser ? browser.currentTab : null
    readonly property var view: tab ? tab.webView : null
    readonly property string pageUrl: view ? String(view.url) : ""
    readonly property bool webPage: pageUrl.indexOf("http") === 0
    property bool bookmarked: false

    property bool open: false
    // The tallest the sheet and the toolbar under it may be (set by the page).
    property real maxHeight: height
    // The toolbar's height on screen: the sheet rises from its top edge.
    property real bottomMargin: 0

    signal findRequested
    signal pushPage(string page, var props)

    function show(): void {
        open = true;
    }
    function hide(): void {
        open = false;
    }

    width: parent ? parent.width : 0
    height: parent ? parent.height : 0
    visible: closed < 1

    // 1 closed, 0 open: the sheet's rise.
    property real closed: open ? 0 : 1
    Behavior on closed {
        NumberAnimation {
            duration: 200
            easing.type: Easing.InOutQuad
        }
    }

    onOpenChanged: {
        if (open && webPage)
            Pacific.checkBookmark(pageUrl);
        if (open)
            flick.contentY = 0;
    }

    Connections {
        target: Pacific
        function onBookmarkState(url, on) {
            if (url === menu.pageUrl)
                menu.bookmarked = on;
        }
    }

    ShareAction {
        id: share
        mimeType: "text/x-url"
    }

    // A tap on the page closes the menu.
    MouseArea {
        anchors.fill: parent
        enabled: menu.open
        onClicked: menu.hide()
    }

    // Above the toolbar, so the sheet rises from its top edge.
    Item {
        width: parent.width
        height: parent.height - menu.bottomMargin
        clip: true

        Item {
            objectName: "pageMenuCard"

            width: parent.width
            height: Math.min(menu.maxHeight - menu.bottomMargin, rows.height + footer.height)
            y: parent.height - height + menu.closed * height

            // Taps inside the sheet stay in it; dragging it down closes it.
            MouseArea {
                anchors.fill: parent
                property real startY
                onPressed: function (mouse) {
                    startY = mouse.y;
                }
                onReleased: function (mouse) {
                    if (mouse.y - startY > Theme.paddingLarge)
                        menu.hide();
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.rgba(Theme.overlayBackgroundColor, 1.0)
            }

            SilicaFlickable {
                id: flick
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    bottom: footer.top
                }
                contentHeight: rows.height
                clip: true
                boundsBehavior: Flickable.DragOverBounds
                // Pulled down past its top: the sheet goes, as the stock menu.
                onDragEnded: if (contentY < -Theme.itemSizeSmall)
                    menu.hide()

                // Two columns where the switch's row fits in one.
                Grid {
                    id: rows
                    width: parent.width
                    topPadding: Theme.paddingMedium
                    bottomPadding: Theme.paddingSmall
                    columns: width >= 2 * desktopRow.implicitWidth ? 2 : 1
                    readonly property real columnWidth: width / columns

                    Column {
                        width: rows.columnWidth
                        MenuButton {
                            iconSource: "image://theme/icon-m-tab-new"
                            text: qsTr("New tab")
                            onClicked: {
                                menu.hide();
                                menu.browser.newTab(false);
                            }
                        }
                        MenuButton {
                            iconSource: "image://theme/icon-m-incognito-new"
                            text: qsTr("New private tab")
                            onClicked: {
                                menu.hide();
                                menu.browser.newTab(true);
                            }
                        }
                        MenuButton {
                            iconSource: "image://theme/icon-m-search-on-page"
                            text: qsTr("Find in page")
                            enabled: menu.webPage || (menu.tab !== null && menu.tab.readerMode)
                            onClicked: {
                                menu.hide();
                                menu.findRequested();
                            }
                        }
                        MenuButton {
                            iconSource: "image://theme/icon-m-add-to-grid"
                            text: qsTr("Add to app grid")
                            visible: Pacific.canAddToHomeScreen()
                            enabled: menu.webPage
                            onClicked: {
                                Pacific.addToHomeScreen(menu.pageUrl, menu.view.title);
                                menu.hide();
                            }
                        }
                        MenuButton {
                            iconSource: "image://theme/icon-m-share"
                            text: qsTr("Share")
                            enabled: menu.webPage
                            onClicked: {
                                share.resources = [
                                    {
                                        "data": menu.pageUrl,
                                        "linkTitle": menu.view.title,
                                        "type": "text/x-url"
                                    }
                                ];
                                share.title = menu.view.title;
                                share.trigger();
                                menu.hide();
                            }
                        }
                    }
                    Column {
                        width: rows.columnWidth
                        MenuButton {
                            id: desktopRow
                            iconSource: "image://theme/icon-m-computer"
                            text: qsTr("Desktop version")
                            checkable: true
                            checked: menu.view !== null && menu.view.desktopMode
                            enabled: menu.webPage
                            onClicked: Pacific.setSiteSetting(menu.pageUrl, "desktop", menu.view.desktopMode ? "0" : "1", menu.tab.isPrivate)
                        }
                        MenuButton {
                            iconSource: "image://theme/icon-m-favorite-selected"
                            text: qsTr("Bookmarks")
                            onClicked: {
                                menu.hide();
                                menu.pushPage("BookmarksPage.qml", {
                                    browser: menu.browser
                                });
                            }
                        }
                        MenuButton {
                            iconSource: "image://theme/icon-m-history"
                            text: qsTr("History")
                            onClicked: {
                                menu.hide();
                                menu.pushPage("HistoryPage.qml", {
                                    browser: menu.browser
                                });
                            }
                        }
                        MenuButton {
                            iconSource: "image://theme/icon-m-downloads"
                            text: qsTr("Downloads")
                            onClicked: {
                                menu.hide();
                                menu.pushPage("DownloadsPage.qml", {
                                    browser: menu.browser
                                });
                            }
                        }
                        MenuButton {
                            iconSource: "image://theme/icon-m-setting"
                            text: qsTr("Settings")
                            onClicked: {
                                menu.hide();
                                menu.pushPage("SettingsPage.qml", {
                                    browser: menu.browser
                                });
                            }
                        }
                    }
                }
                VerticalScrollDecorator {}
            }

            // The stock menu's footer: close tab, forward, bookmark, reload,
            // each on a flat disc.
            Row {
                id: footer
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                height: Theme.itemSizeLarge
                readonly property real cell: width / 4
                IconButton {
                    objectName: "closeTabFooter"
                    width: footer.cell
                    height: parent.height
                    icon.source: "image://theme/icon-m-tab-close"
                    enabled: menu.tab !== null
                    onClicked: {
                        menu.hide();
                        menu.browser.close(menu.browser.currentId, menu.tab.isPrivate);
                    }
                    FooterDisc {}
                }
                IconButton {
                    width: footer.cell
                    height: parent.height
                    icon.source: "image://theme/icon-m-forward"
                    enabled: menu.view !== null && menu.view.canGoForward
                    onClicked: {
                        menu.view.goForward();
                        menu.hide();
                    }
                    FooterDisc {}
                }
                IconButton {
                    objectName: "bookmarkButton"
                    width: footer.cell
                    height: parent.height
                    icon.source: menu.bookmarked ? "image://theme/icon-m-favorite-selected" : "image://theme/icon-m-favorite"
                    highlighted: down || menu.bookmarked
                    enabled: menu.webPage
                    onClicked: Pacific.toggleBookmark(menu.pageUrl, menu.view.title)
                    FooterDisc {}
                }
                IconButton {
                    width: footer.cell
                    height: parent.height
                    icon.source: menu.view && menu.view.loading ? "image://theme/icon-m-reset" : "image://theme/icon-m-refresh"
                    enabled: menu.webPage
                    onClicked: {
                        if (menu.view.loading)
                            menu.view.stop();
                        else
                            menu.view.reload();
                        menu.hide();
                    }
                    FooterDisc {}
                }
            }

            GlowLine {
                width: parent.width
            }
        }
    }

    component FooterDisc: Rectangle {
        anchors.centerIn: parent
        z: -1
        width: Theme.itemSizeExtraSmall
        height: width
        radius: width / 2
        color: Theme.rgba(Theme.primaryColor, 0.08)
    }
}
