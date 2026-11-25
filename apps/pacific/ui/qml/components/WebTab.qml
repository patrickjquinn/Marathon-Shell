// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// One tab: a web view and everything that happens to its page. A delegate
// of a TabModel (BrowserPage's Repeaters); it keeps the model row up to
// date, applies HTTPS-first, cosmetic filtering, site settings and the
// lifecycle decisions, records history and answers the page's requests
// (permissions, downloads, dialogs, new windows) with the UI's help.
//
// A restored or discarded tab has no live page (`live` false) until it is
// shown: wake() restores its back/forward list and loads it then.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Pacific 1.0
import Shipwright.Pacific.WebView 1.0
import "../js/logic.js" as Logic

Item {
    id: tab

    required property int tabId
    required property string url
    required property string title
    required property bool live
    required property string engineState
    required property real scrollY
    required property string thumbnail
    required property bool isPrivate
    required property int index

    property var browser
    property TabModel tabModel
    // The page stack, for dialogs.
    property var pageStack

    readonly property bool current: browser !== null && browser.tabs === tabModel && tabModel.activeId === tabId
    readonly property alias webView: view
    readonly property bool newTabPage: url === "" && !view.loading
    readonly property bool readerMode: Logic.isReaderUrl(view.url)

    // How the current navigation started (for frecency): typed, link, ...
    property string transition: "link"
    // The site settings of the page shown, as Pacific.siteSettingsLoaded gave them.
    property var siteSettings: ({})
    property bool crashed: false
    // Opened for another app (openUrl): back from its first page closes it.
    property bool openedByApp: false
    // A failed load to show: { url, error } (or null).
    property var loadError: null
    // HTTPS-first interstitial: { http_url, host } (or null).
    property var interstitial: null
    // A certificate problem: { url, host, pem } (or null).
    property var certificateProblem: null
    // Requests waiting for the person.
    property var pendingPermission: null
    // A login form on the page: { url, logins: [{id, title, username}], locked }.
    property var pendingLogin: null
    // A login just submitted, to offer saving: { url, username, password }.
    property var pendingSave: null
    property string _readerFrom: ""
    // Scroll direction for the collapsing toolbar.
    property real lastScrollY: 0
    property real _lastScrollAt: 0
    property int _sentProgress: -100
    property real lastViewportHeight: 0
    property real lastContentHeight: 0
    // The web view was let go (discarded): what it reports while letting
    // go (an empty address, title) is not the tab's.
    property bool _parked: false
    // Woken from saved state: the last picture stays up until the page's
    // first frame, and the scroll position is put back once it has loaded.
    property bool _waking: false
    signal scrolled(real dy)
    // One finger dragged down on the page, scrolled or not (WebView.pulledDown).
    signal pulledDown
    // Pull to refresh (WebView.pullMoved/pullEnded).
    signal pullMoved(real distance)
    signal pullEnded(real distance, real velocity)
    // Swipe back and forward (WebView.swipeNavMoved/swipeNavEnded).
    signal navMoved(real dx)
    signal navEnded(real dx, real velocity)
    signal readerFailed(string message)

    visible: current
    anchors.fill: parent

    // ---- Navigation ------------------------------------------------------

    function go(target: var, how: var): void {
        transition = how || "link";
        loadError = null;
        interstitial = null;
        crashed = false;
        var step = JSON.parse(Pacific.httpsNavigate(tabId, String(target)));
        view.load(step.action === "load" ? step.url : target);
        tabModel.update(tabId, JSON.stringify({
            live: true,
            url: String(target)
        }));
    }

    // Brings a restored or discarded tab back, from the state saved when it
    // was let go: the engine's session state (back/forward history), else
    // its address.
    function wake(): var {
        if (view.webProcessRunning && live && !_parked)
            return;
        crashed = false;
        _parked = false;
        if (url === "" && engineState === "")
            return;
        _waking = true;
        if (engineState !== "" && view.restoreSessionState(engineState))
            view.reload();
        else if (url !== "")
            view.load(url);
        tabModel.update(tabId, JSON.stringify({
            live: true
        }));
    }

    // Woken from saved state a moment ago and not loaded yet, when another
    // tab takes the front (Pacific started for a link): its web process goes
    // as discard() lets it go, and it loads when it is shown again. The model
    // still holds the state it was woken from.
    function unwake(): void {
        if (!_waking)
            return;
        _waking = false;
        _parked = true;
        view.discard();
        tabModel.update(tabId, JSON.stringify({
            live: false
        }));
    }

    // Lets the web view go to save memory. The tab keeps its address,
    // title, scroll position and the engine's session state (in the tab
    // model, and so in the session file a crash restore reads), and its
    // last picture.
    function discard(): var {
        if (!view.webProcessRunning)
            return;
        var saved = {
            url: tab.readerMode ? tab.url : (String(view.url) || tab.url),
            title: view.title || tab.title,
            scrollY: tab.lastScrollY,
            engineState: view.sessionState() || tab.engineState
        };
        // The scroll position as the page has it now (scroll reports are
        // throttled), then the picture, then the view goes.
        view.runJavaScript("String(window.scrollY)", function (y) {
            var top = Number(y);
            if (y !== null && y !== undefined && isFinite(top) && top >= 0)
                saved.scrollY = top;
            tab.saveThumbnail(function () {
                tab._parked = true;
                saved.live = false;
                tab.tabModel.update(tab.tabId, JSON.stringify(saved));
                view.discard();
            });
        });
    }

    // Back to the top of the page, as a tap on iOS's status bar does: the
    // page itself, or (an app-like page that scrolls a box of its own) the
    // scrolled box under the middle of the screen. From far down it jumps
    // to two screens from the top first, so the glide (WebKit's smooth
    // scroll, on the scrolling thread, at most 200 ms) is not a blur.
    function scrollToTop(): void {
        view.runJavaScriptInWorld("(function () {" + " function top(s, y) { if (y > 2 * innerHeight) s.scrollTo({ top: 2 * innerHeight, behavior: 'instant' });" + " s.scrollTo({ top: 0, behavior: 'smooth' }) }" + " if (window.scrollY > 0) { top(window, window.scrollY); return }" + " for (var e = document.elementFromPoint(innerWidth / 2, innerHeight / 2); e; e = e.parentElement)" + " if (e.scrollTop > 0 && e.scrollHeight > e.clientHeight) { top(e, e.scrollTop); return } })()", "pacific");
    }

    function storeEngineState(): void {
        if (view.webProcessRunning && String(view.url) !== "")
            tabModel.update(tabId, JSON.stringify({
                engineState: view.sessionState()
            }));
    }

    // Only the tab in front: this engine snapshots a background view as
    // whatever was last on screen, which gave tabs another page's picture.
    function saveThumbnail(done: var): void {
        if (isPrivate || String(view.url) === "" || !current) {
            if (done)
                done();
            return;
        }
        var path = Pacific.thumbnailDir + "/tab-" + tabId + ".png";
        view.saveThumbnail(path, Theme.itemSizeHuge * 3, Theme.itemSizeHuge * 5, function (ok) {
            if (ok)
                tab.tabModel.update(tab.tabId, JSON.stringify({
                    thumbnail: "file://" + path + "?" + Date.now()
                }));
            if (done)
                done();
        });
    }

    // ---- Reader mode -----------------------------------------------------

    function toggleReader(): void {
        if (readerMode) {
            if (view.canGoBack)
                view.goBack();
            else if (_readerFrom !== "")
                view.load(_readerFrom);
            return;
        }
        _readerFrom = String(view.url);
        view.pageHtml(4000000, function (html) {
            if (typeof html === "string" && html.length > 0)
                Pacific.reader(tab.tabId, tab._readerFrom, html, qsTr("%1 min read"), JSON.stringify({
                    background: String(Theme.rgba(Theme.overlayBackgroundColor, 1.0)),
                    primary: String(Theme.primaryColor),
                    secondary: String(Theme.secondaryColor),
                    highlight: String(Theme.highlightColor),
                    fontFamily: Theme.fontFamily
                }));
            else
                tab.readerFailed(qsTr("This page cannot be shown in reader mode"));
        });
    }

    // ---- Shoal Keys ------------------------------------------------------

    // Keys comes up, the person unlocks if needed and picks the login.
    function fillLogin(entryId: var): void {
        Pacific.keysFill(tabId, String(view.url), entryId || "");
    }

    // ---- The view --------------------------------------------------------

    // Nothing of the browser's is over the page (BrowserPage): its frames
    // may go straight to the compositor (webview/src/directsurface.h).
    property bool directAllowed: false
    // The floating toolbar's height while it is up (BrowserPage).
    property real obscuredBottom: 0
    // A swipe back or forward has put the page it leads to over this one
    // until that page draws (BrowserPage): the blur of the page left is
    // not wanted under it.
    property bool navCovering: false
    property real _insetChangedAt: 0
    onObscuredBottomChanged: _insetChangedAt = Date.now()
    // What swipes are measured in (BrowserPage, which moves the page with
    // the finger: WebView.swipeFrame).
    property Item swipeFrame: null

    // A picture of the page as it is, for swiping back (or forward) to it
    // later (WebView.captureHistoryPicture): when a page starts to be left,
    // and refreshed once it has loaded and when scrolling stops, so the
    // picture is where the person left it. Only the tab in front: the
    // engine snapshots a background view as whatever was last on screen.
    function capturePicture(): void {
        if (current && view.webProcessRunning && String(view.url) !== "" && !newTabPage) {
            view.captureHistoryPicture();
            pictureTimer.stop();
        }
    }
    Timer {
        id: pictureTimer
        interval: 800
        onTriggered: tab.capturePicture()
    }

    // Cookie-banner answers (autoconsent), kept out of the sites whose
    // shields are down: added again whenever that list changes. From
    // document start, so a consent dialog it knows is hidden before it
    // draws: at document end The Verge's showed, was hidden, and came back
    // before it was rejected.
    property int _consentScript: 0
    function _installConsent(): void {
        if (_consentScript)
            view.removeUserScript(_consentScript);
        _consentScript = view.addUserScript(Pacific.autoconsentScript, "", WebView.DocumentStart, true, JSON.parse(Pacific.shieldsDownSites || "[]"));
    }
    Connections {
        target: Pacific
        enabled: tab._consentScript !== 0
        function onShieldsDownSitesChanged() {
            tab._installConsent();
        }
    }

    // Behind a pinch's preview, while the page is zoomed out of what was
    // drawn: the page's colour, not the wallpaper, until WebKit draws the
    // rest.
    Rectangle {
        anchors.fill: view
        visible: view.zooming
        color: view.themeColor !== "" ? view.themeColor : Theme.lightPrimaryColor
    }

    WebView {
        id: view
        anchors.fill: parent
        // Not while a page change shows: the subsurface is above everything.
        directComposite: tab.current && tab.directAllowed && !leaving.shown
        obscuredBottom: tab.obscuredBottom
        pullDistance: Theme.paddingLarge * 2
        onPulledDown: tab.pulledDown()
        onPullMoved: function (distance) {
            tab.pullMoved(distance);
        }
        onPullEnded: function (distance, velocity) {
            tab.pullEnded(distance, velocity);
        }
        onSwipeNavMoved: function (dx) {
            tab.navMoved(dx);
        }
        onSwipeNavEnded: function (dx, velocity) {
            tab.navEnded(dx, velocity);
        }
        swipeFrame: tab.swipeFrame
        profile: tab.isPrivate ? WebEngine.privateProfile : WebEngine.defaultProfile
        // The front tab and nothing else: the view itself handles being
        // minimised to the cover (webview README, "Page visibility").
        active: tab.current
        javascriptEnabled: tab.browser ? tab.browser.settings.javascript : true
        desktopMode: tab.browser ? tab.browser.settings.desktop_mode : false
        mediaNeedsUserGesture: tab.browser ? !tab.browser.settings.autoplay : true

        Component.onCompleted: {
            // Autoconsent reports to its own handler in the page's world
            // (pacific-core autoconsent.rs): the page's console is never
            // forwarded.
            if (tab.browser && tab.browser.settings.cookie_banners && Pacific.autoconsentScript.length > 0) {
                registerScriptMessageHandler("shipConsent", "");
                tab._installConsent();
            }
            if (!tab.isPrivate && tab.browser && tab.browser.settings.keys_autofill) {
                registerScriptMessageHandler("shipLogin", "pacific");
                addUserScript(Pacific.loginWatcher(), "pacific", WebView.DocumentEnd, true);
            }
            setFeatureEnabled("HiddenPageDOMTimerThrottling", true);
            setFeatureEnabled("HiddenPageCSSAnimationSuspension", true);
        }

        onUrlChanged: {
            if (tab._parked)
                return;
            if (String(url) !== tab.url && !Logic.isReaderUrl(url))
                tab.tabModel.update(tab.tabId, JSON.stringify({
                    url: String(url)
                }));
        }
        onTitleChanged: {
            if (tab._parked)
                return;
            tab.tabModel.update(tab.tabId, JSON.stringify({
                title: title
            }));
            if (!Logic.isReaderUrl(url))
                Pacific.setPageTitle(String(url), title, tab.isPrivate);
        }
        // The model's progress is for Pilot and the session, which need no
        // more than quarters: every tick (dozens a load) went through JSON,
        // the model and every view of it, the cover included. The toolbar
        // follows the view itself.
        onLoadProgressChanged: {
            if (loadProgress === 0 || loadProgress === 100 || Math.abs(loadProgress - tab._sentProgress) >= 25) {
                tab._sentProgress = loadProgress;
                tab.tabModel.update(tab.tabId, JSON.stringify({
                    progress: loadProgress
                }));
            }
        }
        onLoadingStateChanged: tab.tabModel.update(tab.tabId, JSON.stringify({
            loading: loading
        }))
        onAudioPlayingChanged: {
            tab.tabModel.update(tab.tabId, JSON.stringify({
                audible: audioPlaying
            }));
            if (tab.browser)
                tab.browser.audioChanged();
        }

        onLoadingChanged: function (request) {
            var u = String(request.url);
            switch (request.status) {
            case LoadRequest.Started:
                tab.loadError = null;
                tab.certificateProblem = null;
                if (Logic.insecure(u)) {
                    var step = JSON.parse(Pacific.httpsNavigate(tab.tabId, u));
                    if (step.action === "load") {
                        view.stop();
                        view.load(step.url);
                        return;
                    }
                }
                // The page being left, as it is now (a redirect or a
                // reload re-takes the same entry's picture: harmless).
                tab.capturePicture();
                Pacific.pageStarted(tab.tabId, u);
                if (Pacific.httpsPending(tab.tabId))
                    httpsTimer.restart();
                break;
            case LoadRequest.Committed:
                if (!Logic.isReaderUrl(u)) {
                    Pacific.cosmetic(tab.tabId, u);
                    Pacific.loadSiteSettings(u, tab.isPrivate);
                }
                break;
            case LoadRequest.Succeeded:
                httpsTimer.stop();
                Pacific.httpsFinished(tab.tabId, u);
                if (!Logic.isReaderUrl(u) && u.indexOf("http") === 0) {
                    Pacific.recordVisit(u, view.title, tab.transition, tab.isPrivate);
                    if (view.icon.toString() !== "")
                        Pacific.setPageIcon(u, String(view.icon), tab.isPrivate);
                }
                tab.transition = "link";
                tab.tabModel.update(tab.tabId, JSON.stringify({
                    live: true,
                    url: Logic.isReaderUrl(u) ? tab.url : u
                }));
                // Woken: back where the person was (when the engine's own
                // history did not put the page there already).
                if (tab._waking && tab.scrollY > 0)
                    view.runJavaScript("if (window.scrollY < 1) window.scrollTo(0, " + Math.round(tab.scrollY) + ")");
                tab._waking = false;
                // A picture for the tab overview and the swipe peek, also
                // for tabs loaded behind (WebKit snapshots off-screen views).
                thumbTimer.restart();
                pictureTimer.restart();
                if (tab.browser)
                    tab.browser.pageChanged();
                if (tab.browser && tab.browser.settings.keys_autofill && !tab.isPrivate)
                    view.runJavaScriptInWorld(Pacific.loginDetector(), "pacific", function (r) {
                        var d = r ? JSON.parse(r) : {};
                        tab.pendingLogin = null;
                        // Which logins Keys has for the site (only names,
                        // only while it is open); the bar appears with them.
                        if (d.login)
                            Pacific.keysLogins(tab.tabId, u);
                    });
                break;
            case LoadRequest.Failed:
                tab._waking = false;
                httpsTimer.stop();
                var s = JSON.parse(Pacific.httpsFailed(tab.tabId));
                if (s.action === "interstitial")
                    tab.interstitial = s;
                else if (request.errorCode !== 302 && request.errorString !== "")
                    tab.loadError = {
                        url: u,
                        error: request.errorString
                    };
                break;
            default:
                break;
            }
        }

        onCertificateError: function (url, host, errors, pem) {
            tab.certificateProblem = {
                url: String(url),
                host: host,
                pem: pem
            };
        }

        onNewWindowRequested: function (request) {
            if (!request.userInitiated)
                // a popup nobody asked for stays blocked
                return;
            var id = tab.browser.open("about:blank", {
                newTab: true,
                private: tab.isPrivate,
                background: false
            });
            var t = tab.browser.view(id);
            if (t && !request.openIn(t.webView))
                t.go(String(request.url), "link");
        }

        onCloseRequested: tab.browser.close(tab.tabId, tab.isPrivate)

        onPermissionRequested: function (request) {
            var key = Logic.permissionSetting(request.kind);
            var perms = tab.siteSettings.permissions || [];
            for (var i = 0; i < perms.length; ++i) {
                if ("perm." + perms[i][0] === key) {
                    if (perms[i][1] === "allow")
                        request.allow();
                    else
                        request.deny();
                    return;
                }
            }
            if (request.kind === PermissionRequest.MediaKeySystem || request.kind === PermissionRequest.WebsiteDataAccess || request.kind === PermissionRequest.Other) {
                request.deny();
                return;
            }
            tab.pendingPermission = request;
        }

        onScriptDialogRequested: function (dialog) {
            tab.pageStack.push(Qt.resolvedUrl("../pages/ScriptDialogPage.qml"), {
                request: dialog,
                origin: Logic.host(view.url)
            });
        }

        onFileChooserRequested: function (request) {
            tab.pageStack.push(Qt.resolvedUrl("../pages/FileChooserPage.qml"), {
                request: request
            });
        }

        onAuthenticationRequested: function (request) {
            tab.pageStack.push(Qt.resolvedUrl("../pages/AuthDialog.qml"), {
                request: request
            });
        }

        onSelectMenuRequested: function (options, selectedIndex, rect) {
            tab.pageStack.push(Qt.resolvedUrl("../pages/SelectMenuPage.qml"), {
                options: options,
                selectedIndex: selectedIndex,
                view: view
            });
        }

        onInputPickerRequested: function (type, value, min, max, step, rect) {
            tab.pageStack.push(Qt.resolvedUrl("../pages/InputPickerPage.qml"), {
                type: type,
                value: value,
                view: view
            });
        }

        // A word or passage selected with a long press: its actions (copy,
        // share, search) once the selection has settled.
        onSelectionChanged: selectionSettle.restart()
        onContextMenuRequested: function (info) {
            selectionSettle.stop();
            tab.browser.showLinkMenu(tab, info);
        }

        onWebProcessTerminated: function (reason) {
            // Discarded or crashed: the tab keeps its address and title.
            tab._parked = true;
            if (reason === WebView.TerminatedByApi) {
                tab.tabModel.update(tab.tabId, JSON.stringify({
                    live: false
                }));
            } else {
                tab.crashed = true;
                tab.tabModel.update(tab.tabId, JSON.stringify({
                    live: false
                }));
            }
        }

        onScrollChanged: function (y, contentHeight, viewportHeight) {
            // A move the page made because the view changed size (the
            // toolbar sliding away at the end of a page) is not the
            // person scrolling: it must not bring the toolbar back. Only
            // just after the change: a change with no scroll at the time
            // (the bar went once a fling had stopped) left the next real
            // scroll, with the new size, ignored too. Reported once the tab
            // has the new position: the toolbar's end-of-page check reads it.
            var byPerson = tab.lastViewportHeight === 0 || viewportHeight === tab.lastViewportHeight || Date.now() - tab._insetChangedAt > 500;
            var dy = y - tab.lastScrollY;
            tab.lastViewportHeight = viewportHeight;
            tab.lastContentHeight = contentHeight;
            tab.lastScrollY = y;
            if (byPerson)
                tab.scrolled(dy);
            // Scrolling has stopped once no report comes for a while.
            pictureTimer.restart();
            tab._lastScrollAt = Date.now();
            // The session keeps the scroll position (coarsely: no model
            // update for every frame of a fling).
            if (Math.abs(y - tab.scrollY) > viewportHeight / 2)
                tab.tabModel.update(tab.tabId, JSON.stringify({
                    scrollY: y
                }));
        }

        onScriptMessage: function (name, message) {
            if (name === "shipLogin" && message && message.password)
                tab.pendingSave = {
                    url: String(view.url),
                    username: String(message.username || ""),
                    password: String(message.password)
                };
            else if (name === "shipConsent" && message)
                Pacific.consentReport(tab.tabId, JSON.stringify(message), tab.isPrivate);
        }

        onFullscreenRequested: function (fullscreen) {
            if (tab.browser)
                tab.browser.fullscreen = fullscreen;
        }
    }

    // A page change: the page being left, as it was on screen, blurs in
    // place while the next one loads, and the next one's first frame fades
    // in over it. The old page's own frames were garbled once the new one
    // committed (its buffers go), and a blank made the wait feel longer.
    // A quick change (back to a cached page) is over before the blur shows.
    PageTransition {
        id: leaving
        anchors.fill: view
        view: view
        changing: view.pageBlanked && !tab.navCovering
        z: view.z + 1
    }

    // A woken tab shows its last picture until the page has loaded.
    Image {
        objectName: "wakePicture"
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        visible: tab._waking && tab.thumbnail !== "" && !tab.isPrivate
        source: visible ? tab.thumbnail : ""
        height: implicitWidth > 0 ? width * implicitHeight / implicitWidth : 0
        fillMode: Image.Stretch
        asynchronous: true
    }

    // What the engine blocked on the page (WebView.blockedRequest, from the
    // engine's content filters), for the shield's count. Connected loosely:
    // engines without the signal simply count nothing.
    Connections {
        target: view
        ignoreUnknownSignals: true
        function onBlockedRequest(url) {
            Pacific.requestBlocked(tab.tabId, String(url));
        }
    }

    Timer {
        id: selectionSettle
        interval: 500
        onTriggered: {
            if (tab.current && view.selectedText !== "")
                tab.browser.showLinkMenu(tab, {
                    selectionText: view.selectedText,
                    source: "selection"
                });
        }
    }

    // The visible area changed (the tab came to the front): a fresh
    // thumbnail a little later.
    Timer {
        id: thumbTimer
        interval: 1200
        // Not while the page moves: the grab reads the frame back on the
        // GPU and encodes it, and a fling has better uses for both (as the
        // stock browser now defers its captures).
        onTriggered: {
            if (Date.now() - tab._lastScrollAt < 600)
                restart();
            else
                tab.saveThumbnail();
        }
    }

    Timer {
        id: httpsTimer
        interval: 3000
        onTriggered: {
            var s = JSON.parse(Pacific.httpsTimeout(tab.tabId));
            if (s.action === "interstitial") {
                view.stop();
                tab.interstitial = s;
            }
        }
    }

    // The picture is taken before the tab leaves the front
    // (Browser.leavingFront): a hidden view cannot be snapshotted.
    onCurrentChanged: {
        if (current)
            wake();
    }

    // ---- Answers from the core -------------------------------------------

    Connections {
        target: Pacific
        function onCosmeticReady(tabId, url, css, script, extra) {
            if (tabId !== tab.tabId || url !== String(view.url))
                return;
            if (css.length > 0)
                view.runJavaScriptInWorld("(function (css) { var s = document.createElement('style'); s.textContent = css; (document.head || document.documentElement).appendChild(s) })(" + JSON.stringify(css) + ")", "pacific");
            if (script.length > 0)
                view.runJavaScript(script);
        }
        function onIconCached(url, fileUrl) {
            if (url === String(view.url) || url === tab.url)
                tab.tabModel.update(tab.tabId, JSON.stringify({
                    icon: fileUrl
                }));
        }
        function onSiteSettingsLoaded(url, json) {
            if (url !== String(view.url))
                return;
            var s = JSON.parse(json);
            tab.siteSettings = s;
            var defaultZoom = tab.browser ? tab.browser.settings.default_zoom : 1.0;
            view.zoomFactor = s.zoom !== null && s.zoom !== undefined ? s.zoom : defaultZoom;
            var js = s.javascript !== null && s.javascript !== undefined ? s.javascript : (tab.browser ? tab.browser.settings.javascript : true);
            if (view.javascriptEnabled !== js)
                view.javascriptEnabled = js;
            var desktop = s.desktop !== null && s.desktop !== undefined ? s.desktop : (tab.browser ? tab.browser.settings.desktop_mode : false);
            if (view.desktopMode !== desktop) {
                view.desktopMode = desktop;
                view.reload();
            }
        }
        function onReaderReady(tabId, ok, fileUrl, json) {
            if (tabId !== tab.tabId)
                return;
            if (ok)
                view.load(fileUrl);
            else
                tab.readerFailed(JSON.parse(json).error || qsTr("This page cannot be shown in reader mode"));
        }
        function onKeysLoginsReady(tabId, json, error) {
            if (tabId !== tab.tabId)
                return;
            var logins = JSON.parse(json);
            if (error.indexOf("locked") >= 0)
                tab.pendingLogin = {
                    url: String(view.url),
                    logins: [],
                    locked: true
                };
            else if (error.length === 0 && logins.length > 0)
                tab.pendingLogin = {
                    url: String(view.url),
                    logins: logins,
                    locked: false
                };
        }
        function onKeysSaved(status) {
            if (status === "saved" || status === "updated")
                Notices.show(status === "saved" ? qsTr("Login saved in Shoal Keys") : qsTr("Password updated in Shoal Keys"));
        }
        function onKeysFillReady(tabId, script, error) {
            if (tabId !== tab.tabId)
                return;
            // The login was chosen (or the choice declined) in Shoal Keys:
            // come back to the page without the person switching apps.
            if (Qt.application.state !== Qt.ApplicationActive && tab.browser && tab.browser.window)
                tab.browser.window.activate();
            if (error.length > 0)
                Notices.show(error);
            else
                view.runJavaScriptInWorld(script, "pacific");
        }
    }

    Component.onCompleted: {
        if (browser)
            browser.register(tabId, tab);
        if (current)
            wake();
    }
    Component.onDestruction: {
        if (browser)
            browser.unregister(tabId, tab);
    }
}
