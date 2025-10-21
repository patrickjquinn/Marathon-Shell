pragma Singleton
import QtQuick

QtObject {
    id: constants
    
    // =========================================================================
    // RESPONSIVE SIZING SYSTEM
    // =========================================================================
    
    // Base screen dimensions (set by shell on startup via updateScreenSize)
    property real screenWidth: 720
    property real screenHeight: 1280
    property real screenDiagonal: 1477.53  // Updated by updateScreenSize()
    property real dpi: 320
    
    // Responsive scaling - scale everything based on screen height
    // Base: 800px height (optimized for Passport 720x720)
    readonly property real baseHeight: 800
    property real userScaleFactor: 1.0  // User preference (0.75, 1.0, 1.25, 1.5)
    readonly property real scaleFactor: (screenHeight / baseHeight) * userScaleFactor
    
    // Aspect ratio detection
    readonly property bool isTallScreen: screenHeight / screenWidth > 1.2
    readonly property bool isSquareScreen: Math.abs(screenWidth - screenHeight) < 100
    
    // =========================================================================
    // Z-INDEX LAYERS
    // =========================================================================
    
    readonly property int zIndexBackground: 0
    readonly property int zIndexMainContent: 90
    readonly property int zIndexBottomSection: 150
    readonly property int zIndexTaskSwitcher: 200
    readonly property int zIndexAppWindow: 600
    readonly property int zIndexPeekGesture: 650
    readonly property int zIndexPeek: 700
    readonly property int zIndexSettings: 700
    readonly property int zIndexSettingsPage: 700
    readonly property int zIndexLockScreen: 1000
    readonly property int zIndexPinScreen: 1100
    readonly property int zIndexSearch: 1150
    readonly property int zIndexStatusBarApp: 1200
    readonly property int zIndexQuickSettings: 1200
    readonly property int zIndexQuickSettingsOverlay: 1300
    readonly property int zIndexNavBarApp: 1600
    readonly property int zIndexStatusBarDrag: 1700
    readonly property int zIndexKeyboard: 3000
    
    // =========================================================================
    // GESTURE THRESHOLDS (responsive)
    // =========================================================================
    
    readonly property real gestureEdgeWidth: Math.round(50 * scaleFactor)
    readonly property real gesturePeekThreshold: Math.round(100 * scaleFactor)
    readonly property real gestureCommitThreshold: Math.round(200 * scaleFactor)
    readonly property real gestureSwipeShort: Math.round(80 * scaleFactor)
    readonly property real gestureSwipeLong: Math.round(150 * scaleFactor)
    
    // =========================================================================
    // ANIMATION DURATIONS (time-based, not size-based)
    // =========================================================================
    
    readonly property int animationFast: 150
    readonly property int animationNormal: 200
    readonly property int animationSlow: 300
    readonly property int animationDurationFast: 150
    readonly property int animationDurationNormal: 250
    readonly property int animationDurationSlow: 400
    
    // =========================================================================
    // SESSION & TIMEOUT
    // =========================================================================
    
    readonly property int sessionTimeout: 600000  // 10 minutes
    
    // =========================================================================
    // PERFORMANCE MODE
    // =========================================================================
    
    property bool performanceMode: false
    readonly property bool enableAnimations: !performanceMode
    
    // Debug mode - controlled by MARATHON_DEBUG environment variable
    property bool debugMode: typeof MARATHON_DEBUG_ENABLED !== 'undefined' ? MARATHON_DEBUG_ENABLED : false
    
    // =========================================================================
    // LAYOUT DIMENSIONS (responsive)
    // =========================================================================
    
    readonly property real statusBarHeight: Math.round(44 * scaleFactor)
    readonly property real navBarHeight: Math.round(20 * scaleFactor)
    readonly property real bottomBarHeight: Math.round(100 * scaleFactor)
    
    readonly property real safeAreaTop: statusBarHeight
    readonly property real safeAreaBottom: navBarHeight
    readonly property real safeAreaLeft: 0
    readonly property real safeAreaRight: 0
    
    // =========================================================================
    // PAGE INDICATORS (responsive)
    // =========================================================================
    
    readonly property real pageIndicatorSizeActive: Math.round(28 * scaleFactor)
    readonly property real pageIndicatorSizeInactive: Math.round(16 * scaleFactor)
    readonly property real pageIndicatorHubSizeActive: Math.round(40 * scaleFactor)
    readonly property real pageIndicatorHubSizeInactive: Math.round(20 * scaleFactor)
    
    // =========================================================================
    // LOCK SCREEN (responsive)
    // =========================================================================
    
    readonly property real lockScreenNotificationSize: Math.round(40 * scaleFactor)
    readonly property real lockScreenShortcutSize: Math.round(64 * scaleFactor)
    
    // =========================================================================
    // SCROLLING PERFORMANCE (physics-based)
    // =========================================================================
    
    readonly property int flickDecelerationFast: 8000
    readonly property int flickVelocityMax: 2000
    
    // =========================================================================
    // BB10 TOUCH TARGETS (responsive)
    // =========================================================================
    
    readonly property real touchTargetLarge: Math.round(90 * scaleFactor)
    readonly property real touchTargetMedium: Math.round(70 * scaleFactor)
    readonly property real touchTargetSmall: Math.round(60 * scaleFactor)
    readonly property real touchTargetIndicator: Math.round(50 * scaleFactor)
    readonly property real touchTargetMinimum: Math.max(44, Math.round(45 * scaleFactor))
    
    // =========================================================================
    // BB10 ACTION BAR (responsive)
    // =========================================================================
    
    readonly property real actionBarHeight: Math.round(72 * scaleFactor)
    readonly property real hubHeaderHeight: Math.round(80 * scaleFactor)
    
    // =========================================================================
    // APP GRID (responsive)
    // =========================================================================
    
    readonly property real appIconSize: Math.round(72 * scaleFactor)
    readonly property real appGridSpacing: Math.round(20 * scaleFactor)
    readonly property real appLabelHeight: Math.round(32 * scaleFactor)
    
    // =========================================================================
    // CARDS (responsive)
    // =========================================================================
    
    readonly property real cardHeight: Math.round(160 * scaleFactor)
    readonly property real cardWidth: Math.round(screenWidth * 0.42)
    readonly property real cardBannerHeight: Math.round(60 * scaleFactor)
    readonly property real cardRadius: Math.round(20 * scaleFactor)
    
    // =========================================================================
    // TYPOGRAPHY (responsive)
    // =========================================================================
    
    readonly property real fontSizeXSmall: Math.round(12 * scaleFactor)
    readonly property real fontSizeSmall: Math.round(14 * scaleFactor)
    readonly property real fontSizeMedium: Math.round(16 * scaleFactor)
    readonly property real fontSizeLarge: Math.round(18 * scaleFactor)
    readonly property real fontSizeXLarge: Math.round(24 * scaleFactor)
    readonly property real fontSizeXXLarge: Math.round(32 * scaleFactor)
    readonly property real fontSizeHuge: Math.round(48 * scaleFactor)
    
    // =========================================================================
    // SPACING SYSTEM (responsive)
    // =========================================================================
    
    readonly property real spacingXSmall: Math.round(5 * scaleFactor)
    readonly property real spacingSmall: Math.round(10 * scaleFactor)
    readonly property real spacingMedium: Math.round(16 * scaleFactor)
    readonly property real spacingLarge: Math.round(20 * scaleFactor)
    readonly property real spacingXLarge: Math.round(32 * scaleFactor)
    readonly property real spacingXXLarge: Math.round(40 * scaleFactor)
    
    // =========================================================================
    // BORDERS & RADII (responsive, BB10-inspired sharp)
    // =========================================================================
    
    readonly property real borderRadiusSharp: 0
    readonly property real borderRadiusSmall: 4
    readonly property real borderRadiusMedium: 8
    readonly property real borderRadiusLarge: 12
    readonly property real borderRadiusXLarge: Math.round(20 * scaleFactor)
    
    readonly property real borderWidthThin: 1
    readonly property real borderWidthMedium: 2
    readonly property real borderWidthThick: 3
    
    readonly property bool enableAntialiasing: true
    
    // =========================================================================
    // ICON SIZES (responsive)
    // =========================================================================
    
    readonly property real iconSizeSmall: Math.round(20 * scaleFactor)
    readonly property real iconSizeMedium: Math.round(32 * scaleFactor)
    readonly property real iconSizeLarge: Math.round(40 * scaleFactor)
    readonly property real iconSizeXLarge: Math.round(64 * scaleFactor)
    
    // =========================================================================
    // SHADOWS (responsive)
    // =========================================================================
    
    readonly property real shadowSmall: Math.max(1, Math.round(2 * scaleFactor))
    readonly property real shadowMedium: Math.max(2, Math.round(4 * scaleFactor))
    readonly property real shadowLarge: Math.max(4, Math.round(8 * scaleFactor))
    readonly property real shadowOpacity: 0.3
    readonly property color shadowColor: "#000000"
    
    // =========================================================================
    // MODAL & OVERLAY SIZES (responsive)
    // =========================================================================
    
    readonly property real modalMaxWidth: Math.round(screenWidth * 0.85)
    readonly property real modalMaxHeight: Math.round(screenHeight * 0.75)
    readonly property real toastHeight: Math.round(64 * scaleFactor)
    readonly property real hudSize: Math.round(128 * scaleFactor)
    
    // =========================================================================
    // HELPER FUNCTION
    // =========================================================================
    
    // Update screen dimensions (called by shell on startup/resize)
    function updateScreenSize(width, height, deviceDpi) {
        screenWidth = width
        screenHeight = height
        screenDiagonal = Math.sqrt(width * width + height * height)
        dpi = deviceDpi || 320
    }
}
