import MarathonUI.Theme
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
        if (page === -2) {
            pageView.currentIndex = 0;
        } else if (page === -1) {
            pageView.currentIndex = 1;
        } else if (page >= 0) {
            pageViewContainer.internalAppGridPage = page;
            pageView.currentIndex = 2;
            Qt.callLater(function () {
                var loader = pageView.itemAtIndex(2);
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
            Logger.info("PageView", "Forcing view to App Grid (Index 2)");
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
        highlightMoveDuration: 250
        preferredHighlightBegin: 0
        preferredHighlightEnd: width
        cacheBuffer: width * 3
        pixelAligned: true
        reuseItems: true
        synchronousDrag: false
        model: sharedAppModel.count > 0 ? 2 + pageCount : 4
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
                    pageView.currentIndex = 2;
                }
            }
        }

        Component {
            id: framesComponent

            MarathonTaskSwitcher {
                opacity: 1
                compositor: pageViewContainer.compositor
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
