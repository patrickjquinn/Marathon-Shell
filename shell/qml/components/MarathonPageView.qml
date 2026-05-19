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
        // page === -1: jump to Hub (was -2 before frames page was deleted)
        // page >=  0: jump to app-grid page N (now at index = N + 1)
        if (page === -1) {
            pageView.currentIndex = 0;
        } else if (page >= 0) {
            pageViewContainer.internalAppGridPage = page;
            pageView.currentIndex = page + 1;
            Qt.callLater(function () {
                let loader = pageView.itemAtIndex(page + 1) as Loader;
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
            Logger.info("PageView", "Forcing view to home (App Grid page 0 at index 1)");
            pageView.currentIndex = 1;
            pageView.positionViewAtIndex(1, ListView.Center);
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
        // Hub is at index 0 → currentPage -1.
        // App-grid pages start at index 1 → currentPage 0, 1, 2…
        property int currentPage: currentIndex - 1
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
        currentIndex: 1
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 250
        preferredHighlightBegin: 0
        preferredHighlightEnd: width
        cacheBuffer: width * 3
        pixelAligned: true
        reuseItems: true
        synchronousDrag: false
        // 1 fixed page (Hub) + N app-grid pages. Show at least the home
        // page even before the app model has loaded.
        model: sharedAppModel.count > 0 ? 1 + pageCount : 2
        onCurrentIndexChanged: {
            Logger.debug("PageView", "Page changed to index: " + currentIndex + ", page: " + currentPage);
            pageViewContainer.hubVisible(currentIndex === 0);
            if (currentIndex < 1)
                pageViewContainer.searchPullProgress = 0;
            else
                pageViewContainer.internalAppGridPage = currentIndex - 1;
        }

        Component {
            id: hubComponent

            MarathonHub {
                onClosed: {
                    // Return to the home (first app-grid page).
                    pageView.currentIndex = 1;
                }
            }
        }

        // Page 0: Hub (notifications)
        // Page 1+: MarathonAppGrid (the iOS-style icon grid home, paginated)
        //
        // The previous "framesComponent" page was a design-team
        // confusion — Active Frames IS the task switcher, not a
        // home page. The task switcher is reached via a gesture
        // (app-minimise swipe), not by paging horizontally. So the
        // dedicated frames page is gone, and the home is now just
        // page 1 of the app grid per JSX HomePage1.
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
        //   index >= 1   → AppGrid page (pageIndex = index - 1)
        //
        // i.e. page 1 is the FIRST app-grid page (the home).
        delegate: Loader {
            property int pageNumber: index - 1

            width: pageView.width
            height: pageView.height
            sourceComponent: {
                if (index === 0)
                    return hubComponent;

                return appGridComponent;
            }
            Binding {
                target: item
                property: "pageIndex"
                value: pageNumber
                when: index >= 1
            }
        }
    }
}
