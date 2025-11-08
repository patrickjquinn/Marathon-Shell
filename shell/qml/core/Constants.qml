pragma Singleton
import QtQuick

QtObject {
    id: constants
    
    // =======================================================================
    // CONFIG HELPER (Load from marathon-config.json with fallbacks)
    // =========================================================================
    
    function cfg(section, key, fallback) {
        if (typeof MarathonConfig === 'undefined') return fallback
        var sec = MarathonConfig[section]
        if (!sec) return fallback
        var val = sec[key]
        return (val !== undefined) ? val : fallback
    }
    
    // =========================================================================
    // RESPONSIVE SIZING SYSTEM (Loaded from marathon-config.json)
    // =========================================================================
    
    // Base screen dimensions (set by shell on startup via updateScreenSize)
    property real screenWidth: 540  // OnePlus 6 50% scale (actual: 1080)
    property real screenHeight: 1140  // OnePlus 6 50% scale (actual: 2280)
    property real screenDiagonal: 1263.15  // Updated by updateScreenSize()
    property real dpi: 120  // Matches baseDPI for 1:1 scaling in desktop testing (device: 320)
    
    // Responsive scaling - scale everything based on ACTUAL DPI (from config)
    readonly property real baseDPI: cfg("responsive", "baseDPI", 160)
    property real userScaleFactor: 1.0  // Initialized from SettingsManagerCpp
    readonly property real scaleFactor: (dpi / baseDPI) * userScaleFactor
    
    // Two-way binding for userScaleFactor
    property Binding userScaleFactorBinding: Binding {
        target: constants
        property: "userScaleFactor"
        value: typeof SettingsManagerCpp !== 'undefined' ? SettingsManagerCpp.userScaleFactor : cfg("responsive", "defaultUserScaleFactor", 1.0)
        restoreMode: Binding.RestoreBinding
        when: typeof SettingsManagerCpp !== 'undefined'
    }
    
    // Legacy height-based scaling (from config)
    readonly property real baseHeight: cfg("responsive", "baseHeight", 800)
    readonly property real heightScaleFactor: screenHeight / baseHeight
    
    // Aspect ratio detection (from config)
    readonly property real tallScreenRatio: cfg("responsive", "tallScreenRatio", 1.2)
    readonly property real squareScreenTolerance: cfg("responsive", "squareScreenTolerance", 100)
    readonly property bool isTallScreen: screenHeight / screenWidth > tallScreenRatio
    readonly property bool isSquareScreen: Math.abs(screenWidth - screenHeight) < squareScreenTolerance
    
    // =========================================================================
    // Z-INDEX LAYERS (Loaded from marathon-config.json)
    // =========================================================================
    
    readonly property int zIndexBackground: cfg("zIndex", "background", 0)
    readonly property int zIndexMainContent: cfg("zIndex", "mainContent", 90)
    readonly property int zIndexBottomSection: cfg("zIndex", "bottomSection", 150)
    readonly property int zIndexTaskSwitcher: cfg("zIndex", "taskSwitcher", 200)
    readonly property int zIndexAppWindow: cfg("zIndex", "appWindow", 600)
    readonly property int zIndexPeekGesture: cfg("zIndex", "peekGesture", 650)
    readonly property int zIndexPeek: cfg("zIndex", "peek", 700)
    readonly property int zIndexSettings: cfg("zIndex", "settings", 700)
    readonly property int zIndexSettingsPage: cfg("zIndex", "settingsPage", 700)
    readonly property int zIndexLockScreen: cfg("zIndex", "lockScreen", 1000)
    readonly property int zIndexPinScreen: cfg("zIndex", "pinScreen", 1100)
    readonly property int zIndexSearch: cfg("zIndex", "search", 1150)
    readonly property int zIndexStatusBarApp: cfg("zIndex", "statusBarApp", 1200)
    readonly property int zIndexQuickSettings: cfg("zIndex", "quickSettings", 1200)
    readonly property int zIndexQuickSettingsOverlay: cfg("zIndex", "quickSettingsOverlay", 1300)
    readonly property int zIndexNavBarApp: cfg("zIndex", "navBarApp", 1600)
    readonly property int zIndexStatusBarDrag: cfg("zIndex", "statusBarDrag", 1700)
    readonly property int zIndexModalOverlay: cfg("zIndex", "modalOverlay", 2000)
    readonly property int zIndexKeyboard: cfg("zIndex", "keyboard", 3000)
    
    // =========================================================================
    // GESTURE THRESHOLDS (responsive, from config)
    // =========================================================================
    
    readonly property real gestureEdgeWidth: Math.round(cfg("gestures", "edgeWidth", 50) * scaleFactor)
    readonly property real gesturePeekThreshold: Math.round(cfg("gestures", "peekThreshold", 100) * scaleFactor)
    readonly property real gestureCommitThreshold: Math.round(cfg("gestures", "commitThreshold", 200) * scaleFactor)
    readonly property real gestureSwipeShort: Math.round(cfg("gestures", "swipeShort", 80) * scaleFactor)
    readonly property real gestureSwipeLong: Math.round(cfg("gestures", "swipeLong", 150) * scaleFactor)
    
    // =========================================================================
    // ANIMATION DURATIONS (time-based, not size-based, from config)
    // =========================================================================
    
    readonly property int animationFast: cfg("animations", "fast", 150)
    readonly property int animationNormal: cfg("animations", "normal", 200)
    readonly property int animationSlow: cfg("animations", "slow", 300)
    readonly property int animationDurationFast: cfg("animations", "durationFast", 150)
    readonly property int animationDurationNormal: cfg("animations", "durationNormal", 250)
    readonly property int animationDurationSlow: cfg("animations", "durationSlow", 400)
    
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
    // PEEK GESTURE THRESHOLDS (from legacy Theme.qml)
    // =========================================================================
    
    readonly property int peekThreshold: 40
    readonly property int commitThreshold: 100
    
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
    // SCROLLING PERFORMANCE (physics-based, tuned for touch)
    // =========================================================================
    
    readonly property int flickDecelerationFast: 8000
    readonly property int flickVelocityMax: 5000  // Higher for responsive touch
    
    // Touch-optimized flick physics
    readonly property int touchFlickDeceleration: 25000  // Snappy page transitions
    readonly property int touchFlickVelocity: 8000  // Responsive to fast flicks
    
    // =========================================================================
    // BB10 TOUCH TARGETS (responsive)
    // =========================================================================
    
    readonly property real touchTargetLarge: Math.round(90 * scaleFactor)
    readonly property real touchTargetMedium: Math.round(70 * scaleFactor)
    readonly property real touchTargetSmall: Math.round(60 * scaleFactor)
    readonly property real touchTargetIndicator: Math.round(50 * scaleFactor)
    readonly property real touchTargetMinimum: Math.max(44, Math.round(45 * scaleFactor))
    
    // Common component dimensions (responsive)
    readonly property real inputHeight: Math.round(48 * scaleFactor)  // Standard text input
    readonly property real listItemHeight: Math.round(56 * scaleFactor)  // Standard list item
    readonly property real iconButtonSize: Math.round(20 * scaleFactor)  // Small icon button
    readonly property real smallIndicatorSize: Math.round(8 * scaleFactor)  // Small dots/indicators
    readonly property real mediumIndicatorSize: Math.round(12 * scaleFactor)  // Medium indicators
    readonly property real dividerHeight: Math.max(1, Math.round(1 * scaleFactor))  // Divider lines
    
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
    readonly property real fontSizeGigantic: Math.round(96 * scaleFactor)  // Lock screen clock
    
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
    readonly property real borderRadiusSmall: Math.round(4 * scaleFactor)
    readonly property real borderRadiusMedium: Math.round(8 * scaleFactor)
    readonly property real borderRadiusLarge: Math.round(12 * scaleFactor)
    readonly property real borderRadiusXLarge: Math.round(20 * scaleFactor)
    
    readonly property real borderWidthThin: Math.max(1, Math.round(1 * scaleFactor))
    readonly property real borderWidthMedium: Math.max(1, Math.round(2 * scaleFactor))
    readonly property real borderWidthThick: Math.max(2, Math.round(3 * scaleFactor))
    
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
        
        // For desktop testing with scaled-down windows (< 800px wide),
        // use baseDPI to get 1:1 rendering. User can adjust with userScaleFactor in settings.
        if (width < 800) {
            dpi = baseDPI  // Desktop testing: 160 DPI for 1:1 rendering
            console.log("[Constants] Desktop mode: Using baseDPI=" + baseDPI + " for 1:1 scaling")
        } else {
            dpi = deviceDpi || 320  // Real device: Use actual screen DPI
        }
    }
}
