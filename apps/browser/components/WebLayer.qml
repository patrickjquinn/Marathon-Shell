pragma ComponentBehavior: Bound

import QtQuick
import QtWebEngine
import MarathonApp.Browser

// The tabs' web views, one per row of browser.tabs; only the current one shows.
Item {
    id: root

    property var browser
    property alias normalProfile: normalProfile
    property alias privateProfile: privateProfile

    signal scrolled(real y)

    function currentView() {
        const tab = repeater.itemAt(browser.currentTabIndex) as BrowserTab;
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
        const tab = repeater.itemAt(index) as BrowserTab;
        if (!tab)
            return;
        tab.view.lifecycleState = WebEngineView.LifecycleState.Discarded;
        tab.view.stop();
    }

    function capture() {
        const tab = repeater.itemAt(browser.currentTabIndex) as BrowserTab;
        if (tab)
            tab.capture();
    }

    function clearSiteData() {
        return BrowserData.clearCookiesAndCache(normalProfile) && BrowserData.clearCookiesAndCache(privateProfile);
    }

    WebEngineProfile {
        id: normalProfile

        httpUserAgent: "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
        Component.onCompleted: {
            storageName = "normal";
            offTheRecord = false;
            httpCacheType = WebEngineProfile.DiskHttpCache;
            persistentCookiesPolicy = WebEngineProfile.AllowPersistentCookies;
        }
    }

    WebEngineProfile {
        id: privateProfile

        httpUserAgent: normalProfile.httpUserAgent
        Component.onCompleted: {
            offTheRecord = true;
            httpCacheType = WebEngineProfile.MemoryHttpCache;
            persistentCookiesPolicy = WebEngineProfile.NoPersistentCookies;
        }
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
