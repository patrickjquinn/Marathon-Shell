import QtQuick
import MarathonOS.Shell

ListView {
    id: pageView
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
    
    signal hubVisible(bool visible)
    signal framesVisible(bool visible)
    signal appLaunched(var app)
    
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
    
    property bool isGestureActive: false
    
    Component {
        id: appGridComponent
        
        MarathonAppGrid {
            columns: 4
            rows: 4
            
            onAppLaunched: (app) => {
                Logger.info("PageView", "App launched: " + app.name)
                pageView.appLaunched(app)
            }
        }
    }
    
    onCurrentIndexChanged: {
        currentPage = currentIndex - 2
        Logger.debug("PageView", "Page changed to index: " + currentIndex + ", page: " + currentPage)
        
        hubVisible(currentIndex === 0)
        framesVisible(currentIndex === 1)
    }
}

