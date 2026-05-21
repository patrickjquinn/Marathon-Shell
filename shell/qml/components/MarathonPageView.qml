import MarathonOS.Shell
import QtQuick

Item {
    id: pageViewContainer

    property alias currentIndex: pageView.currentIndex
    property alias currentPage: pageView.currentPage
    property alias isGestureActive: pageView.isGestureActive
    property alias count: pageView.count
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
        property int pageCount: Math.ceil(sharedAppModel.count / 16)

        anchors.fill: parent
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        interactive: true
        pressDelay: 200
        flickDeceleration: 3000
        maximumFlickVelocity: 10000
        flickableDirection: Flickable.HorizontalFlick
        currentIndex: 2
        boundsBehavior: Flickable.StopAtBounds
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
                columns: 4
                rows: 4
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
