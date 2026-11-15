// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// The browser: the tab in front fills the screen, the toolbar sits at the
// bottom within thumb reach and hides while scrolling down. Every tab's web
// view lives here (one Repeater per tab model) so that switching tabs is
// instant; the ones behind are inactive (throttled) or discarded.

pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Sailfish.Silica 1.0 as Silica
import Sailfish.Silica.private 1.0 as SilicaPrivate
import Shipwright.Pacific 1.0
import Shipwright.Pacific.WebView 1.0
import "../components"
import "../js/logic.js" as Logic

Page {
    id: page
    objectName: "browserPage"

    property var browser
    readonly property var tab: browser ? browser.currentTab : null
    readonly property bool showNewTab: !tab || tab.newTabPage
    property bool toolbarShown: true
    property bool finding: false
    property bool readable: false
    // The shield's count: what the engine's content filters blocked on
    // the page in front (reset when a new page starts loading).
    readonly property int blocked: tab && tab.webView ? tab.webView.blockedRequestCount : 0

    // The toolbar is up (or hidden while scrolling down, as in Safari).
    readonly property bool barUp: toolbarShown || showNewTab || !browser.settings.toolbar_autohide
    // The page alone on screen and still: nothing of the browser's is drawn
    // over it (toolbar, menus, prompts, panels) and it is not being swiped
    // or shrunk into the tab overview. Its frames may then go straight to the
    // compositor (PACIFIC_DIRECT), which cannot stack anything above them.
    readonly property bool directAllowed: !barUp && !_barHold && toolbar.y >= page.height - 0.5
            && pullShown === 0
            && status === PageStatus.Active
            && !(pageMenu && pageMenu.open) && !(tabsMenu && tabsMenu.open) && !(linkMenu && linkMenu.visible)
            && prompts.height <= 0 && lift === 0 && swipeX === 0 && navDir === 0 && !navCovering
            && !addressSheet.shown
            && tab !== null && tab.interstitial === null && tab.certificateProblem === null
            && tab.loadError === null && !tab.crashed && !browser.fullscreen
            && Notices._current === null
    readonly property bool barVisible: toolbar.visible
    // An auto-hiding toolbar floats over the page, as Safari's does: the
    // page is laid out at the full height and the bar's slide only reveals
    // or covers it. Resizing the page as the bar slid away made WebKit's main
    // thread lay it out again in the middle of a fling, while the scrolling
    // thread kept moving it: no tiles were painted ahead for that long, and
    // the band the bar uncovered was blank, taller the faster the fling.
    readonly property bool barFloats: browser.settings.toolbar_autohide
    // What the floating bar covers, for the engine: the page can scroll its
    // end clear of it, and position: fixed elements (cookie banners, sites'
    // bottom navigation) sit above it rather than under it, as Safari and
    // Chrome keep them. It follows the bar once scrolling has stopped, as
    // Chrome's does: each change lays the page out again, and in the middle
    // of a fling that held up the scrolling thread for a frame (one frame
    // moved twice as far and the next not at all).
    readonly property real _obscuredWanted: barFloats && barUp && barVisible ? toolbar.height : 0
    property real obscuredBottom: 0
    on_ObscuredWantedChanged: obscuredTimer.restart()
    Timer {
        id: obscuredTimer
        interval: 300
        onTriggered: page.obscuredBottom = page._obscuredWanted
    }
    // A pinned toolbar takes its space from the page: changed once per
    // slide so the page relayouts once, never every frame, and always under
    // the bar: it grows as the bar starts to slide away (the bar still
    // covers the new space) and shrinks once the bar has slid in over it.
    property bool _reserve: true
    readonly property real reservedBottom: barFloats ? 0 : _reserve ? toolbar.height : 0
    function _updateReserve(): void {
        if (barUp && barVisible) {
            _barHold = false
            reserveTimer.restart()
        } else {
            reserveTimer.stop()
            _reserve = false
            // The page has grown under the bar: the bar stays until WebKit
            // has drawn at the new height (about 70 ms), so its slide reveals
            // the page, not a blank band where a frame was still missing.
            if (barVisible && tab && tab.webView && !tab.webView.frameFitsView) {
                _barHold = true
                barHoldTimer.restart()
            }
        }
    }
    property bool _barHold: false
    Timer {
        id: barHoldTimer
        interval: 200
        onTriggered: page._barHold = false
    }
    Connections {
        target: page.tab ? page.tab.webView : null
        function onFrameFitsViewChanged() {
            if (page.tab.webView.frameFitsView)
                page._barHold = false
        }
    }
    onBarUpChanged: _updateReserve()
    onBarVisibleChanged: _updateReserve()
    Timer {
        id: reserveTimer
        interval: 200
        onTriggered: page._reserve = page.barUp && page.barVisible
    }

    // ---- Gestures on the toolbar ------------------------------------------
    // Sideways: the page follows the finger and the neighbouring tab
    // slides in (its last thumbnail), then becomes the tab in front.
    // Upwards: the page shrinks towards the tab overview, which opens past
    // a third of the way. Both are interruptible: a new drag picks up
    // where an animation is.
    property real swipeX: 0
    property real lift: 0
    property int gestureAxis: 0
    property real gestureBase: 0
    property int peekId: 0
    readonly property var peekTab: peekId !== 0 && browser ? JSON.parse(browser.tabs.get(peekId)) : null

    function neighbourFor(dx: var): var {
        return browser.tabs.neighbour(browser.currentId, dx < 0 ? 1 : -1)
    }

    NumberAnimation {
        id: swipeAnim
        target: page
        property: "swipeX"
        duration: 220
        easing.type: Easing.OutCubic
        onFinished: page.swipeSettled()
    }
    NumberAnimation {
        id: liftAnim
        target: page
        property: "lift"
        duration: 200
        easing.type: Easing.OutCubic
        onFinished: page.liftSettled()
    }

    function gestureStarted(): void {
        swipeAnim.stop()
        liftAnim.stop()
        gestureAxis = swipeX !== 0 ? 1 : (lift !== 0 ? 2 : 0)
        gestureBase = gestureAxis === 1 ? swipeX : lift
    }

    function gestureMoved(dx: var, dy: var): var {
        if (gestureAxis === 0) {
            if (Math.abs(dx) > Math.abs(dy))
                gestureAxis = 1
            else if (dy < 0) {
                gestureAxis = 2
                _prepareTabs()
            }
            else
                return
            gestureBase = gestureAxis === 1 ? swipeX : lift
        }
        if (gestureAxis === 1) {
            var x = gestureBase + dx
            peekId = neighbourFor(x)
            // No tab that way: the page resists.
            swipeX = peekId !== 0 ? x : x / 4
        } else {
            lift = Math.max(0, Math.min(1, gestureBase - dy / (page.height * 0.4)))
        }
    }

    function gestureEnded(dx: var, dy: var, vx: var, vy: var): void {
        if (gestureAxis === 1) {
            var flick = Math.abs(vx) > 900 && (vx < 0) === (swipeX < 0)
            var go = peekId !== 0 && (Math.abs(swipeX) > webArea.width / 3 || flick)
            swipeAnim.to = go ? (swipeX < 0 ? -webArea.width : webArea.width) : 0
            swipeAnim.restart()
        } else if (gestureAxis === 2) {
            liftAnim.to = lift > 0.35 || vy < -900 ? 1 : 0
            liftAnim.restart()
        }
        gestureAxis = 0
    }

    function swipeSettled(): void {
        if (Math.abs(swipeX) >= webArea.width - 1 && peekId !== 0) {
            var id = peekId
            peekId = 0
            browser.switchTo(id)
        }
        swipeX = 0
    }

    function liftSettled(): void {
        if (lift >= 0.999) {
            openTabs()
            lift = 0
        }
    }

    // ---- Swipe back and forward on the page ------------------------------
    // The web view hands over a sideways drag the page cannot use
    // (WebView.swipeNavMoved), as Chrome on Android does: the screen's edges
    // are Sailfish's. Back: the page follows the finger off to the right and
    // the page before it lies underneath, coming out from the left. Forward:
    // the next page slides in over this one from the right. Each is the
    // picture taken when that page was left (HistoryPicture). Let go past a
    // third of the way (a tick says so) or flicked, and the picture covers
    // the screen until the page itself has drawn; otherwise everything
    // slides back.
    property real navDx: 0
    property int navDir: 0 // 1 back, -1 forward
    property var navItem: null
    property bool _navGoing: false
    property bool _navArmed: false
    readonly property real navProgress: navDir === 0 || webArea.width <= 0 ? 0 : Math.min(1, Math.abs(navDx) / webArea.width)
    // The page's own movement: all of the finger's going back, a third of
    // it going forward (the next page comes over it).
    readonly property real navPageX: navDir > 0 ? Math.max(0, navDx) : navDir < 0 ? Math.min(0, navDx) / 3 : 0
    // The page it led to, over everything until it has drawn.
    property bool navCovering: false
    property var navCoverItem: null

    function navMoved(dx: var): void {
        if (!tab || !tab.webView)
            return
        navAnim.stop()
        if (navDir === 0) {
            navDir = dx > 0 ? 1 : -1
            navItem = tab.webView.historyItemAt(-navDir)
            _navArmed = false
        }
        // It does not turn into the other way: back to the start at most.
        navDx = navDir > 0 ? Math.max(0, dx) : Math.min(0, dx)
        var armed = Math.abs(navDx) > webArea.width / 3
        if (armed && !_navArmed && _pullFeedback)
            _pullFeedback.play()
        _navArmed = armed
    }
    function navEnded(dx: var, velocity: var): void {
        if (navDir === 0)
            return
        // px per ms; a flick the right way goes, one back cancels.
        var flick = Math.abs(velocity) > 0.5
        var go = flick ? (velocity > 0) === (navDir > 0) : _navArmed
        _navGoing = go && navItem && navItem.key !== undefined
        navAnim.to = _navGoing ? navDir * webArea.width : 0
        navAnim.duration = _navGoing ? Math.max(120, 260 * (1 - navProgress)) : 220
        navAnim.restart()
    }
    function navSettled(): void {
        if (_navGoing && tab && tab.webView) {
            navCoverItem = navItem
            navCovering = true
            navCoverTimeout.restart()
            if (navDir > 0)
                tab.webView.goBack()
            else
                tab.webView.goForward()
        }
        _navGoing = false
        _navArmed = false
        navDir = 0
        navDx = 0
        navItem = null
    }
    NumberAnimation {
        id: navAnim
        target: page
        property: "navDx"
        easing.type: Easing.OutCubic
        onFinished: page.navSettled()
    }
    // The cover goes once the page it shows is the one on screen and has
    // drawn (WebView.pageBlanked is over), or after 4 s whatever happens.
    function _navCoverCheck(): void {
        var v = tab ? tab.webView : null
        if (!navCovering || !v || !navCoverItem)
            return
        if (v.historyKey === navCoverItem.key && !v.pageBlanked && !v.loading)
            navCoverDelay.restart()
        else if (v.historyKey === navCoverItem.key && !v.pageBlanked && v.loadProgress >= 50)
            navCoverDelay.restart()
    }
    Connections {
        target: page.navCovering && page.tab ? page.tab.webView : null
        ignoreUnknownSignals: true
        function onBackForwardChanged() { page._navCoverCheck() }
        function onPageBlankedChanged() { page._navCoverCheck() }
        function onLoadingStateChanged() { page._navCoverCheck() }
        function onLoadProgressChanged() { page._navCoverCheck() }
    }
    // A frame or two for the page's first picture to reach the screen.
    Timer {
        id: navCoverDelay
        interval: 60
        onTriggered: navCoverFade.restart()
    }
    Timer {
        id: navCoverTimeout
        interval: 4000
        onTriggered: navCoverFade.restart()
    }
    SequentialAnimation {
        id: navCoverFade
        NumberAnimation { target: navCover; property: "opacity"; to: 0; duration: 160; easing.type: Easing.InOutQuad }
        ScriptAction {
            script: {
                navCoverTimeout.stop()
                page.navCovering = false
                page.navCoverItem = null
                navCover.opacity = 1
            }
        }
    }

    allowedOrientations: Orientation.All
    backNavigation: false

    // Back closes what is open over the page first, topmost first; true if
    // something was.
    function closeOverlay(): bool {
        if (linkMenu && linkMenu.visible) {
            linkMenu.visible = false
            return true
        }
        if (pageMenu && pageMenu.open) {
            pageMenu.hide()
            return true
        }
        if (tabsMenu && tabsMenu.open) {
            tabsMenu.hide()
            return true
        }
        if (finding) {
            if (findBar.view)
                findBar.view.stopFind()
            findBar.closed()
            return true
        }
        if (addressSheet.shown) {
            addressSheet.leave()
            return true
        }
        if (tab && tab.pendingLogin !== null) {
            tab.pendingLogin = null
            return true
        }
        return false
    }

    function push(name: var, props: var): void {
        pageStack.push(Qt.resolvedUrl(name), props || { browser: browser })
    }

    // The address sheet rises over the page (AddressSheet), the toolbar
    // turning into its field as the keyboard comes up. The pages keep the
    // height they had meanwhile: the keyboard shrinks the window's content,
    // and the page behind the glass laid itself out again at the smaller
    // height and back.
    function openAddress(): void {
        _frozenWebHeight = webArea.height
        _freezeWeb = true
        addressSheet.open(tab && !tab.newTabPage && !tab.readerMode ? String(tab.webView.url) : "")
    }
    property bool _freezeWeb: false
    property real _frozenWebHeight: 0
    readonly property bool _webCanThaw: !addressSheet.shown && !Qt.inputMethod.visible
    on_WebCanThawChanged: if (_webCanThaw) _freezeWeb = false
    Connections {
        target: page.browser
        function onAddressRequested() { page.openAddress() }
    }

    // The tab overview: the page shrinks away into it (the lift, as the
    // upward swipe on the toolbar does it), and the overview comes in at
    // once, its cards settling, instead of the page stack's sideways slide;
    // back from it, the page grows from the overview's size again.
    function showTabs(): void {
        swipeAnim.stop()
        liftAnim.stop()
        _prepareTabs()
        liftAnim.to = 1
        liftAnim.restart()
    }
    // The overview is built while the page shrinks, off the frame it
    // appears in (made then, its cards and pictures held that frame back
    // by 80 ms on the Jolla Phone).
    Component {
        id: tabsPageComponent
        TabsPage {}
    }
    property var _tabsIncubator: null
    function _prepareTabs(): void {
        if (!_tabsIncubator)
            _tabsIncubator = tabsPageComponent.incubateObject(null, { browser: browser, ownedByCaller: true })
    }
    function openTabs(): void {
        if (tab && !tab.isPrivate)
            tab.saveThumbnail()
        var inc = _tabsIncubator
        _tabsIncubator = null
        if (inc && inc.status === Component.Ready) {
            pageStack.push(inc.object, {}, PageStackAction.Immediate)
        } else {
            if (inc && inc.status === Component.Loading)
                inc.forceCompletion()
            pageStack.push(inc && inc.object ? inc.object : tabsPageComponent, { browser: browser }, PageStackAction.Immediate)
        }
    }
    Connections {
        target: page.browser
        function onTabsReturned() {
            page.lift = 1
            liftAnim.to = 0
            liftAnim.restart()
        }
    }

    function swipe(step: var): void {
        var next = browser.tabs.neighbour(browser.currentId, step)
        if (next !== 0)
            browser.switchTo(next)
    }

    // Is the page worth a reader view? Asked once per finished load.
    function checkReadable(): var {
        readable = false
        if (!tab || tab.newTabPage || String(tab.webView.url).indexOf("http") !== 0)
            return
        var t = tab
        t.webView.runJavaScriptInWorld("(function () { var a = document.querySelector('article, main, [role=main]'); var ps = document.querySelectorAll('p'); var n = 0; for (var i = 0; i < ps.length && i < 200; i++) n += (ps[i].innerText || '').length; return (a ? 1000 : 0) + n })()",
                                        "pacific", function(n) {
            if (t === page.tab)
                page.readable = Number(n) > 1500
        })
    }

    Connections {
        target: page.tab ? page.tab.webView : null
        ignoreUnknownSignals: true
        function onLoadingChanged(request) {
            // A new page in this tab: the toolbar comes back, as in any
            // phone browser.
            if (request.status === LoadRequest.Started)
                page.toolbarShown = true
            if (request.status === LoadRequest.Succeeded)
                page.checkReadable()
        }
    }
    onTabChanged: {
        toolbarShown = true
        finding = false
        checkReadable()
        if (navCovering)
            navCoverFade.complete()
    }

    // ---- The pages -------------------------------------------------------

    // Behind the shrinking page: the overview's backdrop.
    Rectangle {
        anchors.fill: parent
        visible: page.lift > 0
        color: Theme.overlayBackgroundColor
        opacity: Math.min(1, page.lift * 2)
    }

    // The neighbouring tab while swiping: its last picture.
    Item {
        id: peek
        objectName: "tabPeek"
        anchors.fill: webArea
        visible: page.swipeX !== 0 && page.peekId !== 0
        transform: Translate { x: page.swipeX + (page.swipeX < 0 ? peek.width : -peek.width) }
        Rectangle {
            anchors.fill: parent
            color: Theme.overlayBackgroundColor
        }
        Image {
            anchors.fill: parent
            source: page.peekTab && page.peekTab.thumbnail ? page.peekTab.thumbnail : ""
            fillMode: Image.PreserveAspectCrop
            verticalAlignment: Image.AlignTop
            asynchronous: true
        }
        // No picture yet: the tab's site and title, at the edge that
        // comes into view first.
        Column {
            visible: !page.peekTab || !page.peekTab.thumbnail
            anchors.verticalCenter: parent.verticalCenter
            x: page.swipeX < 0 ? Theme.horizontalPageMargin : parent.width - width - Theme.horizontalPageMargin
            width: parent.width / 2
            spacing: Theme.paddingMedium
            LetterIcon {
                text: page.peekTab ? Logic.initial(page.peekTab.title, page.peekTab.url) : ""
                url: page.peekTab ? page.peekTab.url || "" : ""
                iconSource: page.peekTab ? page.peekTab.icon || "" : ""
            }
            Label {
                width: parent.width
                horizontalAlignment: Text.AlignLeft
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
                text: page.peekTab ? (page.peekTab.title || page.peekTab.url || qsTr("New tab")) : ""
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeLarge
            }
        }
    }

    // Swiping back: the page before, under this one.
    Item {
        objectName: "navUnder"
        anchors.fill: webArea
        visible: page.navDir > 0
        clip: true
        HistoryPicture {
            width: parent.width
            height: parent.height
            x: -parent.width / 3 * (1 - page.navProgress)
            view: page.tab ? page.tab.webView : null
            item: page.navDir > 0 ? page.navItem : null
        }
        // Shaded where the page still covers it.
        Rectangle {
            anchors.fill: parent
            color: Theme.overlayBackgroundColor
            opacity: 0.35 * (1 - page.navProgress)
        }
    }

    // The display's notch (Keel's Screen.topCutout). In portrait every page
    // stays below it, as in Safari, which reports a top safe area of 0 there
    // even to viewport-fit=cover pages. Giving those pages the notch as
    // env(safe-area-inset-top) put YouTube's header under it: sites written
    // for Safari do not pad for it. (Landscape puts the notch at the side.)
    readonly property real notch: Silica.Screen.topCutout.height

    // ---- Pull to refresh -------------------------------------------------
    // Dragging down a page that is at its top stretches it down as iOS's
    // rubber band does, (1 - 1/(x 0.55/d + 1)) d; past pullArmAt a haptic
    // tick says letting go reloads (dragging back up, or a flick up as the
    // finger lifts, does not). Which pulls count is the web view's (Chrome's
    // rules: the page was at its top when the finger landed, and it neither
    // opts out with overscroll-behavior nor takes the drag).
    property real pullShown: 0
    property bool _pullArmed: false
    readonly property real pullArmAt: Theme.itemSizeLarge
    property var _pullFeedback: null

    function _pullMoved(distance: var): void {
        pullBack.stop()
        var d = Math.max(1, page.height)
        pullShown = (1 - 1 / (distance * 0.55 / d + 1)) * d
        var armed = pullShown >= pullArmAt
        if (armed && !_pullArmed && _pullFeedback)
            _pullFeedback.play()
        _pullArmed = armed
    }
    function _pullEnded(distance: var, velocity: var): void {
        var reload = _pullArmed && velocity > -0.5
        _pullArmed = false
        if (reload && page.tab && page.tab.webView) {
            page.tab.webView.reload()
            page.toolbarShown = true
        }
        pullBack.start()
    }
    NumberAnimation {
        id: pullBack
        target: page
        property: "pullShown"
        to: 0
        duration: 280
        easing.type: Easing.OutCubic
    }
    Component.onCompleted: {
        try {
            _pullFeedback = SilicaPrivate.Util._keelOptionalObject("ngf-pulldown_lock", "import Nemo.Ngf 1.0",
                "NonGraphicalFeedback { event: 'pulldown_lock' }", page)
        } catch (e) {
            _pullFeedback = null
        }
    }

    // The reload sign in the gap the pull opens above the page.
    Icon {
        z: 1
        visible: page.pullShown > 0
        anchors.horizontalCenter: parent.horizontalCenter
        y: page.notch + page.pullShown / 2 - height / 2
        source: "image://theme/icon-m-refresh"
        color: page._pullArmed ? Theme.highlightColor : Theme.primaryColor
        opacity: Math.min(1, page.pullShown / page.pullArmAt)
        rotation: Math.min(1, page.pullShown / page.pullArmAt) * 270
    }

    // A tap in the band under the notch takes the page to its top and
    // brings the toolbar back, as a tap on iOS's status bar does.
    MouseArea {
        z: 1
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: page.notch
        enabled: height > 0 && !page.browser.fullscreen && !page.isLandscape && !!page.tab
        onClicked: {
            page.tab.scrollToTop()
            page.toolbarShown = true
        }
    }

    Item {
        id: webArea
        anchors {
            top: parent.top
            topMargin: page.browser.fullscreen || page.isLandscape ? 0 : page.notch
            left: parent.left
            right: parent.right
            bottom: page._freezeWeb ? undefined : parent.bottom
            bottomMargin: page.browser.fullscreen ? 0 : page.reservedBottom
        }
        height: page._frozenWebHeight
        transform: [
            Scale {
                origin.x: webArea.width / 2
                origin.y: webArea.height * 0.4
                xScale: 1 - 0.45 * page.lift
                yScale: 1 - 0.45 * page.lift
            },
            Translate { x: page.swipeX + page.navPageX; y: page.pullShown }
        ]

        Repeater {
            model: page.browser ? page.browser.normalTabs : null
            delegate: WebTab {
                browser: page.browser
                tabModel: page.browser.normalTabs
                pageStack: page.pageStack
                directAllowed: page.directAllowed
                obscuredBottom: page.obscuredBottom
                onScrolled: function(dy) { page.scrolled(dy) }
                // A page that stops its own scrolling (a modal, a cookie
                // wall) gives no scrolls: a pull still brings the toolbar
                // back, or with it hidden there would be no way to leave.
                onPulledDown: page.toolbarShown = true
                onPullMoved: function(distance) { page._pullMoved(distance) }
                onPullEnded: function(distance, velocity) { page._pullEnded(distance, velocity) }
                onNavMoved: function(dx) { page.navMoved(dx) }
                onNavEnded: function(dx, velocity) { page.navEnded(dx, velocity) }
                navCovering: page.navCovering
                swipeFrame: page
                onReaderFailed: function(message) { Notices.show(message) }
            }
        }
        Repeater {
            model: page.browser ? page.browser.privateTabs : null
            delegate: WebTab {
                browser: page.browser
                tabModel: page.browser.privateTabs
                pageStack: page.pageStack
                directAllowed: page.directAllowed
                obscuredBottom: page.obscuredBottom
                onScrolled: function(dy) { page.scrolled(dy) }
                // A page that stops its own scrolling (a modal, a cookie
                // wall) gives no scrolls: a pull still brings the toolbar
                // back, or with it hidden there would be no way to leave.
                onPulledDown: page.toolbarShown = true
                onPullMoved: function(distance) { page._pullMoved(distance) }
                onPullEnded: function(distance, velocity) { page._pullEnded(distance, velocity) }
                onNavMoved: function(dx) { page.navMoved(dx) }
                onNavEnded: function(dx, velocity) { page.navEnded(dx, velocity) }
                navCovering: page.navCovering
                swipeFrame: page
                onReaderFailed: function(message) { Notices.show(message) }
            }
        }

        Rectangle {
            anchors.fill: parent
            visible: page.showNewTab
            color: Theme.rgba(Theme.overlayBackgroundColor, 1.0)
            clip: true // its long content never runs under the toolbar
            NewTabView {
                anchors.fill: parent
                browser: page.browser
                onSearchClicked: page.openAddress()
                onOpenUrl: function(url) { page.browser.open(url, { transition: "bookmark" }) }
                onPushPage: function(name) { page.push(name) }
            }
        }

        InfoPanel {
            objectName: "httpsInterstitial"
            anchors.fill: parent
            visible: page.tab !== null && page.tab.interstitial !== null
            iconSource: "image://theme/icon-m-warning"
            title: qsTr("This site has no secure connection")
            text: page.tab && page.tab.interstitial
                  ? qsTr("%1 doesn't support secure connections. Anyone on the network could see or change what you send and receive.").arg(page.tab.interstitial.host)
                  : ""
            primaryText: qsTr("Go back")
            secondaryText: qsTr("Continue to the site")
            onPrimaryClicked: {
                var t = page.tab
                t.interstitial = null
                if (t.webView.canGoBack)
                    t.webView.goBack()
                else
                    page.browser.close(t.tabId, t.isPrivate)
            }
            onSecondaryClicked: {
                var t = page.tab
                var s = t.interstitial
                t.interstitial = null
                Pacific.httpsAllow(s.host, t.isPrivate)
                t.webView.load(s.http_url)
            }
        }

        InfoPanel {
            objectName: "certificateError"
            anchors.fill: parent
            visible: page.tab !== null && page.tab.certificateProblem !== null
            iconSource: "image://theme/icon-m-warning"
            title: qsTr("This connection isn't private")
            text: page.tab && page.tab.certificateProblem
                  ? qsTr("%1's certificate isn't valid. Someone may be pretending to be this site to steal what you send.").arg(page.tab.certificateProblem.host)
                  : ""
            primaryText: qsTr("Go back")
            secondaryText: qsTr("Continue anyway")
            onPrimaryClicked: {
                var t = page.tab
                t.certificateProblem = null
                if (t.webView.canGoBack)
                    t.webView.goBack()
            }
            onSecondaryClicked: {
                var t = page.tab
                var p = t.certificateProblem
                t.certificateProblem = null
                t.webView.profile.allowCertificate(p.host, p.pem)
                t.webView.reload()
            }
        }

        InfoPanel {
            objectName: "loadError"
            anchors.fill: parent
            visible: page.tab !== null && page.tab.loadError !== null && page.tab.interstitial === null
            iconSource: "image://theme/icon-m-website"
            title: qsTr("This page didn't load")
            // The engine's own error is for developers; say what to do.
            text: qsTr("Check your connection and the address, then try again.")
            primaryText: qsTr("Try again")
            onPrimaryClicked: {
                var t = page.tab
                t.loadError = null
                t.webView.reload()
            }
        }

        InfoPanel {
            objectName: "crashed"
            anchors.fill: parent
            visible: page.tab !== null && page.tab.crashed
            iconSource: "image://theme/icon-m-website"
            title: qsTr("This page stopped working")
            text: qsTr("Reloading usually brings it back.")
            primaryText: qsTr("Reload")
            onPrimaryClicked: {
                var t = page.tab
                t.crashed = false
                t.webView.reload()
            }
        }
    }

    // Swiping back: the page's shadow on the one under it.
    Rectangle {
        visible: page.navDir > 0 && page.navDx > 0
        x: webArea.x + page.navPageX - width
        y: webArea.y
        width: Theme.paddingLarge
        height: webArea.height
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 1; color: Theme.rgba(Theme.overlayBackgroundColor, 0.3) }
        }
    }
    // Swiping forward: this page darkens as the next comes over it, with
    // its shadow.
    Rectangle {
        anchors.fill: webArea
        visible: page.navDir < 0
        color: Theme.overlayBackgroundColor
        opacity: 0.35 * page.navProgress
    }
    Item {
        objectName: "navOver"
        anchors.fill: webArea
        visible: page.navDir < 0
        HistoryPicture {
            width: parent.width
            height: parent.height
            x: parent.width + page.navDx
            view: page.tab ? page.tab.webView : null
            item: page.navDir < 0 ? page.navItem : null
            Rectangle {
                anchors.right: parent.left
                width: Theme.paddingLarge
                height: parent.height
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: Theme.rgba(Theme.overlayBackgroundColor, 0.3) }
                }
            }
        }
    }
    // Gone back or forward: the page it led to until it has drawn.
    HistoryPicture {
        id: navCover
        objectName: "navCover"
        anchors.fill: webArea
        visible: page.navCovering
        view: page.tab ? page.tab.webView : null
        item: page.navCoverItem
    }

    // ---- A site's questions: Dialogs, as in the Sailfish Browser ---------

    // A permission request or a login to save, asked once this page is in
    // front and the page stack is still.
    property bool _asking: false
    property var _askedFor: null
    // Back on this page with the question unanswered (the dialog was left
    // some other way): that is a no.
    onStatusChanged: {
        // Another page over this one: the address sheet is not left open
        // under it.
        if (status !== PageStatus.Active)
            addressSheet.leave()
        if (status !== PageStatus.Active || !_asking)
            return
        _asking = false
        var t = tab
        if (t && _askedFor !== null && t.pendingPermission === _askedFor) {
            t.pendingPermission = null
            _askedFor.deny()
        } else if (t && _askedFor !== null && t.pendingSave === _askedFor) {
            t.pendingSave = null
        }
        _askedFor = null
    }
    Timer {
        interval: 250
        repeat: true
        running: !page._asking && page.status === PageStatus.Active && page.tab !== null
                 && (page.tab.pendingPermission !== null || page.tab.pendingSave !== null)
        onTriggered: page.askSite()
    }
    function askSite(): var {
        var t = tab
        if (!t || pageStack.busy)
            return
        var d
        if (t.pendingPermission !== null) {
            var r = t.pendingPermission
            var site = Logic.host(r.origin)
            var key = Logic.permissionSetting(r.kind)
            d = pageStack.push(Qt.resolvedUrl("SitePromptDialog.qml"), {
                site: site, question: Logic.permissionQuestion(r.kind, site),
                iconSource: Logic.permissionIcon(r.kind), rememberVisible: key !== ""
            })
            _asking = true
            _askedFor = r
            var answer = function(allow) {
                _askedFor = null
                if (t.pendingPermission !== r)
                    return
                t.pendingPermission = null
                if (allow)
                    r.allow()
                else
                    r.deny()
                if (d.remember && key !== "")
                    Pacific.setSiteSetting(String(r.origin), key, allow ? "allow" : "deny", t.isPrivate)
            }
            d.accepted.connect(function() { answer(true) })
            d.rejected.connect(function() { answer(false) })
        } else if (t.pendingSave !== null) {
            var l = t.pendingSave
            d = pageStack.push(Qt.resolvedUrl("SitePromptDialog.qml"), {
                site: Logic.host(l.url), iconSource: "image://theme/icon-m-keys",
                question: l.username !== "" ? qsTr("Save the login %1 in Shoal Keys?").arg(l.username)
                                            : qsTr("Save this login in Shoal Keys?"),
                detail: Logic.host(l.url), acceptText: qsTr("Save"), cancelText: qsTr("Not now")
            })
            _asking = true
            _askedFor = l
            d.accepted.connect(function() { _askedFor = null; t.pendingSave = null; Pacific.keysSave(l.url, l.username, l.password) })
            d.rejected.connect(function() { _askedFor = null; t.pendingSave = null })
        }
    }

    // ---- Notes above the toolbar (they do not block the page) -------------

    Column {
        id: prompts
        anchors { left: parent.left; right: parent.right; bottom: toolbar.visible ? toolbar.top : parent.bottom }

        PromptBar {
            objectName: "loginBar"
            width: parent.width
            visible: page.tab !== null && page.tab.pendingLogin !== null
            readonly property var login: page.tab ? page.tab.pendingLogin : null
            text: !login ? "" : login.locked ? qsTr("Sign in with a login from Shoal Keys?")
                  : login.logins.length === 1 ? qsTr("Sign in as %1?").arg(login.logins[0].username || login.logins[0].title)
                  : qsTr("Sign in with one of %1 logins from Shoal Keys?").arg(login.logins.length)
            acceptText: qsTr("Fill")
            rejectText: qsTr("Not now")
            onAccepted: {
                var l = login
                page.tab.pendingLogin = null
                page.tab.fillLogin(l.logins.length === 1 ? l.logins[0].id : "")
            }
            onRejected: page.tab.pendingLogin = null
        }

        PromptBar {
            objectName: "pilotBar"
            width: parent.width
            readonly property var agent: JSON.parse(Pacific.agent)
            visible: agent.active === true
            text: qsTr("Pilot is browsing %1").arg(agent.visited && agent.visited.length > 0
                                                   ? Logic.host(agent.visited[agent.visited.length - 1]) : qsTr("the web"))
            acceptText: qsTr("Show")
            rejectText: qsTr("Stop")
            onAccepted: page.browser.takeOverAgent()
            onRejected: page.browser.stopAgent()
        }

        FindBar {
            id: findBar
            width: parent.width
            visible: page.finding
            view: page.tab ? page.tab.webView : null
            onClosed: page.finding = false
        }
    }

    // ---- The toolbar -----------------------------------------------------

    AddressBar {
        id: toolbar
        objectName: "toolbar"
        anchors { left: parent.left; right: parent.right }
        y: page.barUp || page._barHold ? page.height - height : page.height
        visible: !page.browser.fullscreen && !page.finding && (!Qt.inputMethod.visible || addressSheet.shown)
        // Turning into the address sheet's field.
        opacity: 1 - addressSheet.progress
        Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.InOutQuad } }
        browser: page.browser
        // Frosted over the pages while any of the bar is on screen.
        backdrop: webArea
        backdropY: y - webArea.y
        frosted: y < page.height
        tabCount: page.browser ? page.browser.tabs.count : 0
        blockedCount: page.blocked
        protectionIncomplete: page.browser.protectionIncomplete
        readable: page.readable
        onAddressClicked: page.openAddress()
        onTabsClicked: page.showTabs()
        onTabsHeld: if (page.tabsMenu) page.tabsMenu.open = true
        onMenuClicked: if (page.pageMenu) page.pageMenu.open = !page.pageMenu.open
        onShieldClicked: page.push("ProtectionPage.qml", { browser: page.browser, tab: page.tab })
        onReaderClicked: if (page.tab) page.tab.toggleReader()
        onDragStarted: page.gestureStarted()
        onDragMoved: function(dx, dy) { page.gestureMoved(dx, dy) }
        onDragEnded: function(dx, dy, vx, vy) { page.gestureEnded(dx, dy, vx, vy) }
    }

    AddressSheet {
        id: addressSheet
        anchors.fill: parent
        browser: page.browser
        backdrop: webArea
    }

    function scrolled(dy: var): void {
        if (obscuredTimer.running)
            obscuredTimer.restart()
        // At the top of the page the toolbar is always there, and it comes
        // back at the end, as Safari's does: there is nothing further to
        // read and the next thing is likely the bar.
        if (tab && tab.lastScrollY <= Theme.paddingLarge)
            toolbarShown = true
        else if (tab && dy > 0 && tab.lastContentHeight > 0
                 && tab.lastScrollY + tab.lastViewportHeight >= tab.lastContentHeight - Theme.paddingLarge)
            toolbarShown = true
        else if (dy > Theme.paddingLarge)
            toolbarShown = false
        else if (dy < -Theme.paddingLarge)
            toolbarShown = true
    }

    // Built after the first frame, off the start-up path.
    property bool _deferred: false
    Timer {
        interval: 50
        running: true
        onTriggered: page._deferred = true
    }

    Loader {
        id: pageMenuLoader
        // Docked to the page itself (a sized Loader would stretch the
        // panel to its own size).
        onLoaded: item.parent = page
        active: page._deferred
        asynchronous: true
        sourceComponent: PageMenu {
            objectName: "pageMenu"
            maxHeight: page.height - Theme.paddingLarge
            browser: page.browser
            onFindRequested: {
                page.finding = true
                findBar.start()
            }
            onPushPage: function(name, props) { page.push(name, props) }
        }
    }
    readonly property var pageMenu: pageMenuLoader.item

    Loader {
        id: tabsMenuLoader
        onLoaded: item.parent = page
        active: page._deferred
        asynchronous: true
        sourceComponent: TabsMenu {
            objectName: "tabsMenu"
            browser: page.browser
            remorseParent: page
        }
    }
    readonly property var tabsMenu: tabsMenuLoader.item

    Loader {
        id: linkMenuLoader
        anchors.fill: parent
        active: page._deferred
        asynchronous: true
        sourceComponent: LinkMenu {
            objectName: "linkMenu"
            visible: false
            browser: page.browser
            onDone: visible = false
        }
    }
    readonly property var linkMenu: linkMenuLoader.item

    Connections {
        target: page.browser
        function onLinkMenuRequested(tab, info) {
            var menu = page.linkMenu
            if (!menu)
                return
            // Find in page selects each match: that is not the person
            // selecting text, and the menu covered the matches and the bar.
            if (page.finding && !info.linkUrl && !info.imageUrl && !info.misspelled)
                return
            menu.tab = tab
            menu.info = info
            menu.visible = !!(info.linkUrl || info.imageUrl || info.selectionText || info.misspelled)
        }
    }
}
