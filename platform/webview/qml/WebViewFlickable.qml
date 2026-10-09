// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.WebView 1.0 WebViewFlickable on Keel: a Silica flickable holding
// a WebView (`webView`), so pulley menus can be attached above the content.
// The public documentation has no members; `webView`, `header` (a
// Component, as in Sailfish's; an Item is placed as it is) and `headerItem`
// follow how Sailfish apps use it. The page scrolls inside the web engine,
// the flickable holds the header and the pulley menus.
import QtQuick 2.6
import Sailfish.Silica 1.0

SilicaFlickable {
    id: flickable

    property alias webView: view
    property var header
    readonly property Item headerItem: header instanceof Item ? header : headerLoader.item

    contentWidth: width
    contentHeight: height
    interactive: !view.textSelectionActive

    Loader {
        id: headerLoader
        width: flickable.width
        sourceComponent: flickable.header instanceof Component ? flickable.header : null
    }

    WebView {
        id: view
        y: flickable.headerItem ? flickable.headerItem.height : 0
        width: flickable.width
        height: flickable.height - y
    }
}
