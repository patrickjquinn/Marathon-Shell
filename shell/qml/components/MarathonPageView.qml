import QtQuick
import MarathonOS.Shell

Item {
    id: pageViewContainer
    
    property alias currentIndex: pageView.currentIndex
    property alias currentPage: pageView.currentPage
    property alias isGestureActive: pageView.isGestureActive
    property alias count: pageView.count
    
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
    
    model: AppStore.apps.length > 0 ? 2 + Math.ceil(AppStore.apps.length / 16) : 4
    
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
    }
}

MarathonSearch {
    id: searchOverlay
    anchors.fill: parent
    z: 1000
    
    onResultSelected: (result) => {
        Logger.info("PageView", "Search result selected: " + result.title)
    }
}

MouseArea {
    id: pullDownGestureArea
    anchors.fill: parent
    anchors.topMargin: -100
    anchors.bottomMargin: Constants.bottomBarHeight
    z: searchOverlay.active ? -1 : 5
    enabled: pageView.currentIndex >= 2 && !searchOverlay.active
    propagateComposedEvents: !searchOverlay.active
    
    property real startY: 0
    property real pullDistance: 0
    property bool isPulling: false
    
    onPressed: (mouse) => {
        if (mouse.y < Constants.safeAreaTop + 50) {
            startY = mouse.y
            isPulling = true
        } else {
            mouse.accepted = false
        }
    }
    
    onPositionChanged: (mouse) => {
        if (isPulling) {
            pullDistance = mouse.y - startY
            if (pullDistance < 0) {
                pullDistance = 0
            }
        } else {
            mouse.accepted = false
        }
    }
    
    onReleased: (mouse) => {
        if (isPulling && pullDistance > 80) {
            Logger.info("PageView", "Pull-down search triggered")
            searchOverlay.open()
        }
        isPulling = false
        pullDistance = 0
    }
    
    onCanceled: {
        isPulling = false
        pullDistance = 0
    }
}

Keys.onPressed: (event) => {
    if (pageView.currentIndex >= 2 && !searchOverlay.active) {
        if (event.text.length > 0 && event.text.match(/[a-zA-Z0-9 ]/)) {
            Logger.info("PageView", "Keyboard search triggered")
            searchOverlay.open()
            event.accepted = false
        }
    }
}

Component.onCompleted: {
    pageViewContainer.forceActiveFocus()
}
}

