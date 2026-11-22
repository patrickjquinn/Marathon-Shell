// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// Typing an address or a search, over the page (BrowserPage): a sheet on
// the toolbar's flat surface with the page in view above it, and the
// toolbar rises into the field with the keyboard, as the Sailfish Browser's
// toolbar becomes its address field (it was a page of its own, pushed at
// once: the page behind vanished and came back with no motion between).
// The field stays at the bottom, under the thumb, and the list grows
// upwards from it, the best match nearest.
// Before anything is typed: "paste and go" for what is on the clipboard,
// the recent searches and the most visited sites. While typing: the
// address or search first, the most frecent site's host completed inline
// (the added part selected, so typing on replaces it), pages from history
// and bookmarks with their icons, open tabs to switch to, earlier searches
// and the engine's suggestions (when allowed; never in private tabs).

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Shipwright.Pacific 1.0
import "../js/logic.js" as Logic

Item {
    id: page
    objectName: "addressSheet"

    property var browser
    property string initialText
    // 0 closed, 1 open; the toolbar fades by it (BrowserPage).
    property real progress: 0
    readonly property bool shown: progress > 0
    property bool _completing: false
    property string _typed: ""
    readonly property bool privateTab: browser ? browser.privateMode : false
    readonly property string clipText: Clipboard.hasText ? String(Clipboard.text).trim() : ""
    readonly property bool canPaste: field.text === "" && clipText !== "" && clipText.length < 2048 && clipText.indexOf("\n") < 0

    property bool _open: false
    visible: shown

    // Opens with `text` in the field (selected, so typing replaces it).
    function open(text: var): void {
        initialText = text || "";
        field.text = initialText;
        field._selectedOnce = false;
        _open = true;
        // Open tabs to switch to, but not the one in front: that is
        // where the person already is.
        var tabs = browser ? JSON.parse(browser.tabs.tabsJson()) : [];
        var front = browser ? browser.tabs.activeId : -1;
        suggestions.tabs = JSON.stringify(tabs.filter(function (t) {
            return t.id !== front;
        }));
        suggestions.refresh();
        closeAnim.stop();
        openAnim.restart();
        field.forceActiveFocus();
    }
    // Back to the page: the sheet goes as the keyboard goes.
    function leave(): void {
        if (!_open)
            return;
        _open = false;
        openAnim.stop();
        closeAnim.restart();
        // The page takes the keys, as a browser's does. Focus left on
        // nothing kept the app's text input on, so the trackpad moved a
        // caret instead of scrolling until the page was tapped.
        var tab = browser ? browser.currentTab : null;
        if (tab && tab.webView)
            tab.webView.forceActiveFocus();
        else
            field.focus = false;
    }
    NumberAnimation {
        id: openAnim
        target: page
        property: "progress"
        to: 1
        duration: 240
        easing.type: Easing.OutCubic
    }
    NumberAnimation {
        id: closeAnim
        target: page
        property: "progress"
        to: 0
        duration: 180
        easing.type: Easing.InOutQuad
        onFinished: {
            field.text = "";
            page.initialText = "";
        }
    }

    // A tap on the page above the sheet goes back to it.
    MouseArea {
        anchors.fill: parent
        enabled: page._open
        onClicked: page.leave()
    }

    function go(text: var): var {
        if (text.trim() === "")
            return;
        var nav = JSON.parse(Pacific.classify(text));
        if (!nav.url)
            return;
        if (nav.kind === "search")
            Pacific.recordSearch(nav.query, nav.engine, privateTab);
        Pacific.recordSelection(_typed !== "" ? _typed : text, nav.url);
        browser.open(nav.url, {
            transition: "typed"
        });
        leave();
    }

    function choose(row: var): void {
        var s = JSON.parse(suggestions.get(row));
        if (s.kind === "tab") {
            browser.switchTo(s.tabId);
        } else {
            if (s.kind === "search" || s.kind === "suggestion" || s.kind === "recent")
                Pacific.recordSearch(s.query, s.engine, privateTab);
            Pacific.recordSelection(_typed, s.url);
            browser.open(s.url, {
                transition: "typed"
            });
        }
        leave();
    }

    SuggestionModel {
        id: suggestions
        remoteEnabled: page.browser ? page.browser.settings.search_suggestions && !page.privateTab : false
        onAutofillChanged: page.complete()
    }

    // Inline completion: only while adding characters at the end.
    function complete(): var {
        var a = suggestions.autofill;
        var t = field.text;
        if (a === "" || _completing || field.cursorPosition !== t.length)
            return;
        if (a.toLowerCase().indexOf(t.toLowerCase()) !== 0 || a.length <= t.length || t !== _typed)
            return;
        _completing = true;
        field.text = t + a.substring(t.length);
        field.select(t.length, field.text.length);
        _completing = false;
    }

    // The list and the field come up from where the toolbar was.
    Item {
        id: content
        anchors.fill: parent
        opacity: page.progress
        transform: Translate {
            y: (1 - page.progress) * Theme.itemSizeLarge
        }
        Rectangle {
            anchors {
                top: list.top
                bottom: parent.bottom
            }
            width: parent.width
            color: Theme.rgba(Theme.overlayBackgroundColor, 1.0)
            GlowLine {
                width: parent.width
            }
        }
        SilicaListView {
            id: list
            // As tall as its rows: above them the page shows, and a tap
            // there goes back to it.
            anchors {
                left: parent.left
                right: parent.right
                bottom: field.top
            }
            height: Math.min(contentHeight, field.y)
            verticalLayoutDirection: ListView.BottomToTop
            clip: true
            model: suggestions

            // Nearest the field: paste and go, then (before typing) the most
            // visited sites as a row of icons.
            header: Column {
                width: list.width

                BackgroundItem {
                    id: paste
                    objectName: "pasteAndGo"
                    visible: page.canPaste
                    width: parent.width
                    // As tall as its lines need at a large text size.
                    height: Math.max(Theme.itemSizeMedium, pasteText.height + 2 * Theme.paddingSmall)
                    onClicked: page.go(page.clipText)
                    Icon {
                        id: pasteIcon
                        x: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        source: "image://theme/icon-m-clipboard"
                        highlighted: paste.highlighted
                    }
                    Column {
                        id: pasteText
                        anchors {
                            left: pasteIcon.right
                            leftMargin: Theme.paddingMedium
                            right: parent.right
                            rightMargin: Theme.horizontalPageMargin
                            verticalCenter: parent.verticalCenter
                        }
                        Label {
                            text: JSON.parse(Pacific.classify(page.clipText)).kind === "url" ? qsTr("Paste and go") : qsTr("Paste and search")
                            color: paste.highlighted ? Theme.highlightColor : Theme.primaryColor
                        }
                        Label {
                            width: parent.width
                            text: page.clipText
                            textFormat: Text.PlainText
                            truncationMode: TruncationMode.Fade
                            font.pixelSize: Theme.fontSizeExtraSmall
                            color: paste.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                        }
                    }
                }

                Row {
                    objectName: "topSitesRow"
                    visible: field.text === "" && topSites.count > 0 && !page.privateTab
                    x: Theme.horizontalPageMargin - Theme.paddingSmall
                    // Sized by its own condition, not `visible`: `visible` is also false while the page is hidden under another, and a height that followed it collapsed the page's content then (its scroll position was lost on the way back).
                    height: (field.text === "" && topSites.count > 0 && !page.privateTab) ? implicitHeight : 0
                    Repeater {
                        model: PacificList {
                            id: topSites
                            kind: "topSites"
                            limit: Math.max(4, Math.floor(page.width / Theme.itemSizeHuge))
                            revision: Pacific.revision
                        }
                        delegate: SiteTile {
                            required property string title
                            required property string url
                            required property string icon
                            width: (page.width - 2 * Theme.horizontalPageMargin + 2 * Theme.paddingSmall) / topSites.limit
                            siteTitle: title
                            siteUrl: url
                            iconSource: icon
                            onClicked: {
                                page.browser.open(url, {
                                    transition: "bookmark"
                                });
                                page.leave();
                            }
                        }
                    }
                }
            }

            delegate: ListItem {
                id: item
                required property int index
                required property string kind
                required property string title
                required property string url
                required property string query
                required property string icon
                // As tall as its lines need at a large text size.
                contentHeight: Math.max(Theme.itemSizeMedium, suggestionText.height + 2 * Theme.paddingSmall)
                onClicked: page.choose(index)
                menu: item.kind === "recent" ? recentMenu : null

                Component {
                    id: recentMenu
                    ContextMenu {
                        MenuItem {
                            text: qsTr("Remove from recent searches")
                            onClicked: item.remorseDelete(function () {
                                Pacific.deleteSearch(item.query);
                                suggestions.refresh();
                            })
                        }
                    }
                }

                readonly property bool web: item.kind === "history" || item.kind === "bookmark" || item.kind === "tab" || item.kind === "visit"
                LetterIcon {
                    id: siteIcon
                    visible: item.web
                    x: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.iconSizeMedium
                    text: Logic.initial(item.title, item.url)
                    url: item.url
                    iconSource: item.icon
                    highlighted: item.highlighted
                }
                Icon {
                    id: kindIcon
                    visible: !item.web
                    x: Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    source: item.kind === "recent" ? "image://theme/icon-m-history" : "image://theme/icon-m-search"
                    highlighted: item.highlighted
                }
                Column {
                    id: suggestionText
                    anchors {
                        left: kindIcon.right
                        leftMargin: Theme.paddingMedium
                        right: badge.visible ? badge.left : parent.right
                        rightMargin: badge.visible ? Theme.paddingSmall : Theme.horizontalPageMargin
                        verticalCenter: parent.verticalCenter
                    }
                    Label {
                        width: parent.width
                        text: item.kind === "search" ? qsTr("Search for %1").arg(item.query) : item.title
                        textFormat: Text.PlainText
                        truncationMode: TruncationMode.Fade
                        color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
                    }
                    Label {
                        width: parent.width
                        visible: text !== ""
                        text: item.kind === "tab" ? qsTr("Switch to tab") : (!item.web ? "" : Logic.displayUrl(item.url, "") + (item.url.indexOf("/", 8) > 0 ? item.url.substring(item.url.indexOf("/", 8)) : ""))
                        textFormat: Text.PlainText
                        truncationMode: TruncationMode.Fade
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                    }
                }
                // Fill the field with this text to edit it further.
                IconButton {
                    id: badge
                    anchors {
                        right: parent.right
                        rightMargin: Theme.paddingSmall
                        verticalCenter: parent.verticalCenter
                    }
                    width: Theme.itemSizeSmall
                    height: Theme.itemSizeSmall
                    visible: item.kind !== "tab"
                    icon.source: "image://theme/icon-m-edit"
                    onClicked: {
                        field.text = item.kind === "search" || item.kind === "suggestion" || item.kind === "recent" ? item.query : item.url;
                        field.cursorPosition = field.text.length;
                        field.forceActiveFocus();
                    }
                }
            }

            VerticalScrollDecorator {}
        }

        TextField {
            id: field
            objectName: "addressField"
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                bottomMargin: Theme.paddingMedium
            }
            label: page.privateTab ? qsTr("Private tab") : qsTr("Address or search")
            placeholderText: qsTr("Search or type an address")
            inputMethodHints: Qt.ImhUrlCharactersOnly | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
            text: page.initialText
            EnterKey.iconSource: "image://theme/icon-m-enter-accept"
            EnterKey.onClicked: page.go(field.text)
            onTextChanged: {
                if (page._completing)
                    return;
                // The part a completion added is selected; what is typed is the rest.
                page._typed = field.selectionStart < field.selectionEnd ? text.substring(0, field.selectionStart) : text;
                suggestions.text = page._typed;
            }
            // The address is selected, so typing replaces it. Silica's field
            // places the cursor when it takes focus, so select once focus has
            // arrived rather than when the text is set.
            property bool _selectedOnce: false
            onActiveFocusChanged: {
                if (activeFocus && !_selectedOnce && text !== "") {
                    _selectedOnce = true;
                    Qt.callLater(selectAll);
                }
            }
        }
    }
}
