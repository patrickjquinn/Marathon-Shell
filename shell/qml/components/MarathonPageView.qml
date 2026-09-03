import MarathonOS.Shell
import QtQuick

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

    signal hubVisible(bool visible)
    signal framesVisible(bool visible)
    signal appLaunched(var app)

    function incrementCurrentIndex() {
        pageView.incrementCurrentIndex();
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
                let loader = pageView.itemAtIndex(page + 2) as Loader;
                if (loader && loader.item && typeof loader.item.navigateToPage === 'function')
                    loader.item.navigateToPage(page);
            });
        }
    }

    // Head-shake feedback for discrete-swipe events that hit a boundary.
    // Plasma Mobile gesture revamp (Akademy 2024): a failed gesture must
    // teach, never no-op. direction: -1 nudges right (nothing further left),
    // +1 nudges left.
    function nudgeAtBoundary(direction) {
        nudgeAnimation.stop();
        nudgeAnimation.fromX = pageView.contentX;
        nudgeAnimation.peakX = pageView.contentX + direction * 24;
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
            easing.type: Easing.OutBack
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
        // Items per page = MarathonAppGrid.columns × rows. Hardcoding 16
        // (= 4×4) worked accidentally on phone canvas at scale 1.25 but
        // broke on the HyperPixel 720×720 where the grid is 4×4 at scale
        // 1.25 but 5×5 at scale 1.0. With the wrong divisor pageCount
        // returned 1 for a 13-app set that needs 2 pages and swipe to
        // page 2 silently did nothing. Replicate MarathonAppGrid's
        // columns × rows math here (Constants + SettingsManagerCpp are
        // singletons; same inputs → same answer).
        property real _userScale: SettingsManagerCpp.userScaleFactor
        property int _baseCols: Constants.screenWidth < 700 ? 4 : Constants.screenWidth < 900 ? 5 : 6
        property int _baseRows: Constants.screenWidth < 700 ? 4 : 5
        property real _scaleDivisor: Math.max(1.0, _userScale)
        property int _gridCols: SettingsManagerCpp.appGridColumns > 0 ? SettingsManagerCpp.appGridColumns : Math.max(3, Math.floor(_baseCols / _scaleDivisor))
        property int _gridRows: Math.max(4, Math.floor(_baseRows / _scaleDivisor))
        property int _itemsPerPage: _gridCols * _gridRows
        property int pageCount: Math.max(1, Math.ceil(sharedAppModel.count / _itemsPerPage))

        anchors.fill: parent
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        interactive: true
        // pressDelay 200 ate fast horizontal flicks before the Flickable
        // could steal — the user reported swipe Drawer→Hub silently failed.
        // Per-icon MouseAreas already reject tap-on-release when drag > 15 px,
        // so children don't need the delay to suppress accidental taps.
        pressDelay: 0
        flickDeceleration: 3000
        maximumFlickVelocity: 10000
        flickableDirection: Flickable.HorizontalFlick
        currentIndex: 2
        // Rubber-band at the first/last page instead of a hard stop.
        boundsBehavior: Flickable.DragAndOvershootBounds
        // 250 ms felt sluggish on small screens; 180 ms matches the
        // OutCubic snap pattern the rest of the shell uses.
        highlightMoveDuration: 180
        preferredHighlightBegin: 0
        preferredHighlightEnd: width
        cacheBuffer: width * 3
        pixelAligned: true
        reuseItems: true
        synchronousDrag: false
        // 1 Hub + 1 Frames + N app-grid pages. Show at least the home
        // page (index 2) even before the app model has loaded.
        model: sharedAppModel.count > 0 ? 2 + pageCount : 3
        onCurrentIndexChanged: {
            Logger.debug("PageView", "Page changed to index: " + currentIndex + ", page: " + currentPage);
            pageViewContainer.hubVisible(currentIndex === 0);
            pageViewContainer.framesVisible(currentIndex === 1);
            if (currentIndex < 2)
                pageViewContainer.searchPullProgress = 0;
            else
                pageViewContainer.internalAppGridPage = currentIndex - 2;
        }

        Component {
            id: hubComponent

            MarathonHub {
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
            }
        }

        // Page index map:
        //   index 0      → Hub
        //   index 1      → MarathonTaskSwitcher (Active Frames)
        //   index >= 2   → AppGrid page (pageIndex = index - 2)
        //
        // i.e. page 2 is the FIRST app-grid page (the home).
        delegate: Loader {
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
                target: item
                property: "pageIndex"
                value: pageNumber
                when: index >= 2
            }
        }
    }
}
