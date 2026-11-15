// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// The browser's state, shared by every page: the tab models (normal and
// private), the web views by tab id, opening and closing tabs, the session
// save, the tab lifecycle (discarding background tabs), content filters
// and clearing data in the engine. One instance, made by the window.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Shipwright.Pacific 1.0
import Shipwright.Pacific.WebView 1.0
import "../js/logic.js" as Logic

Item {
    id: browser

    readonly property alias normalTabs: normalModel
    readonly property alias privateTabs: privateModel
    // Showing the private tabs (the tab grid's switch, a new private tab).
    property bool privateMode: false
    readonly property TabModel tabs: privateMode ? privateModel : normalModel
    readonly property int currentId: tabs.activeId
    // The WebTab of the tab in front (null on the new-tab page of an empty model).
    readonly property var currentTab: _views[currentId] || null
    // tab id -> WebTab
    property var _views: ({})
    // The parsed global settings.
    readonly property var settings: JSON.parse(Pacific.settings)
    // The application window (set by it): its page stack and activate().
    property var window

    function bringToFront(): void {
        if (window)
            window.activate();
    }
    readonly property var pageStack: window ? window.pageStack : null
    // Pilot's background tab, if any (see actions/PacificActions.qml).
    property var agentView: null
    // A page asked for fullscreen (video): the toolbar hides.
    property bool fullscreen: false
    function exitFullscreen(): void {
        var t = currentTab;
        if (t)
            t.webView.runJavaScript("document.fullscreenElement && document.exitFullscreen()");
        fullscreen = false;
    }

    // A long press on a link or image in `tab` (BrowserPage shows the menu).
    signal linkMenuRequested(var tab, var info)
    // The address sheet, from outside the browser page (the cover's search).
    signal addressRequested
    // Back from the tab overview to the browser page, which grows the page
    // back from the overview (BrowserPage) instead of the stack's slide.
    signal tabsReturned
    function returnFromTabs(): void {
        if (pageStack)
            pageStack.pop(pageStack.find(function (p) {
                return p.objectName === "browserPage";
            }), PageStackAction.Immediate);
        tabsReturned();
    }
    function openAddress(): void {
        if (pageStack)
            pageStack.pop(pageStack.find(function (p) {
                return p.objectName === "browserPage";
            }), PageStackAction.Immediate);
        addressRequested();
    }

    function showLinkMenu(tab: var, info: var): void {
        linkMenuRequested(tab, info);
    }

    TabModel {
        id: normalModel
        privateTabs: false
    }
    TabModel {
        id: privateModel
        privateTabs: true
    }

    function register(tabId: var, item: var): void {
        var v = _views;
        v[tabId] = item;
        _views = v;
    }

    function unregister(tabId: var, item: var): var {
        if (_views[tabId] !== item)
            return;
        var v = _views;
        delete v[tabId];
        _views = v;
    }

    function view(tabId: var): var {
        return _views[tabId] || null;
    }

    function modelOf(isPrivate: var): var {
        return isPrivate ? privateModel : normalModel;
    }

    // ---- Opening ---------------------------------------------------------

    // The tab in front is about to leave it: its picture now, while the
    // view is still shown (a hidden view cannot be snapshotted).
    function leavingFront(): void {
        var t = currentTab;
        if (t && !t.isPrivate && t.live && !t.newTabPage)
            t.saveThumbnail();
    }

    // Opens `url` (already a URL: see navigate() for typed text).
    // opts: { newTab, private, background, transition }
    function open(url: var, opts: var): var {
        opts = opts || {};
        var isPrivate = opts.private !== undefined ? opts.private : privateMode;
        var model = modelOf(isPrivate);
        if (opts.newTab || model.count === 0) {
            if (!opts.background)
                leavingFront();
            var id = model.addTab(url, "", opts.background === true);
            if (!opts.background)
                privateMode = isPrivate;
            var t = view(id);
            if (t) {
                t.transition = opts.transition || "link";
                if (opts.background)
                    t.wake();
            }
            return id;
        }
        var cur = view(model.activeId);
        if (cur)
            cur.go(url, opts.transition || "link");
        return model.activeId;
    }

    // Handles text from the address bar: an address or a search.
    function navigate(text: var, opts: var): var {
        var nav = JSON.parse(Pacific.classify(text));
        if (!nav.url)
            return false;
        opts = opts || {};
        opts.transition = "typed";
        if (nav.kind === "search")
            Pacific.recordSearch(nav.query, nav.engine, opts.private !== undefined ? opts.private : privateMode);
        open(nav.url, opts);
        return true;
    }

    // A new tab showing the new-tab page.
    function newTab(isPrivate: var): var {
        leavingFront();
        privateMode = isPrivate === true;
        var id = modelOf(privateMode).addTab("", "", false);
        return id;
    }

    function switchTo(tabId: var, isPrivate: var): void {
        if (tabId !== currentId || (isPrivate !== undefined && isPrivate !== privateMode))
            leavingFront();
        if (isPrivate !== undefined)
            privateMode = isPrivate;
        tabs.activate(tabId);
        lifecycleTimer.restart();
    }

    function close(tabId: var, isPrivate: var): void {
        var model = modelOf(isPrivate !== undefined ? isPrivate : privateMode);
        Pacific.tabClosed(tabId);
        model.closeTab(tabId);
        if (model === privateModel && privateModel.count === 0) {
            // The last private tab: nothing of the session may remain.
            WebEngine.privateProfile.clearData(WebProfile.AllData, 0);
            if (privateMode)
                privateMode = false;
        }
        saveTimer.restart();
    }

    function closeAll(isPrivate: var): void {
        var model = modelOf(isPrivate);
        while (model.count > 0)
            close(model.idAt(0), isPrivate);
    }

    function reopenClosed(): var {
        leavingFront();
        privateMode = false;
        var id = normalModel.reopenClosed();
        saveTimer.restart();
        return id;
    }

    // ---- Session ---------------------------------------------------------

    function restore(): void {
        _applyEngineSettings(); // before the first view loads anything
        var s = Pacific.savedSession;
        var restoring = s.length > 0 && (settings.restore === "always" || (settings.restore === "crash" && Pacific.crashed));
        if (restoring)
            normalModel.restore(s);
        if (normalModel.count === 0)
            normalModel.addTab("", "", false);
        if (restoring && Pacific.crashed)
            Notices.show(qsTr("Pacific closed unexpectedly. Your tabs are back."));
    }

    function saveSession(): void {
        // The engine's back/forward lists go with the tabs.
        for (var i = 0; i < normalModel.count; ++i) {
            var t = view(normalModel.idAt(i));
            if (t)
                t.storeEngineState();
        }
        Pacific.saveSession(normalModel.sessionJson());
    }

    Timer {
        id: saveTimer
        interval: 2000
        onTriggered: browser.saveSession()
    }

    Connections {
        target: normalModel
        function onCountChanged() {
            saveTimer.restart();
        }
        function onActiveIdChanged() {
            saveTimer.restart();
        }
    }

    // Called by tabs when a page finished loading.
    function pageChanged(): void {
        saveTimer.restart();
    }

    // ---- Tab lifecycle ---------------------------------------------------

    function applyLifecycle(): void {
        var models = [normalModel, privateModel];
        for (var m = 0; m < models.length; ++m) {
            var model = models[m];
            var decisions = JSON.parse(Pacific.lifecycle(model.lifecycleJson()));
            for (var i = 0; i < decisions.length; ++i) {
                var d = decisions[i];
                var t = view(d.tab);
                if (!t)
                    continue;
                if (d.action === "discard")
                    t.discard();
                else if (d.action === "reload" && model === tabs)
                    t.wake();
            }
        }
    }

    Timer {
        id: lifecycleTimer
        interval: 1500
        onTriggered: browser.applyLifecycle()
    }

    Timer {
        interval: 30000
        repeat: true
        running: Qt.application.state === Qt.ApplicationActive || Qt.application.state === Qt.ApplicationInactive
        onTriggered: browser.applyLifecycle()
    }

    // ---- Content filters, clearing data ----------------------------------

    property var _activeFilters: []

    function _profiles(): var {
        return [WebEngine.defaultProfile, WebEngine.privateProfile];
    }

    // Engine-wide settings follow the browser's: Global Privacy Control on
    // both profiles (the `Sec-GPC` header and navigator.globalPrivacyControl)
    // and spell checking. No chosen dictionaries means the engine's own
    // choice, the phone's language, remembered at start.
    property var _defaultSpelling: null
    function _applyEngineSettings(): void {
        var ps = _profiles();
        for (var i = 0; i < ps.length; ++i)
            ps[i].globalPrivacyControl = settings.global_privacy_control;
        if (_defaultSpelling === null)
            _defaultSpelling = WebEngine.spellCheckingLanguages;
        WebEngine.spellChecking = settings.spell_check;
        WebEngine.darkMode = settings.color_scheme === "dark" || (settings.color_scheme !== "light" && Theme.colorScheme === Theme.LightOnDark);
        var langs = settings.spell_languages || [];
        WebEngine.spellCheckingLanguages = langs.length > 0 ? langs : _defaultSpelling;
    }
    // Websites follow the ambience (Settings, Website colours) when it changes.
    Connections {
        target: Theme
        function onColorSchemeChanged() {
            browser._applyEngineSettings();
        }
    }
    // (After `settings` has the new values: a handler on Pacific's signal
    // could run before this binding is updated.)
    onSettingsChanged: {
        _applyEngineSettings();
        syncFilters();
        if (settings.blocking !== _lastBlocking) {
            _lastBlocking = settings.blocking;
            reloadForFilters();
        }
    }

    Connections {
        target: Pacific
        function onContentFilterCompile(identifier, json) {
            if (!browser.settings.blocking)
                // compiled when blocking is turned on (it stays unconfirmed)
                return;
            // Asked for again (each profile reports a filter its store lost)
            // while it compiles: one compile, whose result is reported.
            if (browser._compiling[identifier])
                return;
            browser._compiling[identifier] = true;
            var ps = browser._profiles();
            var left = ps.length, allOk = true;
            for (var i = 0; i < ps.length; ++i) {
                ps[i].compileContentFilter(identifier, json, function (ok, error) {
                    if (!ok) {
                        allOk = false;
                        // (Dropped on purpose when blocking went off meanwhile.)
                        if (browser.settings.blocking)
                            console.warn("content filter " + identifier + ": " + error);
                    }
                    if (--left === 0) {
                        delete browser._compiling[identifier];
                        // Recorded as compiled only now, once each store has it.
                        Pacific.contentFilterResult(identifier, allOk);
                        browser._filtersSettled();
                    }
                });
            }
        }
        function onContentFiltersActive(idsJson) {
            browser._activeFilters = JSON.parse(idsJson);
            browser.syncFilters();
            browser._filtersSettled();
        }
        function onDataCleared(json) {
            var e = JSON.parse(json);
            var types = Logic.clearTypes(e, {
                cookies: WebProfile.Cookies,
                cache: WebProfile.Cache,
                localStorage: WebProfile.LocalStorage,
                indexedDb: WebProfile.IndexedDb,
                serviceWorkers: WebProfile.ServiceWorkers
            });
            if (types !== 0)
                WebEngine.defaultProfile.clearData(types, Logic.sinceSeconds(e.since_ms, Date.now()));
            Notices.show(qsTr("Browsing data cleared"));
        }
        function onOpenUrlRequested(url) {
            // A link from another app opens in a new tab, unless the tab in
            // front is an untouched new tab (as after starting the browser
            // for the link): that one is used, not left behind empty.
            var cur = browser.privateMode ? null : browser.view(browser.normalTabs.activeId);
            var blank = cur !== null && cur.newTabPage && !cur.webView.canGoBack;
            var t = browser.view(browser.open(url, {
                newTab: !blank,
                private: false
            }));
            // Back from its first page closes it and returns to the caller.
            if (t)
                t.openedByApp = true;
            if (browser.pageStack)
                browser.pageStack.pop(browser.pageStack.find(function (p) {
                    return p.objectName === "browserPage";
                }), PageStackAction.Immediate);
            browser.bringToFront();
        }
        function onRaiseRequested() {
            browser.bringToFront();
        }
        function onNotice(text) {
            Notices.show(text);
        }
    }

    // Filters being compiled now (id -> true), so a failed load does not
    // start a second compile.
    property var _compiling: ({})

    // Filters wanted but not in force in a profile: blocking is incomplete
    // until they are (the shield says so; never "on" with a list missing).
    readonly property var missingFilters: {
        if (!settings.blocking)
            return [];
        var want = _activeFilters, out = [];
        var ps = _profiles();
        for (var p = 0; p < ps.length; ++p) {
            var have = ps[p].contentFilters;
            for (var i = 0; i < want.length; ++i)
                if (have.indexOf(want[i]) < 0 && out.indexOf(want[i]) < 0)
                    out.push(want[i]);
        }
        return out;
    }
    readonly property bool protectionIncomplete: Pacific.blockerReady && missingFilters.length > 0

    // Turns a filter off or on in a profile, keeping it in the engine's
    // store (disableContentFilter / enableContentFilter). Either takes
    // effect from the next page load (see reloadForFilters).
    function _setFilter(profile: var, id: var, on: var): void {
        if (!on) {
            profile.disableContentFilter(id);
            return;
        }
        profile.enableContentFilter(id, function (ok, error) {
            if (ok)
                Pacific.contentFilterResult(id, true);
            else if (!browser._compiling[id])
                Pacific.contentFilterResult(id, false); // missing from the store: compile again
            browser._filtersSettled();
        });
    }

    // Blocking turned on or off, or a site's exception changed: the page in
    // front is loaded again once the filters are in place, so the change
    // shows at once (filters apply from the next load).
    property bool _reloadPending: false
    // The blocking setting as last applied (a value, not a binding).
    property bool _lastBlocking: true
    Component.onCompleted: _lastBlocking = settings.blocking
    function reloadForFilters(): void {
        _reloadPending = true;
        _filtersSettled();
    }
    // A site's exception changed: its filters are converted and compiled
    // again; the page reloads once they are in place.
    function reloadAfterRefilter(): void {
        _reloadPending = true;
    }
    function _filtersSettled(): var {
        if (!_reloadPending || Object.keys(_compiling).length > 0)
            return;
        _reloadPending = false;
        var t = currentTab;
        if (t && t.webView && String(t.webView.url).indexOf("http") === 0)
            t.webView.reload();
    }

    // At every start and every change: each wanted filter in force in both
    // profiles (loaded from the store, or compiled again when the store has
    // lost it), the others off; all of them off when blocking is off.
    function syncFilters(): void {
        var want = settings.blocking ? _activeFilters : [];
        var ps = _profiles();
        // Filters still compiling count as there: disabling one now drops
        // it when it finishes (a late compile cannot turn blocking back on).
        var compiling = Object.keys(_compiling);
        for (var p = 0; p < ps.length; ++p) {
            var have = ps[p].contentFilters.concat(compiling);
            for (var i = 0; i < have.length; ++i)
                if (want.indexOf(have[i]) < 0)
                    _setFilter(ps[p], have[i], false);
            for (var j = 0; j < want.length; ++j)
                if (have.indexOf(want[j]) < 0)
                    _setFilter(ps[p], want[j], true);
        }
    }

    // ---- Downloads ---------------------------------------------------------

    // Every download of either profile (from a page, a link menu or "try
    // again"): saved under a free name in the downloads directory and
    // recorded, with progress, in the downloads list. The name is chosen
    // once the server's is known (Content-Disposition): the engine tells it
    // just before it needs the destination, after the download has started.
    property var _downloads: []
    // The runner's background tasks (manifest backgroundCapabilities), so
    // the app is not frozen while a download runs or a page plays sound.
    property var _tasks: ({})
    function _hold(category: string, reason: string, on: bool): void {
        // qmllint disable unqualified
        if (typeof AppLifecycle === "undefined" || !AppLifecycle)
            return;
        var handle = _tasks[category] || 0;
        if (on && handle === 0) {
            _tasks[category] = AppLifecycle.beginBackgroundTask(category, reason);
        } else if (!on && handle !== 0) {
            AppLifecycle.endBackgroundTask(handle);
            _tasks[category] = 0;
        }
        // qmllint enable unqualified
    }
    function _holdForDownloads(): void {
        _hold("download", qsTr("Downloading"), _downloads.some(function (d) {
            return d.download.state === Download.InProgress;
        }));
    }
    function audioChanged(): void {
        var playing = false;
        for (var id in _views) {
            if (_views[id] && _views[id].webView.audioPlaying)
                playing = true;
        }
        _hold("audio-playback", qsTr("Playing a page's sound"), playing);
    }

    function _track(download: var, isPrivate: var): var {
        function choose() {
            if (download.destination)
                return;
            download.destination = Pacific.downloadDestination(String(download.url), download.suggestedFilename, download.mimeType, isPrivate);
            Notices.show(qsTr("Downloading %1").arg(download.suggestedFilename || Logic.host(download.url)));
        }
        if (download.suggestedFilename)
            choose();
        else
            download.suggestedFilenameChanged.connect(choose);
        var d = _downloads.slice();
        d.push({
            download: download,
            isPrivate: isPrivate
        });
        _downloads = d;
        _holdForDownloads();
    }

    Connections {
        target: WebEngine.defaultProfile
        function onDownloadStarted(download) {
            browser._track(download, false);
        }
    }
    Connections {
        target: WebEngine.privateProfile
        function onDownloadStarted(download) {
            browser._track(download, true);
        }
    }

    Instantiator {
        model: browser._downloads
        delegate: Connections {
            required property var modelData
            target: modelData.download
            property double _last: 0
            function report() {
                var d = modelData.download;
                var states = ["running", "finished", "failed", "cancelled"];
                Pacific.downloadUpdate(d.destination, d.receivedBytes, d.totalBytes, states[d.state] || "running", d.errorString, modelData.isPrivate);
            }
            function onProgressChanged() {
                var now = Date.now();
                if (now - _last > 500) {
                    _last = now;
                    report();
                }
            }
            function onStateChanged() {
                report();
                browser._holdForDownloads();
                var d = modelData.download;
                if (d.state === Download.Finished)
                    Notices.show(qsTr("Downloaded %1").arg(d.suggestedFilename));
                else if (d.state === Download.Failed)
                    Notices.show(qsTr("Download failed: %1").arg(d.errorString));
            }
        }
    }

    // ---- Pilot's background tab --------------------------------------------

    // Pilot browses in a headless view on the private profile: nothing it
    // does reaches the person's history, cookies or tabs, and it never
    // shows unless the person takes it over.
    Component {
        id: agentComponent
        WebView {
            headless: true
            active: false
            profile: WebEngine.privateProfile
            width: browser.window ? browser.window.width : Theme.itemSizeHuge * 4
            height: browser.window ? browser.window.height : Theme.itemSizeHuge * 7
            onUrlChanged: Pacific.agentVisited(String(url))
        }
    }

    function startAgent(): var {
        if (!agentView) {
            agentView = agentComponent.createObject(browser);
            Pacific.agentStart(-1);
        }
        return agentView;
    }

    function stopAgent(): void {
        if (agentView) {
            agentView.destroy();
            agentView = null;
        }
        Pacific.agentStop();
        if (privateModel.count === 0)
            WebEngine.privateProfile.clearData(WebProfile.AllData, 0);
    }

    // The person takes Pilot's page over: it opens in a private tab (the
    // same private profile, so a login Pilot reached carries over).
    function takeOverAgent(): var {
        if (!agentView)
            return;
        var u = String(agentView.url);
        var state = agentView.sessionState();
        var id = open(u, {
            newTab: true,
            private: true
        });
        var t = view(id);
        if (t && state !== "" && t.webView.restoreSessionState(state))
            t.webView.reload();
        agentView.destroy();
        agentView = null;
        Pacific.agentStop();
    }

    // ---- Freezing ------------------------------------------------------------

    // The runner freezes the app in the background and the system may end
    // it there: the session is kept as a clean exit, and under memory
    // pressure the tabs behind give their web processes back first.
    function prepareFreeze(): void {
        leavingFront();
        for (var i = 0; i < normalModel.count; ++i) {
            var t = view(normalModel.idAt(i));
            if (t)
                t.storeEngineState();
        }
        Pacific.prepareFreeze(normalModel.sessionJson());
        applyLifecycle();
    }

    function thawed(): void {
        Pacific.thawed();
        var t = currentTab;
        if (t)
            t.wake();
        lifecycleTimer.restart();
    }

    // ---- Start and stop --------------------------------------------------

    Connections {
        target: Qt.application
        function onAboutToQuit() {
            browser.saveSession();
            Pacific.shutdown();
        }
        function onStateChanged() {
            if (Qt.application.state !== Qt.ApplicationActive) {
                // The page as it was left, for the cover in the switcher.
                browser.leavingFront();
                browser.saveSession();
            }
        }
    }
}
