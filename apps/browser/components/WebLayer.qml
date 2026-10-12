pragma ComponentBehavior: Bound

import QtQuick
import QtWebEngine
import MarathonApp.Browser

// The tabs' web views, one per row of browser.tabs; only the current one shows.
Item {
    id: root

    property var browser

    signal scrolled(real y)

    function tabAt(index) {
        return repeater.itemAt(index);
    }

    function currentView() {
        const tab = repeater.itemAt(browser.currentTabIndex);
        return tab ? tab.view : null;
    }

    function goBack() {
        const view = currentView();
        if (view && view.canGoBack)
            view.goBack();
    }

    function goForward() {
        const view = currentView();
        if (view && view.canGoForward)
            view.goForward();
    }

    function reloadOrStop() {
        const view = currentView();
        if (!view)
            return;
        if (view.loading) {
            view.triggerWebAction(WebEngineView.Stop);
        } else {
            view.triggerWebAction(WebEngineView.ReloadAndBypassCache);
            view.reload();
        }
    }

    function discard(index) {
        const tab = repeater.itemAt(index);
        if (!tab)
            return;
        tab.view.lifecycleState = WebEngineView.LifecycleState.Discarded;
        tab.view.stop();
    }

    function capture() {
        const tab = repeater.itemAt(browser.currentTabIndex);
        if (tab)
            tab.capture();
    }

    function clearSiteData() {
        return BrowserData.clearCookiesAndCache(normalProfile) && BrowserData.clearCookiesAndCache(privateProfile);
    }

    // Profiles come from prototypes: storage and off-the-record are fixed
    // when the profile is created. Set on a live profile from onCompleted,
    // after a tab had already loaded with it, Chromium hit a CHECK and the
    // browser died on its first page.
    readonly property string userAgent: "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"

    WebEngineProfilePrototype {
        id: normalPrototype

        storageName: "normal"
        httpCacheType: WebEngineProfile.DiskHttpCache
        persistentCookiesPolicy: WebEngineProfile.AllowPersistentCookies
    }

    // No storage name: off the record.
    WebEngineProfilePrototype {
        id: privatePrototype

        httpCacheType: WebEngineProfile.MemoryHttpCache
        persistentCookiesPolicy: WebEngineProfile.NoPersistentCookies
    }

    readonly property WebEngineProfile normalProfile: {
        const profile = normalPrototype.instance();
        profile.httpUserAgent = userAgent;
        return profile;
    }
    readonly property WebEngineProfile privateProfile: {
        const profile = privatePrototype.instance();
        profile.httpUserAgent = userAgent;
        return profile;
    }

    Repeater {
        id: repeater

        model: root.browser.tabs

        BrowserTab {
            width: root.width
            height: root.height
            browser: root.browser
            webLayer: root
        }
    }
}
