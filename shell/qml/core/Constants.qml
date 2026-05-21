pragma Singleton
import QtQuick

QtObject {
    id: constants

    // This file is shared with marathon-app-runner via runtime qmldir copy.
    // ScreenMetricsCpp / MARATHON_DEBUG_ENABLED / SettingsManagerCpp are not
    // registered in the runner; the typeof guards must stay so this file
    // evaluates cleanly there.
    property real screenWidth: (typeof ScreenMetricsCpp !== "undefined" && ScreenMetricsCpp) ? ScreenMetricsCpp.width : 0
    property real screenHeight: (typeof ScreenMetricsCpp !== "undefined" && ScreenMetricsCpp) ? ScreenMetricsCpp.height : 0
    readonly property real screenDiagonal: Math.sqrt(screenWidth * screenWidth + screenHeight * screenHeight)
    // DPI source order: shell's ScreenMetricsCpp (full device probe) →
    // marathon-app-runner's MARATHON_DPI context property (forwarded from
    // the shell at launch) → baseDPI. Without the app-runner fallback the
    // sandbox always rendered at 1× while the shell rendered at DPI/baseDPI.
    property real dpi: (typeof ScreenMetricsCpp !== "undefined" && ScreenMetricsCpp && ScreenMetricsCpp.dpi > 0) ? ScreenMetricsCpp.dpi : (typeof MARATHON_DPI !== "undefined" && MARATHON_DPI > 0) ? MARATHON_DPI : baseDPI
    readonly property real baseDPI: 160
    // userScaleFactor source order: shell's SettingsManagerCpp (live binding
    // below) → marathon-app-runner's MARATHON_USER_SCALE context property →
    // 1.0 default.
    property real userScaleFactor: (typeof MARATHON_USER_SCALE !== "undefined" && MARATHON_USER_SCALE > 0) ? MARATHON_USER_SCALE : 1
    readonly property real scaleFactor: (dpi / baseDPI) * userScaleFactor
    property Binding userScaleFactorBinding
    readonly property real baseHeight: 800
    readonly property real heightScaleFactor: screenHeight / baseHeight
    readonly property real tallScreenRatio: 1.2
    readonly property real squareScreenTolerance: 100
    readonly property bool isTallScreen: (screenWidth > 0) ? (screenHeight / screenWidth > tallScreenRatio) : false
    readonly property bool isSquareScreen: Math.abs(screenWidth - screenHeight) < squareScreenTolerance
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
    readonly property int zIndexModalOverlay: 2000
    readonly property int zIndexModal: zIndexModalOverlay
    readonly property int zIndexKeyboard: 3000
    readonly property real gestureEdgeWidth: Math.round(50 * scaleFactor)
    readonly property real gesturePeekThreshold: Math.round(100 * scaleFactor)
    readonly property real gestureCommitThreshold: Math.round(200 * scaleFactor)
    readonly property real gestureSwipeShort: Math.round(80 * scaleFactor)
    readonly property real gestureSwipeLong: Math.round(150 * scaleFactor)
    readonly property real quickSettingsDismissThreshold: 0.3
    readonly property int animationFast: 150
    readonly property int animationNormal: 200
    readonly property int animationSlow: 300
    readonly property int animationDurationFast: 150
    readonly property int animationDurationNormal: 250
    readonly property int animationDurationSlow: 400
    readonly property int sessionTimeout: 600000
    property bool performanceMode: false
    readonly property bool enableAnimations: !performanceMode
    property bool debugMode: typeof MARATHON_DEBUG_ENABLED !== 'undefined' ? MARATHON_DEBUG_ENABLED : false
    readonly property int peekThreshold: 40
    readonly property int commitThreshold: 100
    // Marathon DS 2026: 28px status bar, 96px top bar, 70px tab bar,
    // 64px dock, 36px Now Bar. See docs/redesign/ANALYSIS.md §4.
    //
    // On short/square panels (HyperPixel 4.0 Square 720×720 on Hackberry
    // CM5) the DPI-driven scaleFactor lands around 1.6×; without a
    // compact override the 64+70 px dock chrome consumed ~30% of the
    // 720 px panel. compactLayout drops the base 64/70 to 48/56 so the
    // dock keeps a tappable height (still ≥ Apple HIG 44pt @1×) without
    // eating the rest of the screen.
    readonly property real statusBarHeight: Math.round(28 * scaleFactor)
    readonly property real navBarHeight: Math.round((isSquareScreen || screenHeight < 800 ? 48 : 64) * scaleFactor)
    readonly property real bottomBarHeight: Math.round((isSquareScreen || screenHeight < 800 ? 56 : 70) * scaleFactor)
    readonly property real safeAreaTop: statusBarHeight
    readonly property real safeAreaBottom: navBarHeight
    readonly property real safeAreaLeft: 0
    readonly property real safeAreaRight: 0
    readonly property real pageIndicatorSizeActive: Math.round(28 * scaleFactor)
    readonly property real pageIndicatorSizeInactive: Math.round(16 * scaleFactor)
    readonly property real pageIndicatorHubSizeActive: Math.round(40 * scaleFactor)
    readonly property real pageIndicatorHubSizeInactive: Math.round(20 * scaleFactor)
    readonly property real lockScreenNotificationSize: Math.round(40 * scaleFactor)
    readonly property real lockScreenShortcutSize: Math.round(64 * scaleFactor)
    readonly property int flickDecelerationFast: 8000
    readonly property int flickVelocityMax: 5000
    readonly property int touchFlickDeceleration: 25000
    readonly property int touchFlickVelocity: 8000
    readonly property real touchTargetLarge: Math.round(90 * scaleFactor)
    readonly property real touchTargetXLarge: Math.round(110 * scaleFactor)
    readonly property real touchTargetMedium: Math.round(70 * scaleFactor)
    readonly property real touchTargetSmall: Math.round(60 * scaleFactor)
    readonly property real touchTargetIndicator: Math.round(50 * scaleFactor)
    readonly property real touchTargetMinimum: Math.max(44, Math.round(45 * scaleFactor))
    readonly property real inputHeight: Math.round(48 * scaleFactor)
    readonly property real listItemHeight: Math.round(56 * scaleFactor)
    readonly property real iconButtonSize: Math.round(20 * scaleFactor)
    readonly property real smallIndicatorSize: Math.round(8 * scaleFactor)
    readonly property real mediumIndicatorSize: Math.round(12 * scaleFactor)
    readonly property real dividerHeight: Math.max(1, Math.round(1 * scaleFactor))
    readonly property real actionBarHeight: Math.round(72 * scaleFactor)
    readonly property real hubHeaderHeight: Math.round(80 * scaleFactor)
    readonly property real appIconSize: Math.round(64 * scaleFactor)
    readonly property real appGridSpacing: Math.round(20 * scaleFactor)
    readonly property real appLabelHeight: Math.round(32 * scaleFactor)
    readonly property real cardHeight: Math.round(160 * scaleFactor)
    readonly property real cardWidth: Math.round(screenWidth * 0.42)
    readonly property real cardBannerHeight: Math.round(60 * scaleFactor)
    // DS .m-card uses radius 4 (--r-md). Was 20 (off-spec).
    readonly property real cardRadius: Math.round(4 * scaleFactor)
    readonly property real fontSizeXSmall: Math.round(12 * scaleFactor)
    readonly property real fontSizeSmall: Math.round(14 * scaleFactor)
    readonly property real fontSizeMedium: Math.round(16 * scaleFactor)
    readonly property real fontSizeLarge: Math.round(18 * scaleFactor)
    readonly property real fontSizeXLarge: Math.round(24 * scaleFactor)
    readonly property real fontSizeXXLarge: Math.round(32 * scaleFactor)
    readonly property real fontSizeHuge: Math.round(48 * scaleFactor)
    readonly property real fontSizeGigantic: Math.round(96 * scaleFactor)
    readonly property real spacingXSmall: Math.round(5 * scaleFactor)
    readonly property real spacingSmall: Math.round(10 * scaleFactor)
    readonly property real spacingMedium: Math.round(16 * scaleFactor)
    readonly property real spacingLarge: Math.round(20 * scaleFactor)
    readonly property real spacingXLarge: Math.round(32 * scaleFactor)
    readonly property real spacingXXLarge: Math.round(40 * scaleFactor)
    // DS radius scale (marathon-tokens.css):
    //   --r-sm  = 2  · inline tags
    //   --r-md  = 4  · DEFAULT — cards, buttons, rows, dialogs, chips
    //   --r-lg  = 6  · sheets, dialogs when softer needed
    //   --r-xl  = 8  · map / gallery thumbs (max non-pill / non-squircle)
    //   --r-full= 999· pills (sliders, filter chips, toggles)
    //   squircle=14  · APP ICONS ONLY
    //
    // The DS explicitly forbids 12, 14, 16, 18 ("they drift toward iOS
    // softness"). The legacy Constants ramp had Medium=8, Large=12,
    // XLarge=20 — every value above r-md was off-spec. New ramp:
    //   Small=4, Medium=4, Large=6, XLarge=8.
    // Callers using Medium/Large/XLarge migrate downward without code
    // changes; the DS-canonical MRadius store is preferred for new code.
    readonly property real borderRadiusSharp: 0
    readonly property real borderRadiusSmall: Math.round(4 * scaleFactor)
    readonly property real borderRadiusMedium: Math.round(4 * scaleFactor)
    readonly property real borderRadiusLarge: Math.round(6 * scaleFactor)
    readonly property real borderRadiusXLarge: Math.round(8 * scaleFactor)
    readonly property real borderWidthThin: Math.max(1, Math.round(1 * scaleFactor))
    readonly property real borderWidthMedium: Math.max(1, Math.round(2 * scaleFactor))
    readonly property real borderWidthThick: Math.max(2, Math.round(3 * scaleFactor))
    readonly property bool enableAntialiasing: true
    readonly property real iconSizeSmall: Math.round(20 * scaleFactor)
    readonly property real iconSizeMedium: Math.round(32 * scaleFactor)
    readonly property real iconSizeLarge: Math.round(40 * scaleFactor)
    readonly property real iconSizeXLarge: Math.round(64 * scaleFactor)
    readonly property real shadowSmall: Math.max(1, Math.round(2 * scaleFactor))
    readonly property real shadowMedium: Math.max(2, Math.round(4 * scaleFactor))
    readonly property real shadowLarge: Math.max(4, Math.round(8 * scaleFactor))
    readonly property real shadowOpacity: 0.3
    readonly property color shadowColor: "#000000"
    readonly property real modalMaxWidth: Math.round(screenWidth * 0.85)
    readonly property real modalMaxHeight: Math.round(screenHeight * 0.75)
    readonly property real toastHeight: Math.round(64 * scaleFactor)
    readonly property real hudSize: Math.round(128 * scaleFactor)

    function updateScreenSize(width, height, deviceDpi) {
        screenWidth = width;
        screenHeight = height;
        var dpiMin = 50;
        var dpiMax = 1000;
        var newDpi = baseDPI;
        var dpiSource = "fallback";
        if (deviceDpi && deviceDpi >= dpiMin && deviceDpi <= dpiMax) {
            newDpi = deviceDpi;
            dpiSource = "reported";
        } else {
            newDpi = baseDPI;
            dpiSource = "fallback";
            if (deviceDpi && (deviceDpi < dpiMin || deviceDpi > dpiMax))
                console.warn("[WARN] Constants:", "Invalid deviceDPI (" + deviceDpi + "), using baseDPI: " + newDpi);
        }
        if (Math.abs(dpi - newDpi) > 0.1) {
            dpi = newDpi;
            if (debugMode)
                console.log("[DEBUG] Constants:", "Screen: " + width.toFixed(0) + "×" + height.toFixed(0) + " @ " + dpi.toFixed(0) + " DPI (source: " + dpiSource + ", scaleFactor: " + scaleFactor.toFixed(2) + ")");
        }
    }

    userScaleFactorBinding: Binding {
        target: constants
        property: "userScaleFactor"
        value: typeof SettingsManagerCpp !== 'undefined' ? SettingsManagerCpp.userScaleFactor : 1
        when: typeof SettingsManagerCpp !== 'undefined'
        restoreMode: Binding.RestoreBinding
    }
}
