pragma ComponentBehavior: Bound

import MarathonOS.Shell
import QtQuick
import Sailfish.Silica 1.0 as Silica
import Marathon.Silica 1.0 as Silica
import "../core/LauncherGrid.js" as LauncherGrid

Item {
    id: pageViewContainer

    property alias currentIndex: pageView.currentIndex
    property alias currentPage: pageView.currentPage
    property alias isGestureActive: pageView.isGestureActive
    property alias count: pageView.count
    property alias pageCount: pageView.pageCount
    property real searchPullProgress: 0
    property int internalAppGridPage: 0
    property var compositor: null
    property bool initialPageSet: false
    property bool hubOverlayOpen: false

    signal hubVisible(bool visible)
    signal framesVisible(bool visible)
    signal appLaunched(var app)
    signal appLongPressed(var app, rect sceneRect)

    // Back over the Hub: true when the Hub closed something of its own.
    function closeHubOverlay() {
        const loader = pageView.itemAtIndex(0) as Loader;
        const hub = loader ? loader.item as MarathonHub : null;
        return hub !== null && hub.closeOverlay();
    }

    function _dismissHubOverlay() {
        const loader = pageView.itemAtIndex(0) as Loader;
        const hub = loader ? loader.item as MarathonHub : null;
        if (hub !== null)
            hub.dismissOverlay();
    }

    // The app grid page on screen builds in.
    function playEntrance() {
        const loader = pageView.itemAtIndex(pageView.currentIndex) as Loader;
        const grid = loader ? loader.item as MarathonAppGrid : null;
        if (grid !== null)
            grid.playEntrance();
    }

    function incrementCurrentIndex() {
        pageView.incrementCurrentIndex();
    }

    // Puts a page on screen at once, without the slide: for a page shown under an app.
    function jumpToIndex(index) {
        var duration = pageView.highlightMoveDuration;
        pageView.highlightMoveDuration = 0;
        pageView.currentIndex = index;
        pageView.positionViewAtIndex(index, ListView.Beginning);
        pageView.highlightMoveDuration = duration;
    }

    function decrementCurrentIndex() {
        pageView.decrementCurrentIndex();
    }

    function navigateToPage(page) {
        // page === -2: Hub (currentIndex 0)
        // page === -1: Active Frames / TaskSwitcher (currentIndex 1)
        // page >=  0: app-grid page N (currentIndex = N + 2)
        if (page === -2) {
            pageView.currentIndex = 0;
        } else if (page === -1) {
            pageView.currentIndex = 1;
        } else if (page >= 0) {
            pageViewContainer.internalAppGridPage = page;
            pageView.currentIndex = page + 2;
            Qt.callLater(function () {
                var loader = pageView.itemAtIndex(page + 2) as Loader;
                if (loader && loader.item)
                    pageViewContainer._navigateGridToPage(loader.item, page);
            });
        }
    }

    function _navigateGridToPage(grid, page) {
        if (typeof grid.navigateToPage === 'function')
            grid.navigateToPage(page);
    }

    // Head-shake feedback for discrete-swipe events that hit a boundary.
    // Plasma Mobile gesture revamp (Akademy 2024): a failed gesture must
    // teach, never no-op. direction: -1 nudges right (nothing further left),
    // +1 nudges left.
    function nudgeAtBoundary(direction) {
        nudgeAnimation.stop();
        nudgeAnimation.fromX = pageView.contentX;
        nudgeAnimation.peakX = pageView.contentX + direction * Silica.Theme.paddingLarge;
        nudgeAnimation.start();
    }

    SequentialAnimation {
        id: nudgeAnimation

        property real fromX: 0
        property real peakX: 0

        NumberAnimation {
            target: pageView
            property: "contentX"
            to: nudgeAnimation.peakX
            duration: 110
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: pageView
            property: "contentX"
            to: nudgeAnimation.fromX
            duration: 200
            easing.type: Easing.OutCubic
        }
    }

    Component.onCompleted: {}

    Timer {
        id: forceIndexTimer

        interval: 100
        repeat: false
        onTriggered: {
            Logger.info("PageView", "Forcing view to home (App Grid page 0 at index 2)");
            pageView.currentIndex = 2;
            pageView.positionViewAtIndex(2, ListView.Center);
        }
    }

    FilteredAppModel {
        id: sharedAppModel

        onCountChanged: {
            if (!pageViewContainer.initialPageSet && count > 0) {
                Logger.info("PageView", "Model loaded with " + count + " apps. Scheduling index force.");
                forceIndexTimer.restart();
                pageViewContainer.initialPageSet = true;
            }
        }
        Component.onCompleted: {
            if (count > 0 && !pageViewContainer.initialPageSet) {
                Logger.info("PageView", "Model already loaded. Scheduling index force.");
                forceIndexTimer.restart();
                pageViewContainer.initialPageSet = true;
            }
        }
    }

    ListView {
        id: pageView

        // currentPage exposes the app-grid page number (0-based).
        // Hub is at index 0 → currentPage -2.
        // Frames (task switcher) at index 1 → currentPage -1.
        // App-grid pages start at index 2 → currentPage 0, 1, 2…
        property int currentPage: currentIndex - 2
        property bool isGestureActive: false
        property int _itemsPerPage: LauncherGrid.columns(Window.width > 0 ? Window.width : Constants.screenWidth, Silica.Theme.pixelRatio, SettingsManagerCpp.appGridColumns) * LauncherGrid.rows(Window.height > 0 ? Window.height : Constants.screenHeight, Silica.Theme.iconSizeLauncher)
        property int pageCount: LauncherGrid.pageCount(sharedAppModel.count, _itemsPerPage)

        anchors.fill: parent
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        // The Hub's weather sheet keeps the pages still under it.
        interactive: !pageViewContainer.hubOverlayOpen
        // pressDelay 200 ate fast horizontal flicks before the Flickable
        // could steal — the user reported swipe Drawer→Hub silently failed.
        // Per-icon MouseAreas already reject tap-on-release when drag > 15 px,
        // so children don't need the delay to suppress accidental taps.
        pressDelay: 0
        flickDeceleration: 12000
        maximumFlickVelocity: MMotion.pagerFlickVelocity
        flickableDirection: Flickable.HorizontalFlick
        currentIndex: 2
        // Rubber-band at the first/last page instead of a hard stop.
        boundsBehavior: Flickable.DragAndOvershootBounds
        highlightMoveDuration: 180
        // A SnapOneItem flick starts at maximumFlickVelocity and decelerates
        // onto the next page, so at release the cap becomes the finger's
        // speed: the snap carries on from it, as Android's ViewPager does.
        // Qt raises a slower one to reach the page at flickDeceleration.
        property var _motion: []
        onContentXChanged: if (dragging) Silica.Velocity.add(_motion, contentX, contentY)
        onDraggingChanged: {
            if (dragging) {
                _motion = [];
                maximumFlickVelocity = MMotion.pagerFlickVelocity;
            } else {
                maximumFlickVelocity = Math.max(400, Math.abs(Silica.Velocity.rate(_motion, 1)));
            }
        }
        preferredHighlightBegin: 0
        preferredHighlightEnd: width
        cacheBuffer: width * 3
        pixelAligned: true
        reuseItems: true
        // Past the drag distance the page keeps the finger's point under it,
        // from the drag's second move (the first starts the drag from rest).
        synchronousDrag: dragging
        // 1 Hub + 1 Frames + N app-grid pages. Show at least the home
        // page (index 2) even before the app model has loaded.
        readonly property int pagesWanted: sharedAppModel.count > 0 ? 2 + pageCount : 3

        function syncPages() {
            while (pageModel.count < pagesWanted)
                pageModel.append({
                    "page": 0
                });
            while (pageModel.count > pagesWanted)
                pageModel.remove(pageModel.count - 1);
            if (currentIndex >= pageModel.count)
                currentIndex = pageModel.count - 1;
        }

        onPagesWantedChanged: syncPages()
        Component.onCompleted: syncPages()
        // Grown and shrunk, never replaced: a new model sends currentIndex back to 0, the Hub.
        model: ListModel {
            id: pageModel

            ListElement {
                page: 0
            }
            ListElement {
                page: 0
            }
            ListElement {
                page: 0
            }
        }
        onCurrentIndexChanged: {
            Logger.debug("PageView", "Page changed to index: " + currentIndex + ", page: " + currentPage);
            pageViewContainer.hubVisible(currentIndex === 0);
            pageViewContainer.framesVisible(currentIndex === 1);
            // The pages stay visible off screen, so the Hub can't see that it was left.
            if (currentIndex !== 0)
                pageViewContainer._dismissHubOverlay();
            if (currentIndex < 2)
                pageViewContainer.searchPullProgress = 0;
            else
                pageViewContainer.internalAppGridPage = currentIndex - 2;
        }

        Component {
            id: hubComponent

            MarathonHub {
                onOverlayOpenChanged: pageViewContainer.hubOverlayOpen = overlayOpen
                onClosed: {
                    // Return to the home (first app-grid page = index 2).
                    pageView.currentIndex = 2;
                }
            }
        }

        // Active Frames task switcher — the alpha-1 implementation
        // restored from the months-of-work polish that the redesign
        // accidentally wiped out. Lives at index 1 alongside Hub and
        // the AppGrid pages — paginated, not gesture-only. Long-swipe-up
        // on an app still routes here through the snap-into-grid path
        // in MarathonShell.qml.
        Component {
            id: framesComponent

            MarathonTaskSwitcher {
                opacity: 1
                // Index 1 is this page; see the page index map below. A drag
                // crosses currentIndex only at the snap threshold, so while the
                // pages move it is active whenever any of it is on screen.
                pageActive: pageView.currentIndex === 1 || (pageView.moving && parent !== null && Math.abs(parent.x - pageView.contentX) < pageView.width)
                compositor: pageViewContainer.compositor
                onSearchPullProgressChanged: {
                    pageViewContainer.searchPullProgress = searchPullProgress;
                }
                onClosed: {
                    // Return to home from the task switcher (no app picked).
                    pageView.currentIndex = 2;
                }
            }
        }

        Component {
            id: appGridComponent

            MarathonAppGrid {
                appModel: sharedAppModel
                // Setup's handover plays the entrance; until then, no icons behind it.
                entranceHeld: !SettingsManagerCpp.firstRunComplete
                // Don't override columns/rows here — AppGrid computes them
                // scale-aware (drops 4×4 → 3×4 at userScaleFactor ≥ 1.25,
                // matching the iOS Home Screen density behaviour).
                onSearchPullProgressChanged: {
                    pageViewContainer.searchPullProgress = searchPullProgress;
                }
                onAppLaunched: app => {
                    Logger.info("PageView", "App launched: " + app.name);
                    pageViewContainer.appLaunched(app);
                }
                onLongPress: (app, sceneRect) => pageViewContainer.appLongPressed(app, sceneRect)
            }
        }

        // Page index map:
        //   index 0      → Hub
        //   index 1      → MarathonTaskSwitcher (Active Frames)
        //   index >= 2   → AppGrid page (pageIndex = index - 2)
        //
        // i.e. page 2 is the FIRST app-grid page (the home).
        delegate: Loader {
            id: pageLoader

            required property int index
            property int pageNumber: index - 2

            width: pageView.width
            height: pageView.height
            sourceComponent: {
                if (index === 0)
                    return hubComponent;
                if (index === 1)
                    return framesComponent;
                return appGridComponent;
            }
            Binding {
                target: pageLoader.item
                property: "pageIndex"
                value: pageLoader.pageNumber
                when: pageLoader.index >= 2
            }
        }
    }

    Silica.FlingStopper {
        view: pageView
    }
}
