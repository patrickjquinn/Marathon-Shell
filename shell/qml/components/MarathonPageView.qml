import QtQuick
import MarathonOS.Shell

Item {
    id: pageViewContainer
    
    property alias currentIndex: pageView.currentIndex
    property alias currentPage: pageView.currentPage
    property alias isGestureActive: pageView.isGestureActive
    property alias count: pageView.count
    property real searchPullProgress: 0.0  // Exposed to Shell for search overlay
    
    signal hubVisible(bool visible)
    signal framesVisible(bool visible)
    signal appLaunched(var app)
    
    function incrementCurrentIndex() { pageView.incrementCurrentIndex() }
    function decrementCurrentIndex() { pageView.decrementCurrentIndex() }

ListView {
    id: pageView
    anchors.fill: parent
    orientation: ListView.Horizontal
    snapMode: ListView.SnapOneItem
    highlightRangeMode: ListView.StrictlyEnforceRange
    interactive: true
    flickDeceleration: 8000
    maximumFlickVelocity: 2000
    currentIndex: 2
    boundsBehavior: Flickable.StopAtBounds
    highlightMoveDuration: 100
    preferredHighlightBegin: 0
    preferredHighlightEnd: width
    cacheBuffer: width * 3
    
    property int currentPage: currentIndex - 2
    property bool isGestureActive: false
    property int pageCount: Math.ceil(AppModel.count / 16)
    
    model: AppModel.count > 0 ? 2 + pageCount : 4
    
    Connections {
        target: AppModel
        function onCountChanged() {
            pageView.pageCount = Math.ceil(AppModel.count / 16)
        }
    }
    
    delegate: Loader {
        width: pageView.width
        height: pageView.height
        
        sourceComponent: {
            if (index === 0) return hubComponent
            if (index === 1) return framesComponent
            return appGridComponent
        }
        
        property int pageNumber: index - 2
    }
    
    Component {
        id: hubComponent
        
        MarathonHub {
            onClosed: {
                pageView.currentIndex = 2
            }
        }
    }
    
    Component {
        id: framesComponent
        
        MarathonTaskSwitcher {
            opacity: (pageView.currentIndex === 1) && !pageView.isGestureActive ? 1.0 : 0.0
            
            Behavior on opacity {
                NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
            }
            
            onClosed: {
                pageView.currentIndex = 2
            }
        }
    }
    
    Component {
        id: appGridComponent
        
        MarathonAppGrid {
            columns: 4
            rows: 4
            
            onSearchPullProgressChanged: {
                pageViewContainer.searchPullProgress = searchPullProgress
            }
            
            onAppLaunched: (app) => {
                Logger.info("PageView", "App launched: " + app.name)
                pageViewContainer.appLaunched(app)
            }
        }
    }
    
    onCurrentIndexChanged: {
        currentPage = currentIndex - 2
        Logger.debug("PageView", "Page changed to index: " + currentIndex + ", page: " + currentPage)
        
        pageViewContainer.hubVisible(currentIndex === 0)
        pageViewContainer.framesVisible(currentIndex === 1)
        
        // Reset search pull progress when navigating away from app grid pages
        if (currentIndex < 2) {
            pageViewContainer.searchPullProgress = 0.0
        }
    }
}

Component.onCompleted: {
    // Don't force focus - let Shell manage keyboard input
}
}

