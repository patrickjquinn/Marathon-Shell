// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// The open tabs, as in the Sailfish Browser's tab view: Silica's tab bar
// switches between normal and private tabs (each with its count), and each
// tab is a card with its site icon, title and close button over the page's
// last picture. Tap a card to go to the tab, swipe it left or tap its
// close button to close it, press and hold for its context menu (pin,
// duplicate, close others). Pinned tabs come first. The search field finds
// a tab by title or address. Below, the stock browser's tab toolbar: back
// to the page, a new tab, and a menu with new tabs, reopening the last
// closed tab and closing all (with a remorse timer).

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Sailfish.Silica.private 1.0 as Private
import "../components"
import "../js/logic.js" as Logic

Page {
    id: page
    objectName: "tabsPage"

    property var browser
    property bool showPrivate: browser ? browser.privateMode : false
    readonly property var model: showPrivate ? browser.privateTabs : browser.normalTabs
    property string search: ""
    // The stock browser's picture proportions (height over width).
    readonly property real pictureAspect: isPortrait ? 0.6 : 0.4
    // The stock browser's toolbar heights (portrait, landscape).
    readonly property real toolbarHeight: Math.round((isPortrait ? 108 : 72) * Theme.pixelRatio)

    allowedOrientations: Orientation.All

    function openTab(id: var, isPrivate: var): void {
        browser.switchTo(id, isPrivate === undefined ? showPrivate : isPrivate);
        back();
    }
    // To the browser page, whose page grows back from the overview's size.
    function back(): void {
        browser.returnFromTabs();
    }

    // Made by BrowserPage ahead of its push (an object the page stack hands
    // back rather than destroying when it is popped): gone once popped.
    property bool ownedByCaller: false
    property bool _wasShown: false
    onStatusChanged: if (status === PageStatus.Active)
        _wasShown = true
    onPageContainerChanged: {
        if (ownedByCaller && _wasShown && !pageContainer)
            Qt.callLater(function () {
                page.destroy();
            });
    }

    // Comes in as the page shrinks away into it (BrowserPage): the cards
    // settle from a little larger, out of the page's last frame.
    Component.onCompleted: enter.start()
    ParallelAnimation {
        id: enter
        NumberAnimation {
            target: tabView
            property: "opacity"
            from: 0.3
            to: 1
            duration: 180
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: tabView
            property: "scale"
            from: 1.08
            to: 1
            duration: 240
            easing.type: Easing.OutCubic
        }
    }
    function kindTitle(isPrivate: var): var {
        return isPrivate ? qsTr("Private (%1)").arg(browser.privateTabs.count) : qsTr("Tabs (%1)").arg(browser.normalTabs.count);
    }
    function matches(title: var, url: var): var {
        var q = search.trim().toLowerCase();
        return q === "" || (String(title) + " " + String(url)).toLowerCase().indexOf(q) >= 0;
    }

    ListModel {
        id: kinds
        Component.onCompleted: {
            append({
                title: page.kindTitle(false),
                icon: "image://theme/icon-m-tabs"
            });
            append({
                title: page.kindTitle(true),
                icon: "image://theme/icon-m-incognito"
            });
        }
    }
    Connections {
        target: page.browser.normalTabs
        function onCountChanged() {
            kinds.setProperty(0, "title", page.kindTitle(false));
        }
    }
    Connections {
        target: page.browser.privateTabs
        function onCountChanged() {
            kinds.setProperty(1, "title", page.kindTitle(true));
        }
    }

    Private.TabView {
        id: tabView
        objectName: "tabKindSwitch"
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            bottom: toolbar.top
        }
        currentIndex: page.showPrivate ? 1 : 0
        onCurrentIndexChanged: page.showPrivate = currentIndex === 1
        interactive: false

        // Silica's tab bar: an icon, the title and the count per kind.
        header: Private.TabBar {
            model: kinds
        }

        model: [false, true]
        delegate: Private.TabItem {
            id: kindItem
            required property bool modelData
            readonly property bool privateKind: modelData
            readonly property var tabs: privateKind ? page.browser.privateTabs : page.browser.normalTabs
            width: tabView.width
            height: tabView.height - tabView.tabBarHeight
            flickable: list

            SilicaListView {
                id: list
                anchors.fill: parent
                model: kindItem.tabs
                currentIndex: -1 // no list highlight bar; the tab in front is marked on its card
                // Opens at the tab in front, not at the oldest tab.
                Component.onCompleted: {
                    var i = kindItem.tabs.indexOf(kindItem.tabs.activeId);
                    if (i > 0)
                        positionViewAtIndex(i, ListView.Center);
                }
                // One column of cards on a phone in portrait, more when wide.
                readonly property int columns: Math.max(1, Math.floor(width / (Theme.itemSizeHuge * 3.2)))

                header: SearchField {
                    objectName: "tabSearch"
                    width: list.width
                    placeholderText: qsTr("Search tabs")
                    text: page.search
                    EnterKey.iconSource: "image://theme/icon-m-enter-close"
                    EnterKey.onClicked: focus = false
                    onTextChanged: page.search = text
                }

                ViewPlaceholder {
                    enabled: kindItem.tabs.count === 0
                    text: kindItem.privateKind ? qsTr("No private tabs") : qsTr("No tabs")
                    hintText: kindItem.privateKind ? qsTr("Tap + below to open a private tab. Private tabs keep no history, cookies or cache.") : qsTr("Tap + below to open a tab")
                }

                delegate: ListItem {
                    id: cell
                    objectName: "tabCard"
                    required property int index
                    required property int tabId
                    required property string title
                    required property string url
                    required property string thumbnail
                    required property string icon
                    required property bool isPrivate
                    required property bool audible
                    required property bool pinned
                    readonly property bool current: cell.tabId === kindItem.tabs.activeId && page.browser.privateMode === kindItem.privateKind
                    readonly property bool shown: page.matches(title, url)

                    width: list.width
                    visible: shown
                    contentHeight: shown ? card.height + Theme.paddingLarge : 0
                    _showPress: false
                    onClicked: page.openTab(cell.tabId, kindItem.privateKind)

                    // Swipe left to close. Only left: a swipe to the right is
                    // the page stack's, back to the browser. The card's drag
                    // starts later than the page stack's (1.5x its distance),
                    // so the page stack takes a rightward swipe first. A
                    // DragHandler here took every sideways swipe at Qt's 10 px
                    // (the page stack cannot take a touch from a pointer
                    // handler), and back did nothing over a card.
                    drag.target: card
                    drag.axis: Drag.XAxis
                    drag.threshold: Math.round(Theme.startDragDistance * 1.5)
                    drag.minimumX: Theme.horizontalPageMargin - card.width
                    drag.maximumX: Theme.horizontalPageMargin
                    drag.onActiveChanged: {
                        if (drag.active)
                            return;
                        if (card.offset < -card.width / 3)
                            page.browser.close(cell.tabId, kindItem.privateKind);
                        else
                            card.x = Theme.horizontalPageMargin;
                    }
                    // A closed tab's card fades and folds away and the cards
                    // below slide up (Silica's removal), instead of vanishing.
                    ListView.onRemove: animateRemoval(cell)

                    menu: Component {
                        ContextMenu {
                            MenuItem {
                                text: cell.pinned ? qsTr("Unpin tab") : qsTr("Pin tab")
                                onClicked: kindItem.tabs.setPinned(cell.tabId, !cell.pinned)
                            }
                            MenuItem {
                                text: qsTr("Duplicate tab")
                                visible: cell.url !== ""
                                onClicked: {
                                    page.browser.open(cell.url, {
                                        newTab: true,
                                        private: kindItem.privateKind
                                    });
                                    page.back();
                                }
                            }
                            MenuItem {
                                text: qsTr("Close other tabs")
                                visible: kindItem.tabs.count > 1
                                onClicked: {
                                    for (var i = kindItem.tabs.count - 1; i >= 0; --i) {
                                        var id = kindItem.tabs.idAt(i);
                                        if (id !== cell.tabId && !JSON.parse(kindItem.tabs.get(id)).pinned)
                                            page.browser.close(id, kindItem.privateKind);
                                    }
                                }
                            }
                            MenuItem {
                                text: qsTr("Close tab")
                                onClicked: page.browser.close(cell.tabId, kindItem.privateKind)
                            }
                        }
                    }

                    // The card: the stock browser's lifted surface, rounded.
                    Rectangle {
                        id: card
                        objectName: "tabCardSurface"
                        // Left of its place while it is swiped (0 at rest).
                        readonly property real offset: x - Theme.horizontalPageMargin
                        x: Theme.horizontalPageMargin
                        y: Theme.paddingLarge / 2
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        height: header.height + picture.height
                        radius: Math.round(12 * Theme.pixelRatio)
                        opacity: 1 - Math.min(0.8, Math.abs(offset) / width)
                        color: Theme.rgba(Theme.primaryColor, Theme.opacityFaint)
                        Behavior on x {
                            enabled: !cell.drag.active
                            NumberAnimation {
                                duration: 150
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: cell.down ? Theme.rgba(Theme.highlightBackgroundColor, Theme.opacityLow) : (cell.current ? Theme.rgba(Theme.highlightColor, 0.1) : "transparent")
                        }

                        Item {
                            id: header
                            width: parent.width
                            height: Theme.itemSizeSmall
                            LetterIcon {
                                id: favicon
                                x: Theme.paddingMedium
                                anchors.verticalCenter: parent.verticalCenter
                                width: Theme.iconSizeSmall
                                visible: cell.url !== ""
                                text: Logic.initial(cell.title, cell.url)
                                url: cell.url
                                iconSource: cell.icon
                            }
                            Row {
                                id: marks
                                anchors {
                                    right: closeButton.left
                                    verticalCenter: parent.verticalCenter
                                }
                                Icon {
                                    objectName: "pinnedMark"
                                    visible: cell.pinned
                                    source: "image://theme/icon-s-favorite"
                                    highlighted: true
                                }
                                Icon {
                                    objectName: "audibleMark"
                                    visible: cell.audible
                                    source: "image://theme/icon-m-browser-sound"
                                    width: Theme.iconSizeSmall
                                    height: width
                                    highlighted: true
                                }
                            }
                            Label {
                                anchors {
                                    left: favicon.visible ? favicon.right : parent.left
                                    leftMargin: Theme.paddingMedium
                                    right: marks.left
                                    rightMargin: Theme.paddingSmall
                                    verticalCenter: parent.verticalCenter
                                }
                                text: cell.url === "" ? qsTr("New tab") : (cell.title !== "" ? cell.title : Logic.host(cell.url))
                                textFormat: Text.PlainText
                                truncationMode: TruncationMode.Fade
                                font.pixelSize: Theme.fontSizeSmall
                                color: cell.current || cell.down ? Theme.highlightColor : Theme.primaryColor
                            }
                            IconButton {
                                id: closeButton
                                objectName: "closeTabButton"
                                anchors {
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                }
                                width: Theme.itemSizeSmall
                                height: Theme.itemSizeSmall
                                icon.source: "image://theme/icon-s-clear-opaque-cross"
                                onClicked: page.browser.close(cell.tabId, kindItem.privateKind)
                            }
                        }

                        // The page's last picture, its lower corners rounded
                        // with the card's.
                        Item {
                            id: picture
                            anchors.top: header.bottom
                            width: parent.width
                            height: Math.round(width * page.pictureAspect)
                            // Drawn by the ShaderEffect below in one pass, no
                            // layers; at opacity 0 its texture still updates.
                            Image {
                                id: thumb
                                anchors.fill: parent
                                source: cell.isPrivate ? "" : cell.thumbnail
                                fillMode: Image.PreserveAspectCrop
                                verticalAlignment: Image.AlignTop
                                asynchronous: true
                                opacity: 0
                            }
                            ShaderEffect {
                                readonly property Image source: thumb
                                readonly property vector4d crop: thumb.paintedWidth > 0 && thumb.paintedHeight > 0 ? Qt.vector4d((1 - width / thumb.paintedWidth) / 2, 0, width / thumb.paintedWidth, height / thumb.paintedHeight) : Qt.vector4d(0, 0, 1, 1)
                                readonly property size size: Qt.size(width, height)
                                readonly property real radius: card.radius

                                anchors.fill: parent
                                visible: thumb.status === Image.Ready
                                fragmentShader: Qt.resolvedUrl("../shaders/tabthumb.frag.qsb")
                            }
                            LetterIcon {
                                anchors.centerIn: parent
                                visible: thumb.status !== Image.Ready
                                text: cell.url === "" ? "+" : Logic.initial(cell.title, cell.url)
                                url: cell.url
                                iconSource: cell.icon
                            }
                        }
                    }
                }

                VerticalScrollDecorator {}
            }
        }
    }

    // The stock browser's tab toolbar: back to the page, a new tab of the
    // kind shown, and a menu (reopen the last closed tab, close all).
    Item {
        id: toolbar
        objectName: "tabsToolbar"
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: page.toolbarHeight
        Rectangle {
            anchors.fill: parent
            color: Theme.overlayBackgroundColor
            opacity: 0.948
        }
        IconButton {
            objectName: "tabsReturn"
            anchors {
                left: parent.left
                leftMargin: Theme.paddingSmall
                verticalCenter: parent.verticalCenter
            }
            icon.source: "image://theme/icon-m-tab-return"
            onClicked: page.back()
        }
        IconButton {
            objectName: "newTabButton"
            anchors.centerIn: parent
            icon.source: page.showPrivate ? "image://theme/icon-m-incognito-new" : "image://theme/icon-m-tab-new"
            onClicked: {
                page.browser.newTab(page.showPrivate);
                page.back();
            }
        }
        IconButton {
            objectName: "tabsMenuButton"
            anchors {
                right: parent.right
                rightMargin: Theme.paddingSmall
                verticalCenter: parent.verticalCenter
            }
            icon.source: "image://theme/icon-m-menu"
            onClicked: tabsMenu.open = !tabsMenu.open
        }
    }

    DockedPanel {
        id: tabsMenu
        objectName: "tabsMenu"
        width: parent.width
        height: menuColumn.height
        dock: Dock.Bottom
        modal: true
        Rectangle {
            anchors.fill: parent
            color: Theme.rgba(Theme.overlayBackgroundColor, 1.0)
            Rectangle {
                anchors.fill: parent
                color: Theme.rgba(Theme.primaryColor, Theme.opacityFaint)
            }
        }
        Column {
            id: menuColumn
            width: parent.width
            topPadding: Theme.paddingMedium
            bottomPadding: Theme.paddingMedium
            MenuButton {
                iconSource: "image://theme/icon-m-tab-new"
                text: qsTr("New tab")
                onClicked: {
                    tabsMenu.hide();
                    page.browser.newTab(false);
                    page.back();
                }
            }
            MenuButton {
                iconSource: "image://theme/icon-m-incognito-new"
                text: qsTr("New private tab")
                onClicked: {
                    tabsMenu.hide();
                    page.browser.newTab(true);
                    page.back();
                }
            }
            MenuButton {
                iconSource: "image://theme/icon-m-refresh"
                text: qsTr("Reopen closed tab")
                visible: !page.showPrivate && page.browser.normalTabs.closedCount > 0
                onClicked: {
                    tabsMenu.hide();
                    page.browser.reopenClosed();
                    page.back();
                }
            }
            MenuButton {
                iconSource: "image://theme/icon-m-cancel"
                text: page.showPrivate ? qsTr("Close all private tabs") : qsTr("Close all tabs")
                visible: page.model.count > 0
                onClicked: {
                    var priv = page.showPrivate;
                    tabsMenu.hide();
                    Remorse.popupAction(page, priv ? qsTr("Closed all private tabs") : qsTr("Closed all tabs"), function () {
                        page.browser.closeAll(priv);
                    });
                }
            }
        }
    }
}
