import QtQuick
import MarathonOS.Shell
import MarathonUI.Theme

Item {
    id: pageViewContainer

    property alias currentIndex: pageView.currentIndex
    property alias currentPage: pageView.currentPage
    property alias isGestureActive: pageView.isGestureActive
    property alias count: pageView.count
    property real searchPullProgress: 0.0  // Exposed to Shell for search overlay
    property int internalAppGridPage: 0  // Track the internal page within app grid
    property var compositor: null  // Wayland compositor reference for native apps

    property bool initialPageSet: false

    // Timer to force index after model updates settle
    Timer {
        id: forceIndexTimer
        interval: 100  // Give ListView time to process model change
        repeat: false
        onTriggered: {
            Logger.info("PageView", "Forcing view to App Grid (Index 2)");
            pageView.currentIndex = 2;
            pageView.positionViewAtIndex(2, ListView.Center);
        }
    }

    // Shared model for all grid pages
    FilteredAppModel {
        id: sharedAppModel
        onCountChanged: {
            if (!pageViewContainer.initialPageSet && count > 0) {
                // Force to App Grid (index 2) when data first loads
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
        // page: -2 = Hub, -1 = Task Switcher, 0+ = App Grid pages
        if (page === -2) {
            pageView.currentIndex = 0;
        } else if (page === -1) {
            pageView.currentIndex = 1;
        } else if (page >= 0) {
            // Store the target app grid page
            pageViewContainer.internalAppGridPage = page;

            // Navigate to app grid (index 2)
            pageView.currentIndex = 2;

            // Use a timer to navigate to the specific page after the grid loads
            Qt.callLater(function () {
                var loader = pageView.itemAtIndex(2);
                if (loader && loader.item && typeof loader.item.navigateToPage === 'function') {
                    loader.item.navigateToPage(page);
                }
            });
        }
    }

    ListView {
        id: pageView
        anchors.fill: parent
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        interactive: true
        pressDelay: 100  // Delay press to allow flick detection (fixes sticky icons)

        // PHYSICS TUNING for smooth, snappy flick (EASIER swiping)
        flickDeceleration: 5000  // Lower deceleration = smoother coasting
        maximumFlickVelocity: 10000  // Higher velocity = more responsive to lighter flicks
        flickableDirection: Flickable.HorizontalFlick

        currentIndex: 2
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 250  // Smooth programmatic transitions
        preferredHighlightBegin: 0
        preferredHighlightEnd: width
        cacheBuffer: width * 3

        // PERFORMANCE OPTIMIZATIONS for touch fluidity
        pixelAligned: true
        reuseItems: true
        synchronousDrag: false  // Async dragging for better performance

        property int currentPage: currentIndex - 2
        property bool isGestureActive: false
        property int pageCount: Math.ceil(sharedAppModel.count / 16)

        model: sharedAppModel.count > 0 ? 2 + pageCount : 4

        // Connections no longer needed as binding handles updates

        delegate: Loader {
            width: pageView.width
            height: pageView.height

            sourceComponent: {
                if (index === 0)
                    return hubComponent;
                if (index === 1)
                    return framesComponent;
                return appGridComponent;
            }

            property int pageNumber: index - 2

            Binding {
                target: item
                property: "pageIndex"
                value: pageNumber
                when: index >= 2 // Only for app grid pages
            }

            ListView.onReused: {
                if (item && typeof item.searchPullProgress !== 'undefined') {
                    item.searchPullProgress = 0.0;
                    item.searchGestureActive = false;
                }
            }
        }

        Component {
            id: hubComponent

            MarathonHub {
                onClosed: {
                    pageView.currentIndex = 2;
                }
            }
        }

        Component {
            id: framesComponent

            MarathonTaskSwitcher {
                opacity: 1.0
                compositor: pageViewContainer.compositor  // Pass compositor reference

                // Expose search progress from task switcher
                onSearchPullProgressChanged: {
                    pageViewContainer.searchPullProgress = searchPullProgress;
                }

                onClosed: {
                    pageView.currentIndex = 2;
                }
            }
        }

        Component {
            id: appGridComponent

            MarathonAppGrid {
                // Pass shared model
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

                // No need to propagate internal page changes as PageView handles it
            }
        }

        onCurrentIndexChanged: {
            // currentPage is automatically updated via binding on line 37
            Logger.debug("PageView", "Page changed to index: " + currentIndex + ", page: " + currentPage);

            pageViewContainer.hubVisible(currentIndex === 0);
            pageViewContainer.framesVisible(currentIndex === 1);

            // Reset search pull progress when navigating away from app grid pages
            if (currentIndex < 2) {
                pageViewContainer.searchPullProgress = 0.0;
            } else {
                // Update internal page for app grid (index 2+)
                pageViewContainer.internalAppGridPage = currentIndex - 2;
            }
        }
    }

    Component.onCompleted:
    // Don't force focus - let Shell manage keyboard input
    {}
}
