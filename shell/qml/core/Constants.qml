pragma Singleton
import QtQuick

QtObject {
    id: constants
    
    readonly property int zIndexBackground: 0
    readonly property int zIndexMainContent: 90
    readonly property int zIndexBottomSection: 150
    readonly property int zIndexTaskSwitcher: 200
    readonly property int zIndexPeek: 250
    readonly property int zIndexAppWindow: 600
    readonly property int zIndexSettings: 700
    readonly property int zIndexSettingsPage: 700
    readonly property int zIndexLockScreen: 1000
    readonly property int zIndexPinScreen: 1100
    readonly property int zIndexStatusBarApp: 1200
    readonly property int zIndexNavBarApp: 1200
    readonly property int zIndexQuickSettingsOverlay: 1500
    readonly property int zIndexQuickSettings: 1600  // Always on top
    readonly property int zIndexStatusBarDrag: 1700  // Highest priority
    readonly property int zIndexKeyboard: 3000  // Virtual keyboard on top of everything
    
    readonly property int gestureEdgeWidth: 50
    readonly property int gesturePeekThreshold: 100
    readonly property int gestureCommitThreshold: 200
    readonly property int gestureSwipeShort: 80
    readonly property int gestureSwipeLong: 150
    
    readonly property int animationFast: 150
    readonly property int animationNormal: 200
    readonly property int animationSlow: 300
    
    readonly property int sessionTimeout: 600000
    
    readonly property int statusBarHeight: 44
    readonly property int navBarHeight: 20
    readonly property int bottomBarHeight: 100

    readonly property int safeAreaTop: 44
    readonly property int safeAreaBottom: 20
    readonly property int safeAreaLeft: 0
    readonly property int safeAreaRight: 0
    
    readonly property int pageIndicatorSizeActive: 28
    readonly property int pageIndicatorSizeInactive: 16
    readonly property int pageIndicatorHubSizeActive: 40
    readonly property int pageIndicatorHubSizeInactive: 20
    
    readonly property int lockScreenNotificationSize: 40
    readonly property int lockScreenShortcutSize: 64
    
    readonly property int flickDecelerationFast: 8000
    readonly property int flickVelocityMax: 2000
    
    // BB10 Touch Targets (page 110 of guidelines)
    readonly property int touchTargetLarge: 90      // 9x9 du
    readonly property int touchTargetMedium: 70     // 7x7 du (focal 4.5x4.5)
    readonly property int touchTargetSmall: 60      // 6x6 du (focal 4.5x4.5)
    readonly property int touchTargetIndicator: 50  // 5x4 du for indicators
    readonly property int touchTargetMinimum: 45    // Absolute minimum
    
    // BB10 Action Bar
    readonly property int actionBarHeight: 72
    readonly property int hubHeaderHeight: 80
    
    readonly property int shadowSmall: 2
    readonly property int shadowMedium: 4
    readonly property int shadowLarge: 8
    readonly property real shadowOpacity: 0.3
    readonly property color shadowColor: "#000000"
    
    readonly property int animationDurationFast: 150
    readonly property int animationDurationNormal: 250
    readonly property int animationDurationSlow: 400
}

