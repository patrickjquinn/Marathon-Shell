// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// SilicaWebView: Silica's web view with pulley menus and a header. In Qt 5
// Silica it was QtWebKit's WebView (a Flickable) with Silica's extras;
// QtWebKit is gone, and Sailfish OS documents Sailfish.WebView for web
// content now. Keel's SilicaWebView keeps the type's API on Keel's
// Sailfish.WebView (Qt WebEngine): Silica's members as the BSD
// SilicaWebView.qml of 2014 declares them (quickScroll, quickScrollEnabled,
// pullDownMenu, pushUpMenu, pulleyMenuActive, overridePageStackNavigation,
// header, scrollToTop(), scrollToBottom()), and QtWebKit 3.0's WebView API
// that apps used through it (Qt 5 documentation: url, title, icon,
// loading, loadProgress, canGoBack, canGoForward, goBack(), goForward(),
// reload(), stop(), loadHtml(), loadingChanged (with loadRequest),
// navigationRequested(request), linkHovered(), the LoadStatus,
// NavigationRequestAction, NavigationType and ErrorDomain enums, and the
// experimental group's userAgent, preferences, evaluateJavaScript(),
// postMessage() and messageReceived). No code of either is used.
//
// The page scrolls inside the web engine: this Flickable holds the header
// and the pulley menus. It takes drags only while the page is at its top
// (pull-down menu) or bottom (push-up menu), so a pulley opens by dragging
// past the page's end. The WebView is made at run time
// (Sailfish.WebView, package shipwright-keel-platform-webview); without it
// the view says so and the API does nothing.
import QtQuick
import Sailfish.Silica
import Sailfish.Silica.private 1.0 as SilicaPrivate
import "private/Util.js" as Util

SilicaFlickable {
    id: root

    enum LoadStatus { LoadStartedStatus, LoadStoppedStatus, LoadSucceededStatus, LoadFailedStatus }
    enum NavigationRequestAction { AcceptRequest, IgnoreRequest }
    enum NavigationType { LinkClickedNavigation, FormSubmittedNavigation, BackForwardNavigation,
                          ReloadNavigation, FormResubmittedNavigation, OtherNavigation }
    enum ErrorDomain { NoErrorDomain, InternalErrorDomain, NetworkErrorDomain, HttpErrorDomain, DownloadErrorDomain }

    // Silica's.
    readonly property bool pulleyMenuActive: _menuActive(pullDownMenu) || _menuActive(pushUpMenu)
    property bool overridePageStackNavigation
    property Component header
    property var _headerItem: headerLoader.item
    property var _page: Util.findPage(root)
    property bool _cookiesEnabled: experimental.preferences.cookiesEnabled

    // QtWebKit's WebView.
    property url url
    readonly property string title: _view ? _view.title : ""
    readonly property url icon: _view && _view._backend && _view._backend.icon !== undefined ? _view._backend.icon : ""
    // loadingChanged also carries the load: in a handler, `loadRequest`
    // (this property) is the load that changed it, as QtWebKit's signal
    // argument was (url, status, errorString, errorCode, errorDomain).
    property bool loading
    property var loadRequest: null
    readonly property int loadProgress: _view ? _view.loadProgress : 0
    readonly property bool canGoBack: _view ? _view.canGoBack : false
    readonly property bool canGoForward: _view ? _view.canGoForward : false

    signal navigationRequested(var request)
    signal linkHovered(url hoveredUrl, string hoveredTitle)

    function _menuActive(menu) { return menu !== null && menu !== undefined && menu.active }

    function goBack() { if (_view) _view.goBack() }
    function goForward() { if (_view) _view.goForward() }
    function reload() { if (_view) _view.reload() }
    function stop() { if (_view) _view.stop() }
    function loadHtml(html, baseUrl, unreachableUrl) { if (_view) _view.loadHtml(html, baseUrl === undefined ? "" : baseUrl) }

    readonly property SilicaPrivate.WebKitExperimental experimental: SilicaPrivate.WebKitExperimental {
        view: root
    }

    function scrollToTop() { if (_view) _view.runJavaScript("window.scrollTo(0, 0); return true") }
    function scrollToBottom() {
        if (_view)
            _view.runJavaScript("window.scrollTo(0, document.documentElement.scrollHeight); return true")
    }

    // The WebView (Sailfish.WebView, made at run time), untyped.
    property var _view: null
    property bool _unavailable

    contentWidth: width
    contentHeight: height
    quickScrollEnabled: false
    interactive: _view !== null && !_view.moving
                 && ((pullDownMenu !== null && _view.atYBeginning) || (pushUpMenu !== null && _view.atYEnd))

    onUrlChanged: {
        if (_view && String(_view.url) !== String(url))
            _view.url = url
    }

    Loader {
        id: headerLoader
        width: root.width
        sourceComponent: root.header
        z: 1
    }

    Item {
        id: viewArea
        y: headerLoader.height
        width: root.width
        height: root.height - y
    }

    Label {
        anchors.centerIn: viewArea
        width: viewArea.width - 2 * Theme.horizontalPageMargin
        visible: root._unavailable
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        color: Theme.secondaryHighlightColor
        text: "Web content needs Sailfish.WebView"
    }

    Connections {
        target: root._view
        ignoreUnknownSignals: true
        function on_BackendChanged() {
            if (root._view._backend && root._view._backend.enableQtNavigator)
                root._view._backend.enableQtNavigator()
        }
        function onUrlChanged() {
            if (String(root.url) !== String(root._view.url))
                root.url = root._view.url
        }
    }

    Connections {
        target: root._view ? root._view._backend : null
        ignoreUnknownSignals: true
        function onKeelLoadingChanged(request) {
            root.loadRequest = request
            root.loading = request.status === SilicaWebView.LoadStartedStatus
        }
        function onKeelNavigationRequested(request) { root.navigationRequested(request) }
        function onKeelLinkHovered(hoveredUrl) { root.linkHovered(hoveredUrl, "") }
        function onKeelMessage(name, data) {
            if (name === "keel:qt-message")
                root.experimental.messageReceived({ "data": data })
        }
    }

    // Page navigation stays with the page while the view is scrolled
    // sideways or a pulley menu is open, as Silica's did.
    states: State {
        name: "disableNavigation"
        when: !root.overridePageStackNavigation && root._page !== null && root._view !== null
              && (!(root._view.atXBeginning && root._view.atXEnd) || root.pulleyMenuActive)
        PropertyChanges {
            target: root._page
            backNavigation: false
        }
    }

    Component.onCompleted: {
        var view = null
        try {
            view = Qt.createQmlObject("import Sailfish.WebView 1.0; WebView { anchors.fill: parent }", viewArea,
                                      "SilicaWebView.view")
        } catch (e) {
            view = null
        }
        if (!view) {
            _unavailable = true
            return
        }
        view.httpUserAgent = Qt.binding(function() { return root.experimental.userAgent })
        view.javascriptEnabled = Qt.binding(function() { return root.experimental.preferences.javascriptEnabled })
        view.backgroundColor = Qt.binding(function() { return root.experimental.transparentBackground ? "transparent" : "white" })
        // QtWebKit's navigator.qt for the page (its main world): messages
        // to the app, onmessage from it.
        view.addMessageListener("keel:qt-message")
        _view = view
        if (view._backend && view._backend.enableQtNavigator)
            view._backend.enableQtNavigator()
        if (String(url) !== "")
            view.url = url
        if (!_page)
            console.log("No parent Page found. A SilicaWebView should be declared inside a Page, as SilicaWebView overrides back navigation bindings defined in Page.")
    }
}
