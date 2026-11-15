// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// A long press on a link or an image: open it in a new (private) tab,
// copy, share or save it.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Sailfish.Share 1.0
import Shipwright.Pacific 1.0
import "../js/logic.js" as Logic

Rectangle {
    id: menu

    property var browser
    property var tab
    property var info: ({})
    readonly property string link: info && info.linkUrl ? String(info.linkUrl) : ""
    readonly property string image: info && info.imageUrl ? String(info.imageUrl) : ""
    readonly property string selection: info && info.selectionText ? String(info.selectionText) : ""
    // A long press on a misspelt word in a field: the checker's
    // suggestions (at most five), learn or ignore.
    readonly property bool misspelled: info && info.misspelled === true
    readonly property var suggestions: misspelled && info.spellingSuggestions ? info.spellingSuggestions.slice(0, 5) : []

    signal done

    color: Theme.rgba(Theme.overlayBackgroundColor, 0.9)

    MouseArea {
        anchors.fill: parent
        onClicked: menu.done()
    }

    ShareAction {
        id: share
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: column.height + Theme.paddingLarge
        color: Theme.rgba(Theme.overlayBackgroundColor, 1.0)

        Column {
            id: column
            width: parent.width

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * x
                height: Theme.itemSizeSmall
                verticalAlignment: Text.AlignVCenter
                text: menu.link !== "" ? menu.link : (menu.image !== "" ? menu.image : (menu.misspelled ? (menu.suggestions.length > 0 ? qsTr("Spelling") : qsTr("No spelling suggestions")) : menu.selection))
                textFormat: Text.PlainText
                truncationMode: TruncationMode.Fade
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeSmall
            }
            Repeater {
                model: menu.suggestions
                MenuItem {
                    required property int index
                    required property string modelData
                    text: modelData
                    onClicked: {
                        menu.tab.webView.applySpellingSuggestion(index);
                        menu.done();
                    }
                }
            }
            MenuItem {
                visible: menu.misspelled
                text: qsTr("Add to dictionary")
                onClicked: {
                    menu.tab.webView.learnSpelling();
                    menu.done();
                }
            }
            MenuItem {
                visible: menu.misspelled
                text: qsTr("Ignore")
                onClicked: {
                    menu.tab.webView.ignoreSpelling();
                    menu.done();
                }
            }
            MenuItem {
                visible: menu.link !== ""
                text: qsTr("Open in new tab")
                onClicked: {
                    menu.browser.open(menu.link, {
                        newTab: true,
                        background: true,
                        private: menu.tab.isPrivate
                    });
                    Notices.show(qsTr("Opened in a new tab"));
                    menu.done();
                }
            }
            MenuItem {
                visible: menu.link !== "" && !menu.tab.isPrivate
                text: qsTr("Open in private tab")
                onClicked: {
                    menu.browser.open(menu.link, {
                        newTab: true,
                        private: true
                    });
                    menu.done();
                }
            }
            MenuItem {
                visible: menu.link !== "" || menu.image !== "" || menu.selection !== ""
                text: menu.selection !== "" && menu.link === "" ? qsTr("Copy text") : qsTr("Copy link")
                onClicked: {
                    Clipboard.text = menu.link !== "" ? menu.link : (menu.image !== "" ? menu.image : menu.selection);
                    Notices.show(qsTr("Copied"));
                    menu.done();
                }
            }
            MenuItem {
                visible: menu.link !== "" || menu.image !== "" || menu.selection !== ""
                text: qsTr("Share")
                onClicked: {
                    if (menu.link === "" && menu.image === "") {
                        share.mimeType = "text/plain";
                        share.resources = [
                            {
                                "data": menu.selection,
                                "type": "text/plain"
                            }
                        ];
                    } else {
                        var u = menu.link !== "" ? menu.link : menu.image;
                        share.mimeType = "text/x-url";
                        share.resources = [
                            {
                                "data": u,
                                "linkTitle": u,
                                "type": "text/x-url"
                            }
                        ];
                    }
                    share.trigger();
                    menu.done();
                }
            }
            MenuItem {
                visible: menu.image !== "" && menu.image.indexOf("http") === 0
                text: qsTr("Save image")
                onClicked: {
                    menu.tab.webView.profile.download(menu.image);
                    menu.done();
                }
            }
            MenuItem {
                visible: menu.selection !== ""
                text: qsTr("Search for \"%1\"").arg(Logic.escape(menu.selection.substring(0, 30)))
                onClicked: {
                    menu.browser.open(Pacific.searchUrl(menu.selection), {
                        newTab: true,
                        private: menu.tab.isPrivate
                    });
                    menu.done();
                }
            }
        }
    }
}
