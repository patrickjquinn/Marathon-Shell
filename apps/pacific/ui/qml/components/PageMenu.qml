// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// The page menu, as the Sailfish Browser's pop-up menu: a card with rounded
// corners at the bottom right, under the menu button, rising over the
// dimmed page. A handle on top (drag the card down to close it, or tap the
// page), rows grouped by kind (new tabs; find, share, add to the app grid,
// desktop version; the browser's places), and the stock footer of four
// buttons: close the tab, forward, bookmark, reload. Taller than the screen
// allows, the rows scroll. Back is on the toolbar; the site's page opens
// from the lock.

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
    // The tallest the card may be (set by the page).
    property real maxHeight: height

    signal findRequested()
    signal pushPage(string page, var props)

    function show(): void { open = true }
    function hide(): void { open = false }

    width: parent ? parent.width : 0
    height: parent ? parent.height : 0
    visible: closed < 1

    // 1 closed, 0 open: the card's rise and the dimming.
    property real closed: open ? 0 : 1
    Behavior on closed { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

    readonly property real margin: Theme.paddingMedium
    readonly property real cornerRadius: Math.round(12 * Theme.pixelRatio)

    onOpenChanged: {
        if (open && webPage)
            Pacific.checkBookmark(pageUrl)
        if (open)
            flick.contentY = 0
    }

    Connections {
        target: Pacific
        function onBookmarkState(url, on) {
            if (url === menu.pageUrl)
                menu.bookmarked = on
        }
    }

    ShareAction {
        id: share
        mimeType: "text/x-url"
    }

    // The page, dimmed; a tap on it closes the menu.
    Rectangle {
        anchors.fill: parent
        color: Theme.overlayBackgroundColor
        opacity: Theme.opacityLow * (1 - menu.closed)
    }
    MouseArea {
        anchors.fill: parent
        enabled: menu.open
        onClicked: menu.hide()
    }

    Item {
        id: card
        objectName: "pageMenuCard"

        width: Math.min(menu.width - 2 * menu.margin, Math.max(Theme.paddingLarge * 18, 4 * Theme.itemSizeLarge))
        height: Math.min(menu.maxHeight - 2 * menu.margin, header.height + rows.height + footer.height)
        x: menu.width - width - menu.margin
        y: menu.height - height - menu.margin + menu.closed * (height + menu.margin)

        // Taps inside the card stay in it.
        MouseArea { anchors.fill: parent }

        // The stock menu's surface: the overlay colour, lifted by a faint
        // wash of the primary colour.
        Rectangle {
            anchors.fill: parent
            radius: menu.cornerRadius
            color: Theme.rgba(Theme.overlayBackgroundColor, 1.0)
            Rectangle {
                anchors.fill: parent
                radius: menu.cornerRadius
                color: Theme.rgba(Theme.primaryColor, Theme.opacityFaint)
            }
        }

        // The handle; dragging it down closes the menu.
        Item {
            id: header
            width: parent.width
            height: Theme.paddingLarge + Theme.paddingMedium
            Rectangle {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                width: Theme.itemSizeLarge
                height: Theme.paddingSmall
                radius: height / 2
                color: Theme.primaryColor
                opacity: flick.contentY > 0 ? Theme.opacityLow : 1
            }
            MouseArea {
                anchors.fill: parent
                property real startY
                onPressed: function(mouse) { startY = mouse.y }
                onReleased: function(mouse) {
                    if (mouse.y - startY > Theme.paddingLarge)
                        menu.hide()
                }
            }
        }

        SilicaFlickable {
            id: flick
            anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: footer.top }
            contentHeight: rows.height
            clip: true
            boundsBehavior: Flickable.DragOverBounds
            // Pulled down past its top: the card goes, as the stock menu's.
            onDragEnded: if (contentY < -Theme.itemSizeSmall) menu.hide()

            Column {
                id: rows
                width: parent.width
                topPadding: Theme.paddingSmall
                bottomPadding: 3 * Theme.paddingSmall
                spacing: Theme.paddingLarge

                Column {
                    width: parent.width
                    MenuButton {
                        iconSource: "image://theme/icon-m-tab-new"
                        text: qsTr("New tab")
                        onClicked: { menu.hide(); menu.browser.newTab(false) }
                    }
                    MenuButton {
                        iconSource: "image://theme/icon-m-incognito-new"
                        text: qsTr("New private tab")
                        onClicked: { menu.hide(); menu.browser.newTab(true) }
                    }
                }
                Column {
                    width: parent.width
                    MenuButton {
                        iconSource: "image://theme/icon-m-search-on-page"
                        text: qsTr("Find in page")
                        enabled: menu.webPage || (menu.tab !== null && menu.tab.readerMode)
                        onClicked: { menu.hide(); menu.findRequested() }
                    }
                    MenuButton {
                        iconSource: "image://theme/icon-m-add-to-grid"
                        text: qsTr("Add to app grid")
                        visible: Pacific.canAddToHomeScreen()
                        enabled: menu.webPage
                        onClicked: { Pacific.addToHomeScreen(menu.pageUrl, menu.view.title); menu.hide() }
                    }
                    MenuButton {
                        iconSource: "image://theme/icon-m-share"
                        text: qsTr("Share")
                        enabled: menu.webPage
                        onClicked: {
                            share.resources = [{ "data": menu.pageUrl, "linkTitle": menu.view.title, "type": "text/x-url" }]
                            share.title = menu.view.title
                            share.trigger()
                            menu.hide()
                        }
                    }
                }
                MenuButton {
                    iconSource: "image://theme/icon-m-computer"
                    text: qsTr("Desktop version")
                    checkable: true
                    checked: menu.view !== null && menu.view.desktopMode
                    enabled: menu.webPage
                    onClicked: Pacific.setSiteSetting(menu.pageUrl, "desktop", menu.view.desktopMode ? "0" : "1", menu.tab.isPrivate)
                }
                Column {
                    width: parent.width
                    MenuButton {
                        iconSource: "image://theme/icon-m-favorite-selected"
                        text: qsTr("Bookmarks")
                        onClicked: { menu.hide(); menu.pushPage("BookmarksPage.qml", { browser: menu.browser }) }
                    }
                    MenuButton {
                        iconSource: "image://theme/icon-m-history"
                        text: qsTr("History")
                        onClicked: { menu.hide(); menu.pushPage("HistoryPage.qml", { browser: menu.browser }) }
                    }
                    MenuButton {
                        iconSource: "image://theme/icon-m-downloads"
                        text: qsTr("Downloads")
                        onClicked: { menu.hide(); menu.pushPage("DownloadsPage.qml", { browser: menu.browser }) }
                    }
                    MenuButton {
                        iconSource: "image://theme/icon-m-setting"
                        text: qsTr("Settings")
                        onClicked: { menu.hide(); menu.pushPage("SettingsPage.qml", { browser: menu.browser }) }
                    }
                }
            }
            VerticalScrollDecorator {}
        }

        // The stock menu's footer: close tab, forward, bookmark, reload; the
        // card's bottom corners are its own.
        Item {
            id: footer
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: Theme.itemSizeMedium - Theme.paddingMedium
            // Opaque, a stronger wash than the card's; square at the top.
            Rectangle {
                anchors.fill: parent
                radius: menu.cornerRadius
                color: Theme.rgba(Theme.overlayBackgroundColor, 1.0)
            }
            Rectangle {
                width: parent.width
                height: menu.cornerRadius
                color: Theme.rgba(Theme.overlayBackgroundColor, 1.0)
            }
            // The wash in two parts that do not overlap (overlapping, the
            // translucent colour doubled into a band): square above, the
            // lower half of a rounded rectangle for the bottom corners.
            Rectangle {
                width: parent.width
                height: parent.height - menu.cornerRadius
                color: Theme.rgba(Theme.primaryColor, Theme.opacityFaint)
            }
            Item {
                y: parent.height - menu.cornerRadius
                width: parent.width
                height: menu.cornerRadius
                clip: true
                Rectangle {
                    y: -menu.cornerRadius
                    width: parent.width
                    height: 2 * menu.cornerRadius
                    radius: menu.cornerRadius
                    color: Theme.rgba(Theme.primaryColor, Theme.opacityFaint)
                }
            }
            Row {
                anchors.fill: parent
                readonly property real cell: width / 4
                IconButton {
                    objectName: "closeTabFooter"
                    width: parent.cell
                    height: parent.height
                    icon.source: "image://theme/icon-m-tab-close"
                    enabled: menu.tab !== null
                    onClicked: { menu.hide(); menu.browser.close(menu.browser.currentId, menu.tab.isPrivate) }
                }
                IconButton {
                    width: parent.cell
                    height: parent.height
                    icon.source: "image://theme/icon-m-forward"
                    enabled: menu.view !== null && menu.view.canGoForward
                    onClicked: { menu.view.goForward(); menu.hide() }
                }
                IconButton {
                    objectName: "bookmarkButton"
                    width: parent.cell
                    height: parent.height
                    icon.source: menu.bookmarked ? "image://theme/icon-m-favorite-selected" : "image://theme/icon-m-favorite"
                    highlighted: down || menu.bookmarked
                    enabled: menu.webPage
                    onClicked: Pacific.toggleBookmark(menu.pageUrl, menu.view.title)
                }
                IconButton {
                    width: parent.cell
                    height: parent.height
                    icon.source: menu.view && menu.view.loading ? "image://theme/icon-m-reset" : "image://theme/icon-m-refresh"
                    enabled: menu.webPage
                    onClicked: {
                        if (menu.view.loading)
                            menu.view.stop()
                        else
                            menu.view.reload()
                        menu.hide()
                    }
                }
            }
        }
    }
}
