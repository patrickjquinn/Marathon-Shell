// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.WebView 1.0 WebViewPage on Keel: a Silica Page for full-page web
// content (the public documentation has no members beyond Page's). A
// WebView inside it takes it as its webViewPage and is active while the
// page is.
import QtQuick 2.6
import Sailfish.Silica 1.0

Page {
    readonly property bool _keelWebViewPage: true
}
