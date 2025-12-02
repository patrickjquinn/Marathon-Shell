import QtQuick
import QtQuick.Window
import MarathonOS.Shell
import "./components" as Comp
import MarathonUI.Theme

// qmllint disable missing-property unqualified import
Item {
    id: shell
    focus: true  // Enable keyboard input

    // Slate Font Family - bundled font resources
    FontLoader {
        id: slateLight
        source: "qrc:/fonts/Slate-Light.ttf"
    }
    FontLoader {
        id: slateBook
        source: "qrc:/fonts/Slate-Book.ttf"
    }
    FontLoader {
        id: slateRegular
        source: "qrc:/fonts/Slate-Regular.ttf"
    }
    FontLoader {
        id: slateMedium
        source: "qrc:/fonts/Slate-Medium.ttf"
    }
    FontLoader {
        id: slateBold
        source: "qrc:/fonts/Slate-Bold.ttf"
    }



    property var compositor: null
    property alias appWindowContainer: appWindowContainer

    // State management moved to stores
    property bool showPinScreen: false
    property bool isTransitioningToActiveFrames: false
    property int currentPage: 0
    property int totalPages: 1

    // Pending notification action after unlock
    property var pendingNotification: null

    // Dynamic Quick Settings sizing (threshold from config)
    readonly property real maxQuickSettingsHeight: shell.height - Constants.statusBarHeight
    readonly property real quickSettingsThreshold: maxQuickSettingsHeight * Constants.quickSettingsDismissThreshold

    // Debounce timer for window resize events (prevent layout thrashing)
    Timer {
        id: resizeDebounceTimer
        interval: 100
        onTriggered: {
            Constants.updateScreenSize(shell.width, shell.height, Screen.pixelDensity * 25.4);
        }
    }

    // Handle deep link requests from NavigationRouter
    Connections {
        target: NavigationRouter

        function onDeepLinkRequested(appId, route, params) {
            DeepLinkHandler.appWindow = appWindow;
            DeepLinkHandler.handleDeepLink(appId, route, params);
        }
    }

    // Handle notification clicks (deep linking)
    Connections {
        target: NotificationService

        function onNotificationClicked(id) {
            NotificationHandler.handleNotificationClick(id);
        }

        function onNotificationActionTriggered(id, action) {
            NotificationHandler.handleNotificationAction(id, action);
        }
    }

    Comp.ShellInitialization {
        id: shellInitialization
    }

    Component.onCompleted: {
        compositor = shellInitialization.initialize(shell, Window.window);

        // Initialize global services
        AppLaunchService.compositor = compositor;
        AppLaunchService.appWindow = appWindow;

        // Initialize ScreenshotService with shell window reference
        ScreenshotService.shellWindow = shell;

        // CRITICAL: Connect compositor signals AFTER compositor is created
        // The Connections block above doesn't work because compositor is null when it's created
        if (compositor) {
            compositor.surfaceCreated.connect(shell, function (surface, surfaceId, xdgSurface) {
                compositorConnections.setupConnections(compositor, appWindow, AppLaunchService.pendingNativeApp);
                compositorConnections.handleSurfaceCreated(surface, surfaceId, xdgSurface);
            });

            compositor.surfaceDestroyed.connect(shell, function (surface, surfaceId) {
                // CRITICAL: Remove task from TaskModel when surface is destroyed
                // This handles both process termination AND surface unmapping (when app closes internally)
                if (typeof TaskModel !== 'undefined') {
                    var task = TaskModel.getTaskBySurfaceId(surfaceId);
                    if (task) {
                        TaskModel.closeTask(task.id);
                    }
                }

                // Also notify CompositorConnections for window cleanup
                compositorConnections.handleSurfaceDestroyed(surface, surfaceId);
            });

            compositor.appLaunched.connect(shell, function (command, pid) {
                compositorConnections.handleAppLaunched(command, pid);
            });

            compositor.appClosed.connect(shell, function (pid) {
                compositorConnections.handleAppClosed(pid);
            });
        }
    }

    // Handle window resize (for desktop/tablet) - debounced to prevent layout thrashing
    onWidthChanged: {
        if (Constants.screenWidth > 0) {  // Only after initialization
            resizeDebounceTimer.restart();
        }
    }
    onHeightChanged: {
        if (Constants.screenHeight > 0) {  // Only after initialization
            resizeDebounceTimer.restart();
        }
    }

    // State-based navigation using centralized stores
    // Don't show lock screen until OOBE is complete
    // Use showLockScreen (not isLocked) to determine if lock screen should be visible
    // This allows lock screen to show with unlocked icon during grace period
    state: SettingsManagerCpp.firstRunComplete ? (SessionStore.showLockScreen ? (showPinScreen ? "pinEntry" : "locked") : (UIStore.appWindowOpen ? "app" : "home")) : "home"

    states: [
        State {
            name: "locked"
            PropertyChanges {
                lockScreen.visible: true
                lockScreen.enabled: true
                lockScreen.expandedCategory: ""  // Close expanded notifications
            }
            StateChangeScript {
                script: {
                    // Reset swipe progress when entering locked state
                    lockScreen.swipeProgress = 0.0;
                }
            }
            // PIN screen HIDDEN behind lock screen until swipe triggers pinEntry state
            PropertyChanges {
                pinScreen.visible: false
                pinScreen.enabled: false
                pinScreen.opacity: 0.0
            }
            // NEVER show mainContent when session invalid (security!)
            // Only fade in when session IS valid
            PropertyChanges {
                mainContent.visible: SessionStore.checkSession()
                mainContent.enabled: false
                mainContent.opacity: SessionStore.checkSession() ? Math.pow(lockScreen.swipeProgress, 0.7) : 0.0
            }
            PropertyChanges {
                appWindow.visible: false
            }
            PropertyChanges {
                navBar.visible: false
            }
        },
        State {
            name: "pinEntry"
            PropertyChanges {
                lockScreen.visible: false
                lockScreen.enabled: false
            }
            PropertyChanges {
                pinScreen.visible: true
                pinScreen.enabled: true
                pinScreen.opacity: 1.0
            }
            // HIDE mainContent completely during PIN entry (security!)
            PropertyChanges {
                mainContent.visible: false
                mainContent.enabled: false
                mainContent.opacity: 0.0
            }
            PropertyChanges {
                appWindow.visible: false
            }
            PropertyChanges {
                navBar.visible: true  // Show nav bar for keyboard access
                navBar.pinScreenMode: true  // Hide pill and search, keep keyboard button
            }
        },
        State {
            name: "home"
            StateChangeScript {
                script: {
                    shell.forceActiveFocus()
                }
            }
            PropertyChanges {
                lockScreen.visible: false
                lockScreen.enabled: false
            }
            PropertyChanges {
                pinScreen.visible: false
                pinScreen.enabled: false
                pinScreen.opacity: 0.0
            }
            PropertyChanges {
                mainContent.visible: true
                mainContent.enabled: true
                mainContent.opacity: 1.0
            }
            PropertyChanges {
                appWindow.visible: false
            }
            PropertyChanges {
                navBar.visible: true
                navBar.pinScreenMode: false  // Normal mode with pill and search
            }
        },
        State {
            name: "app"
            PropertyChanges {
                lockScreen.visible: false
                lockScreen.enabled: false
            }
            PropertyChanges {
                pinScreen.visible: false
                pinScreen.enabled: false
            }
            PropertyChanges {
                mainContent.visible: false
                mainContent.enabled: false
            }
            PropertyChanges {
                appWindow.visible: true
            }
            PropertyChanges {
                statusBar.visible: true
                statusBar.z: Constants.zIndexStatusBarApp
            }
            PropertyChanges {
                navBar.visible: true
                navBar.z: Constants.zIndexNavBarApp
                navBar.pinScreenMode: false  // Normal mode with pill and search
            }
        }
    ]

    transitions: [
        Transition {
            from: "locked"
            to: "home"
            // No animation needed - swipe gesture already animated swipeProgress to 1.0
            PropertyAction {
                target: lockScreen
                property: "visible"
                value: false
            }
        },
        Transition {
            from: "locked"
            to: "pinEntry"
            ParallelAnimation {
                NumberAnimation {
                    target: lockScreen
                    property: "swipeProgress"
                    to: 1.0
                    duration: 200
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: pinScreen
                    property: "opacity"
                    to: 1.0
                    duration: 200
                    easing.type: Easing.InCubic
                }
                PropertyAction {
                    target: lockScreen
                    property: "visible"
                    value: false
                }
                PropertyAction {
                    target: lockScreen
                    property: "enabled"
                    value: false
                }
                PropertyAction {
                    target: pinScreen
                    property: "enabled"
                    value: true
                }
            }
        },
        Transition {
            from: "pinEntry"
            to: "home"
            SequentialAnimation {
                NumberAnimation {
                    target: pinScreen
                    property: "opacity"
                    to: 0
                    duration: Constants.animationNormal
                    easing.type: Easing.OutCubic
                }
                PropertyAction {
                    target: pinScreen
                    property: "visible"
                    value: false
                }
            }
        }
    ]

    Image {
        anchors.fill: parent
        source: WallpaperStore.path
        fillMode: Image.PreserveAspectCrop
        z: Constants.zIndexBackground
    }

    // Main home screen content - controlled by State system
    Column {
        id: mainContent
        anchors.fill: parent
        z: Constants.zIndexMainContent

        // Fade in as lock screen fades out during swipe (if session valid)
        Item {
            width: parent.width
            height: Constants.statusBarHeight
        }

        Item {
            width: parent.width
            height: parent.height - Constants.statusBarHeight - Constants.navBarHeight
            z: Constants.zIndexMainContent + 10

            MarathonPageView {
                id: pageView
                anchors.fill: parent
                z: Constants.zIndexMainContent + 10
                isGestureActive: navBar.isAppOpen && shell.isTransitioningToActiveFrames
                compositor: shell.compositor  // Pass compositor for native app management

                onCurrentPageChanged: {
                    Logger.nav("page" + shell.currentPage, "page" + currentPage, "navigation");
                    // If we're on an app grid page (currentPage >= 0), use the internal page
                    if (currentPage >= 0) {
                        shell.currentPage = pageView.internalAppGridPage;
                        shell.totalPages = Math.max(1, Math.ceil(AppModel.count / 16));
                    } else {
                        // For Hub (-2) and Task Switcher (-1), use the regular currentPage
                        shell.currentPage = currentPage;
                    }
                }

                onInternalAppGridPageChanged: {
                    // Update shell's current page when internal app grid page changes
                    if (pageView.currentPage >= 0) {
                        shell.currentPage = pageView.internalAppGridPage;
                        Logger.debug("Shell", "Internal app grid page changed to: " + pageView.internalAppGridPage);
                    }
                }

                onAppLaunched: app => {
                    AppLaunchService.launchApp(app, compositor, appWindow);
                }

                Component.onCompleted: {
                    shell.totalPages = Math.max(1, Math.ceil(AppModel.count / 16));
                }
            }

            Item {
                id: bottomSection
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: messagingHub.height + bottomBar.height
                z: Constants.zIndexBottomSection

                MarathonMessagingHub {
                    id: messagingHub
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: bottomBar.top
                }

                MarathonBottomBar {
                    id: bottomBar
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    currentPage: shell.currentPage
                    totalPages: shell.totalPages
                    showNotifications: shell.currentPage > 0

                    onAppLaunched: app => {
                        AppLaunchService.launchApp(app, compositor, appWindow);
                    }

                    onPageNavigationRequested: page => {
                        Logger.info("BottomBar", "Navigation requested to page: " + page);
                        pageView.navigateToPage(page);
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: Constants.navBarHeight
        }
    }

    MarathonStatusBar {
        id: statusBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        z: Constants.zIndexStatusBarApp
    }

    MarathonNavBar {
        id: navBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom  // ALWAYS at bottom
        z: Constants.zIndexNavBarApp
        isAppOpen: UIStore.appWindowOpen || UIStore.settingsOpen
        keyboardVisible: virtualKeyboard.active
        searchActive: UIStore.searchOpen

        onToggleKeyboard: {
            Logger.info("Shell", "Keyboard button clicked, current: " + virtualKeyboard.active);
            virtualKeyboard.active = !virtualKeyboard.active;
            Logger.info("Shell", "Keyboard toggled to: " + virtualKeyboard.active);
        }

        onToggleSearch: {
            Logger.info("Shell", "Search button clicked from nav bar");
            UIStore.toggleSearch();
            HapticService.light();
        }

        onSwipeLeft: {
            if (pageView.currentIndex < pageView.count - 1) {
                pageView.incrementCurrentIndex();
                Router.navigateLeft();
            }
        }

        onSwipeRight: {
            // Check if app can handle forward navigation first
            if (UIStore.appWindowOpen && typeof AppLifecycleManager !== 'undefined') {
                var handled = AppLifecycleManager.handleSystemForward();
                if (handled) {
                    return;
                }
            }

            // Otherwise, navigate pages
            if (pageView.currentIndex > 0) {
                pageView.decrementCurrentIndex();
                Router.navigateRight();
            }
        }

        onSwipeBack: {
            Logger.info("NavBar", "Back gesture detected");

            if (typeof AppLifecycleManager !== 'undefined') {
                var handled = AppLifecycleManager.handleSystemBack();
                if (!handled) {
                    Logger.info("NavBar", "App didn't handle back, closing");
                    if (UIStore.appWindowOpen) {
                        UIStore.closeApp();
                    }
                }
            } else {
                Logger.info("NavBar", "AppLifecycleManager unavailable, closing directly");
                if (UIStore.appWindowOpen) {
                    UIStore.closeApp();
                }
            }
        }

        onShortSwipeUp: {
            // Dismiss keyboard if visible, otherwise go home
            if (virtualKeyboard.active) {
                Logger.info("NavBar", "Dismissing keyboard with short swipe up");
                HapticService.light();
                virtualKeyboard.active = false;
                return;
            }

            Logger.gesture("NavBar", "shortSwipeUp", {
                target: "home"
            });
            pageView.currentIndex = 2;
            Router.goToAppPage(0);
        }

        onLongSwipeUp: {
            Logger.info("NavBar", "━━━━━━━ LONG SWIPE UP RECEIVED ━━━━━━━");

            // Dismiss keyboard if visible, otherwise task switcher
            if (virtualKeyboard.active) {
                Logger.info("NavBar", "Dismissing keyboard with long swipe up");
                HapticService.light();
                virtualKeyboard.active = false;
                return;
            }

            Logger.gesture("NavBar", "longSwipeUp", {
                target: "activeFrames"
            });

            if (UIStore.appWindowOpen) {
                Logger.info("NavBar", "📱 APP WINDOW OPEN - Minimizing to task switcher");
                Logger.info("NavBar", "  UIStore.appWindowOpen: " + UIStore.appWindowOpen);
                Logger.info("NavBar", "  UIStore.settingsOpen: " + UIStore.settingsOpen);

                // Use AppLifecycleManager to create task and minimize properly
                if (typeof AppLifecycleManager !== 'undefined') {
                    Logger.info("NavBar", "  🔄 Calling AppLifecycleManager.minimizeForegroundApp()");
                    var result = AppLifecycleManager.minimizeForegroundApp();
                    Logger.info("NavBar", "   AppLifecycleManager.minimizeForegroundApp() returned: " + result);
                } else {
                    Logger.error("NavBar", "   AppLifecycleManager is undefined!");
                }

                // CRITICAL: Detach app instance to background container so it stays alive for preview
                var appInstance = appWindow.detachCurrentApp();
                if (appInstance) {
                    Logger.info("NavBar", "   Detached app instance to background container");
                    appInstance.parent = backgroundAppsContainer;
                    appInstance.visible = true;
                }

                Logger.info("NavBar", "   Hiding appWindow");
                appWindow.hide();
                Logger.info("NavBar", "   Calling UIStore.minimizeApp()");
                UIStore.minimizeApp();
            } else {
                Logger.info("NavBar", "📍 No app open - just navigating to task switcher");
                Logger.info("NavBar", "  UIStore.appWindowOpen: " + UIStore.appWindowOpen);
                Logger.info("NavBar", "  UIStore.settingsOpen: " + UIStore.settingsOpen);
            }

            Logger.info("NavBar", "   Setting pageView.currentIndex = 1");
            pageView.currentIndex = 1;
            Logger.info("NavBar", "   Calling Router.goToFrames()");
            Router.goToFrames();
            Logger.info("NavBar", "━━━━━━━ LONG SWIPE UP COMPLETE ━━━━━━━");
        }

        onStartPageTransition: {
            if ((UIStore.appWindowOpen || UIStore.settingsOpen) && pageView.currentIndex !== 1) {
                pageView.currentIndex = 1;
                Router.goToFrames();
            }
        }

        onMinimizeApp: velocity => {
            Logger.info("Shell", "NavBar minimize gesture detected (velocity: " + velocity + ")");

            // Use AppLifecycleManager for proper snapshot capture and task management
            if (typeof AppLifecycleManager !== 'undefined') {
                AppLifecycleManager.minimizeForegroundApp();
            }

            shell.isTransitioningToActiveFrames = true;
            
            // Pass velocity to animation (ensure it's negative for upward movement)
            // If velocity is 0 or positive (unlikely for swipe up), use a default
            var initialVelocity = velocity < 0 ? velocity : -1000;
            snapIntoGridAnimation.startWithVelocity(initialVelocity);
        }
    }

    // Peek & Flow
    MarathonPeek {
        id: peekFlow
        anchors.fill: parent
        visible: !SessionStore.isLocked
        z: Constants.zIndexPeek

        onNotificationTapped: notification => {
            Logger.info("Shell", "Notification tapped from peek: " + notification.title);
            notificationToast.showToast(notification);
        }
    }

    // Peek gesture capture area - must be above app window to work when app is open
    // Narrow width to not block back button or other left-side content
    MouseArea {
        id: peekGestureCapture
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Constants.spacingSmall
        z: Constants.zIndexPeekGesture
        visible: !SessionStore.isLocked && !peekFlow.isFullyOpen

        property real startX: 0
        property real lastX: 0

        onPressed: mouse => {
            startX = mouse.x;
            lastX = mouse.x;
            peekFlow.startPeekGesture(mouse.x);
        }

        onPositionChanged: mouse => {
            if (pressed) {
                var absoluteX = peekGestureCapture.x + mouse.x;
                var deltaX = absoluteX - startX;
                peekFlow.updatePeekGesture(deltaX);
                lastX = absoluteX;
            }
        }

        onReleased: {
            peekFlow.endPeekGesture();
        }
    }

    // Background container for minimized apps (keeps them alive for previews)
    Item {
        id: backgroundAppsContainer
        anchors.fill: parent
        visible: true // Must be visible for ShaderEffectSource
        opacity: 0.0  // But fully transparent to user
        z: -1         // And behind everything
    }

    // App Window
    Item {
        id: appWindowContainer
        anchors.fill: parent
        anchors.margins: navBar.gestureProgress > 0 ? 8 : 0
        visible: UIStore.appWindowOpen || shell.isTransitioningToActiveFrames
        z: Constants.zIndexAppWindow

        property real finalScale: 0.65
        property real currentGestureScale: 1.0 - (navBar.gestureProgress * 0.35)
        property real currentGestureOpacity: 1.0 - (navBar.gestureProgress * 0.3)

        // Use direct binding when NOT transitioning, otherwise controlled by animation
        scale: shell.isTransitioningToActiveFrames ? scale : (navBar.gestureProgress > 0 ? currentGestureScale : 1.0)
        opacity: shell.isTransitioningToActiveFrames ? opacity : (navBar.gestureProgress > 0 ? currentGestureOpacity : 1.0)

        property bool showCardFrame: navBar.gestureProgress > 0.3 || shell.isTransitioningToActiveFrames

        // Watch for app switching (when restoring from task switcher)
        Connections {
            target: UIStore
            enabled: UIStore !== null

            function onCurrentAppIdChanged() {
                if (UIStore.appWindowOpen && UIStore.currentAppId) {
                    Logger.info("Shell", "🔄 App ID changed, showing: " + UIStore.currentAppId);

                    // Check TaskModel for app type - if native, get surface
                    var task = TaskModel.getTaskByAppId(UIStore.currentAppId);
                    if (task && task.appType === "native") {
                        Logger.info("Shell", "Restoring native app from task switcher");
                        if (compositor) {
                            var surface = compositor.getSurfaceById(task.surfaceId);
                            if (surface) {
                                // Pass surface so native app renders correctly
                                appWindow.show(UIStore.currentAppId, UIStore.currentAppName, UIStore.currentAppIcon, "native", surface, task.surfaceId);
                                return;
                            } else {
                                Logger.warn("Shell", "Native app surface not found for surfaceId: " + task.surfaceId);
                            }
                        }
                    }

                    // Default: Marathon app or native app fallback
                    appWindow.show(UIStore.currentAppId, UIStore.currentAppName, UIStore.currentAppIcon, "marathon");
                }
            }

            function onAppWindowOpenChanged() {
                // Also trigger when appWindowOpen becomes true (covers case where appId hasn't changed)
                if (UIStore.appWindowOpen && UIStore.currentAppId) {
                    Logger.info("Shell", "App window opened, showing: " + UIStore.currentAppId);

                    // Check TaskModel for app type - if native, get surface
                    var task = TaskModel.getTaskByAppId(UIStore.currentAppId);
                    if (task && task.appType === "native") {
                        Logger.info("Shell", "Restoring native app from app window open");
                        if (compositor) {
                            var surface = compositor.getSurfaceById(task.surfaceId);
                            if (surface) {
                                // Pass surface so native app renders correctly
                                appWindow.show(UIStore.currentAppId, UIStore.currentAppName, UIStore.currentAppIcon, "native", surface, task.surfaceId);
                                return;
                            } else {
                                Logger.warn("Shell", "Native app surface not found for surfaceId: " + task.surfaceId);
                            }
                        }
                    }

                    // Default: Marathon app or native app fallback
                    appWindow.show(UIStore.currentAppId, UIStore.currentAppName, UIStore.currentAppIcon, "marathon");
                }
            }
        }

        // Removed Behaviors to allow manual animation control
        
        Behavior on anchors.margins {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            id: cardBorder
            anchors.fill: parent
            color: "transparent"
            radius: Constants.borderRadiusSmall
            border.width: appWindowContainer.showCardFrame ? Constants.borderWidthThin : 0
            border.color: Qt.rgba(255, 255, 255, 0.12)
            layer.enabled: appWindowContainer.showCardFrame
            clip: true

            Behavior on border.width {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                color: "transparent"
                border.width: appWindowContainer.showCardFrame ? 1 : 0
                border.color: Qt.rgba(255, 255, 255, 0.03)

                Behavior on border.width {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }
            }

            Rectangle {
                id: appCardBackground
                anchors.fill: parent
                color: MColors.background
                radius: parent.radius
                opacity: appWindowContainer.showCardFrame ? 1.0 : 0.0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }
            }

            MarathonAppWindow {
                id: appWindow
                anchors.fill: parent
                anchors.topMargin: Constants.safeAreaTop
                anchors.bottomMargin: Constants.safeAreaBottom + virtualKeyboard.height
                visible: true

                onMinimized: {
                    Logger.info("AppWindow", "Minimized: " + appWindow.appName);
                    UIStore.minimizeApp();
                    pageView.currentIndex = 1;
                    Router.goToFrames();
                }

                onClosed: {
                    Logger.info("AppWindow", "Closed: " + appWindow.appName);
                    UIStore.closeApp();
                }
            }
        }

        Rectangle {
            id: appCardFrameOverlay
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: Constants.touchTargetSmall
            color: MColors.surface
            opacity: (navBar.gestureProgress > 0.3 || shell.isTransitioningToActiveFrames) ? (1.0 / Math.max(0.1, appWindowContainer.opacity)) : 0.0
            visible: opacity > 0
            z: 100

            Rectangle {
                width: parent.width
                height: Math.round(6 * Constants.scaleFactor)
                color: parent.color
                anchors.top: parent.top
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }

            Row {
                anchors.fill: parent
                anchors.leftMargin: Constants.spacingSmall
                anchors.rightMargin: Constants.spacingSmall
                spacing: Constants.spacingSmall

                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    source: appWindow.appIcon
                    width: Constants.iconSizeMedium
                    height: Constants.iconSizeMedium
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                    smooth: true
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Math.round(80 * Constants.scaleFactor)
                    spacing: Math.round(2 * Constants.scaleFactor)

                    Text {
                        text: appWindow.appName
                        color: MColors.textPrimary
                        font.pixelSize: MTypography.sizeSmall
                        font.weight: Font.DemiBold
                        font.family: MTypography.fontFamily
                        elide: Text.ElideRight
                        width: parent.width
                    }

                    Text {
                        text: "Running"
                        color: MColors.textSecondary
                        font.pixelSize: MTypography.sizeXSmall
                        font.family: MTypography.fontFamily
                        opacity: 0.7
                    }
                }

                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Constants.iconSizeMedium
                    height: Constants.iconSizeMedium

                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.round(28 * Constants.scaleFactor)
                        height: Math.round(28 * Constants.scaleFactor)
                        radius: Constants.borderRadiusSmall
                        color: MColors.surface

                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            color: MColors.textPrimary
                            font.pixelSize: MTypography.sizeLarge
                            font.weight: Font.Bold
                        }

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -8
                            onClicked: {
                                UIStore.closeApp();
                            }
                        }
                    }
                }
            }
        }
    }

    ParallelAnimation {
        id: snapIntoGridAnimation
        
        property real velocity: -1000
        
        function startWithVelocity(v) {
            velocity = v;
            // Calculate duration based on velocity (faster swipe = faster animation)
            // Base duration 300ms, reduced by velocity factor
            var velocityFactor = Math.min(2.0, Math.abs(v) / 1000.0);
            var duration = Math.max(150, 350 - (velocityFactor * 100));
            
            scaleAnim.duration = duration;
            opacityAnim.duration = duration;
            
            start();
        }

        NumberAnimation {
            id: scaleAnim
            target: appWindowContainer
            property: "scale"
            to: appWindowContainer.finalScale
            duration: 300
            easing.type: Easing.OutCubic
        }
        
        NumberAnimation {
            id: opacityAnim
            target: appWindowContainer
            property: "opacity"
            to: 0.0
            duration: 300
            easing.type: Easing.OutCubic
        }

        onFinished: {
            // Minimize the app window
            if (UIStore.settingsOpen) {
                UIStore.minimizeSettings();
            } else if (UIStore.appWindowOpen) {
                UIStore.minimizeApp();
            }

            // Navigate to task switcher
            if (typeof Router !== 'undefined') {
                Router.goToFrames();
            }

            shell.isTransitioningToActiveFrames = false;
        }
    }

    // Settings app now loaded dynamically like other Marathon apps

    // Quick Settings
    MarathonQuickSettings {
        id: quickSettings
        anchors.left: parent.left
        anchors.right: parent.right
        y: Constants.statusBarHeight  // Start below status bar
        height: UIStore.quickSettingsHeight  // Directly bind to drag height
        visible: !SessionStore.isLocked && UIStore.quickSettingsHeight > 0
        z: Constants.zIndexQuickSettings
        clip: true

        Behavior on height {
            enabled: !UIStore.quickSettingsDragging  // Disable animation during drag
            NumberAnimation {
                duration: Constants.animationSlow
                easing.type: Easing.OutCubic
            }
        }

        onClosed: {
            UIStore.closeQuickSettings();
        }

        onLaunchApp: app => {
            AppLaunchService.launchApp(app, compositor, appWindow);
        }
    }

    // Status Bar Drag Area
    MouseArea {
        id: statusBarDragArea
        anchors.top: parent.top
        anchors.left: parent.left
        width: parent.width
        height: Constants.statusBarHeight
        z: UIStore.settingsOpen || UIStore.appWindowOpen ? Constants.zIndexStatusBarApp + 1 : Constants.zIndexStatusBarDrag
        enabled: !SessionStore.isLocked
        preventStealing: false

        property real startY: 0
        property bool isDraggingDown: false
        property real lastY: 0
        property real lastTime: 0
        property real velocityY: 0

        onPressed: mouse => {
            if (UIStore.quickSettingsHeight > 0) {
                mouse.accepted = false;
                return;
            }
            startY = mouse.y;
            lastY = mouse.y;
            lastTime = Date.now();
            velocityY = 0;
            isDraggingDown = false;
        }

        onPositionChanged: mouse => {
            var dragDistance = mouse.y - startY;

            // Calculate velocity
            var now = Date.now();
            var dt = now - lastTime;
            if (dt > 0) {
                velocityY = (mouse.y - lastY) / dt * 1000;
            }
            lastY = mouse.y;
            lastTime = now;

            if (dragDistance > 5 && !isDraggingDown) {
                isDraggingDown = true;
                UIStore.quickSettingsDragging = true;
                Logger.gesture("StatusBar", "dragStart", {
                    y: startY
                });
            }

            if (isDraggingDown) {
                UIStore.quickSettingsHeight = Math.min(shell.maxQuickSettingsHeight, dragDistance);
            }
        }

        onReleased: mouse => {
            if (isDraggingDown) {
                UIStore.quickSettingsDragging = false;

                // Check for fling gesture (velocity > 500 px/s)
                var isFlingDown = velocityY > 500;

                if (isFlingDown || UIStore.quickSettingsHeight > shell.quickSettingsThreshold) {
                    UIStore.openQuickSettings();
                } else {
                    UIStore.closeQuickSettings();
                }
                Logger.gesture("StatusBar", "dragEnd", {
                    height: UIStore.quickSettingsHeight,
                    velocity: velocityY,
                    fling: isFlingDown
                });
            }
            startY = 0;
            lastY = 0;
            velocityY = 0;
            isDraggingDown = false;
        }

        onCanceled: {
            Logger.debug("StatusBar", "Touch canceled");
            startY = 0;
            isDraggingDown = false;
            UIStore.quickSettingsDragging = false;
            UIStore.closeQuickSettings();
        }
    }

    // Quick Settings Overlay (dimmed background behind the shade)
    MouseArea {
        id: quickSettingsOverlay
        anchors.fill: parent
        anchors.topMargin: Constants.statusBarHeight + UIStore.quickSettingsHeight
        z: Constants.zIndexQuickSettingsOverlay
        enabled: UIStore.quickSettingsHeight > 0 && !SessionStore.isLocked
        visible: enabled

        property real startY: 0
        property real lastY: 0
        property real lastTime: 0
        property real velocityY: 0

        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: parent.enabled ? 0.3 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Constants.animationFast
                }
            }
        }

        onPressed: mouse => {
            startY = mouse.y;
            lastY = mouse.y;
            lastTime = Date.now();
            velocityY = 0;
            UIStore.quickSettingsDragging = true;
            Logger.gesture("QuickSettings", "overlayDragStart", {
                y: startY
            });
        }

        onPositionChanged: mouse => {
            var dragDistance = mouse.y - startY;
            var newHeight = UIStore.quickSettingsHeight + dragDistance;
            UIStore.quickSettingsHeight = Math.max(0, Math.min(shell.maxQuickSettingsHeight, newHeight));

            // Calculate velocity
            var now = Date.now();
            var dt = now - lastTime;
            if (dt > 0) {
                velocityY = (mouse.y - lastY) / dt * 1000;
            }
            lastY = mouse.y;
            lastTime = now;

            startY = mouse.y;
        }

        onReleased: mouse => {
            UIStore.quickSettingsDragging = false;

            // Check for fling up gesture (velocity < -500 px/s = upward)
            var isFlingUp = velocityY < -500;

            if (isFlingUp || UIStore.quickSettingsHeight < shell.quickSettingsThreshold) {
                UIStore.closeQuickSettings();
            } else {
                UIStore.openQuickSettings();
            }
            startY = 0;
            lastY = 0;
            velocityY = 0;
            Logger.gesture("QuickSettings", "overlayDragEnd", {
                height: UIStore.quickSettingsHeight,
                velocity: velocityY,
                fling: isFlingUp
            });
        }

        onCanceled: {
            // Handle drag cancellation (e.g. touch/mouse leaves area)
            UIStore.quickSettingsDragging = false;
            if (UIStore.quickSettingsHeight > shell.quickSettingsThreshold) {
                UIStore.openQuickSettings();
            } else {
                UIStore.closeQuickSettings();
            }
            startY = 0;
            Logger.gesture("QuickSettings", "overlayDragCanceled", {
                height: UIStore.quickSettingsHeight
            });
        }
    }

    // Pending app launch after unlock
    property var pendingLaunch: null

    // Lock Screen
    MarathonLockScreen {
        id: lockScreen
        anchors.fill: parent
        z: Constants.zIndexLockScreen

        onUnlockRequested: {
            if (SessionStore.checkSession()) {
                // Session valid - just unlock, swipe animation already complete
                Logger.state("Shell", "locked", "unlocked");
                SessionStore.unlock();

                // Handle pending launch if any
                if (pendingLaunch) {
                    Logger.info("Shell", "Executing pending launch: " + pendingLaunch.appName);
                    UIStore.openApp(pendingLaunch.appId, pendingLaunch.appName, "");
                    pendingLaunch = null;
                }
            } else {
                // Need authentication - show PIN screen
                Logger.state("Shell", "locked", "pinEntry");
                showPinScreen = true;
                pinScreen.show();
            }
        }

        onNotificationTapped: function (notifId, appId, title) {
            Logger.info("Shell", "Lock screen notification tapped: " + title + " (id: " + notifId + ", app: " + appId + ")");

            if (SessionStore.checkSession()) {
                // Session valid - unlock and deep link immediately
                Logger.info("Shell", "Session valid, unlocking and navigating to notification");
                SessionStore.unlock();

                // Dismiss notification (clears from Marathon, NotificationModel, and DBus)
                NotificationService.dismissNotification(notifId);
                if (appId) {
                    NavigationRouter.navigateToDeepLink(appId, "", {
                        "notificationId": notifId,
                        "action": "view",
                        "from": "lockscreen"
                    });
                }
            } else {
                // Need authentication - store pending action and show PIN
                Logger.info("Shell", "Session expired, requesting PIN");
                pendingNotification = {
                    "id": notifId,
                    "appId": appId,
                    "title": title
                };
                showPinScreen = true;
                pinScreen.show();
            }
        }

        onCameraLaunched: {
            Logger.info("LockScreen", "Camera quick action tapped");

            if (SessionStore.checkSession()) {
                // Session is valid, just unlock and launch
                SessionStore.unlock();
                UIStore.openApp("camera", "Camera", "");
            } else {
                // Need PIN - enforce security!
                Logger.info("LockScreen", "Session locked - requesting PIN for Camera");
                pendingLaunch = {
                    appId: "camera",
                    appName: "Camera"
                };
                showPinScreen = true;
                pinScreen.show();
            }
            HapticService.medium();
        }

        onPhoneLaunched: {
            Logger.info("LockScreen", "Phone quick action tapped");

            if (SessionStore.checkSession()) {
                // Session is valid, just unlock and launch
                SessionStore.unlock();
                UIStore.openApp("phone", "Phone", "");
            } else {
                // Need PIN - enforce security!
                Logger.info("LockScreen", "Session locked - requesting PIN for Phone");
                pendingLaunch = {
                    appId: "phone",
                    appName: "Phone"
                };
                showPinScreen = true;
                pinScreen.show();
            }
            HapticService.medium();
        }
    }

    // PIN Entry Screen
    MarathonPinScreen {
        id: pinScreen
        anchors.fill: parent
        z: Constants.zIndexPinScreen

        onPinCorrect: {
            Logger.state("Shell", "pinEntry", "unlocked");
            showPinScreen = false;
            pinScreen.reset();
            SessionStore.unlock();  // This triggers state change to "home"

            // Handle pending launch if any
            if (pendingLaunch) {
                Logger.info("Shell", "Executing pending launch: " + pendingLaunch.appName);
                UIStore.openApp(pendingLaunch.appId, pendingLaunch.appName, "");
                pendingLaunch = null;
            }

            // Handle pending notification action
            if (pendingNotification) {
                Logger.info("Shell", "Executing pending notification action: " + pendingNotification.title);
                NotificationService.dismissNotification(pendingNotification.id);
                if (pendingNotification.appId) {
                    NavigationRouter.navigateToDeepLink(pendingNotification.appId, "", {
                        "notificationId": pendingNotification.id,
                        "action": "view",
                        "from": "lockscreen"
                    });
                }
                pendingNotification = null;  // Clear pending action
            }
        }

        onCancelled: {
            Logger.info("PinScreen", "Cancelled by user");
            showPinScreen = false;
            lockScreen.swipeProgress = 0;
            pinScreen.reset();

            // Clear pending launch
            if (pendingLaunch) {
                Logger.info("Shell", "Clearing pending launch");
                pendingLaunch = null;
            }

            // Clear pending notification action
            if (pendingNotification) {
                Logger.info("Shell", "Clearing pending notification action");
                pendingNotification = null;
            }
        }
    }

    NotificationToast {
        id: notificationToast

        Connections {
            target: NotificationService
            function onNotificationReceived(notification) {
                notificationToast.showToast(notification);
            }
        }
    }

    SystemHUD {
        id: systemHUD

        property bool initialized: false

        Connections {
            target: SystemControlStore
            function onVolumeChanged() {
                if (systemHUD.initialized) {
                    systemHUD.showVolume(SystemControlStore.volume / 100.0);
                }
            }
            function onBrightnessChanged() {
                if (systemHUD.initialized) {
                    systemHUD.showBrightness(SystemControlStore.brightness / 100.0);
                }
            }
        }

        Component.onCompleted: {
            initTimer.start();
        }

        Timer {
            id: initTimer
            interval: 500
            onTriggered: {
                systemHUD.initialized = true;
            }
        }
    }

    ConfirmDialog {
        id: confirmDialog

        Connections {
            target: UIStore
            function onShowConfirmDialog(title, message, onConfirm) {
                confirmDialog.show(title, message, onConfirm);
            }
        }
    }

    MarathonSearch {
        id: universalSearch
        anchors.fill: parent
        z: Constants.zIndexSearch
        active: UIStore.searchOpen
        pullProgress: pageView.searchPullProgress  // Bind to app grid's pull gesture

        onClosed: {
            UIStore.closeSearch();
            shell.forceActiveFocus();
        }

        onResultSelected: result => {
            // Handle different result types
            if (result.type === "app") {
                // Transform search result to app object format
                var app = {
                    id: result.data.id,
                    name: result.data.name,
                    icon: result.data.icon,
                    type: result.data.type || "marathon"
                };
                AppLaunchService.launchApp(app, compositor, appWindow);
            } else if (result.type === "deeplink") {
                // Execute deep link navigation
                UnifiedSearchService.executeSearchResult(result);
            } else if (result.type === "setting") {
                // Execute setting navigation
                UnifiedSearchService.executeSearchResult(result);
            }
            UIStore.closeSearch();
        }
    }

    ScreenshotPreview {
        id: screenshotPreview
    }

    // Wire screenshot service to preview
    Connections {
        target: ScreenshotService

        function onScreenshotCaptured(filePath, thumbnailPath) {
            Logger.info("Shell", "Screenshot captured: " + filePath);
            screenshotPreview.show(filePath, thumbnailPath);
            HapticService.medium();
        }

        function onScreenshotFailed(error) {
            Logger.error("Shell", "Screenshot failed: " + error);
        // TODO: Show error toast
        }
    }

    ShareSheet {
        id: shareSheet
    }

    AppContextMenu {
        id: appContextMenu
    }

    ClipboardManager {
        id: clipboardManager
    }

    ConnectionToast {
        id: connectionToast
    }

    // Error toast for system-wide error notifications
    ErrorToast {
        id: errorToast
    }

    // Permission dialog for app permission requests
    Comp.PermissionDialog {
        id: permissionDialog
        anchors.centerIn: parent
        z: Constants.zIndexModalOverlay + 50
    }

    // Wire network manager to connection toast
    Connections {
        target: NetworkManager

        function onWifiConnectedChanged() {
            if (NetworkManager.wifiConnected) {
                connectionToast.show("Connected to Wi-Fi", "wifi");
            } else if (NetworkManager.wifiEnabled && !NetworkManager.wifiConnected) {
                connectionToast.show("Wi-Fi disconnected", "wifi-off");
            }
        }

        function onEthernetConnectedChanged() {
            if (NetworkManager.ethernetConnected) {
                connectionToast.show("Connected to Ethernet", "plug-zap");
            } else if (!NetworkManager.ethernetConnected && !NetworkManager.wifiConnected) {
                connectionToast.show("No network connection", "wifi-off");
            }
        }
    }

    Connections {
        target: typeof PowerManager !== 'undefined' ? PowerManager : null

        function onBatteryLevelChanged() {
            PowerBatteryHandler.errorToast = errorToast;
            PowerBatteryHandler.shutdownCallback = function () {
                criticalBatteryShutdownTimer.start();
            };
            PowerBatteryHandler.shutdownStopCallback = function () {
                criticalBatteryShutdownTimer.stop();
            };
            PowerBatteryHandler.handleBatteryLevelChanged();
        }
    }

    Timer {
        id: criticalBatteryShutdownTimer
        interval: 10000
        repeat: false
        onTriggered: {
            Logger.critical("Battery", "Emergency shutdown due to critical battery");
            if (typeof PowerManager !== 'undefined' && PowerManager) {
                PowerManager.shutdown();
            }
        }
    }

    Timer {
        id: bluetoothReconnectTimer
        interval: 5000
        repeat: false
        onTriggered: {
            if (typeof BluetoothManagerCpp !== 'undefined' && BluetoothManagerCpp.enabled) {
                Logger.info("Shell", "Attempting Bluetooth auto-reconnect...");

                var pairedDevices = BluetoothManagerCpp.pairedDevices;

                if (pairedDevices && pairedDevices.length > 0) {
                    Logger.info("Shell", "Found " + pairedDevices.length + " paired devices, attempting reconnect");

                    for (var i = 0; i < pairedDevices.length; i++) {
                        var device = pairedDevices[i];

                        if (!device.connected) {
                            Logger.info("Shell", "Reconnecting to: " + device.name + " (" + device.address + ")");
                            BluetoothManagerCpp.connectDevice(device.address);
                        } else {
                            Logger.info("Shell", "Device already connected: " + device.name);
                        }
                    }
                } else {
                    Logger.info("Shell", "No paired Bluetooth devices found");
                }
            }
        }
    }

    MarathonAlarmOverlay {
        id: alarmOverlay
    }

    // Out-of-Box Experience (OOBE) - First-run setup
    MarathonOOBE {
        id: oobeWizard
        onSetupComplete: {
            Logger.info("Shell", "OOBE setup completed");
        }
    }

    // Wire alarm manager to overlay
    Connections {
        target: typeof AlarmManager !== 'undefined' ? AlarmManager : null

        function onAlarmTriggered(alarm) {
            Logger.info("Shell", "Alarm triggered: " + alarm.title);
            alarmOverlay.show(alarm);
            HapticService.heavy();
        }
    }

    VirtualKeyboard {
        id: virtualKeyboard
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
    }

    // Auto-show keyboard when text input is focused (if no hardware keyboard)
    Connections {
        target: Qt.inputMethod

        function onVisibleChanged() {
            // Only auto-show if no hardware keyboard is detected
            if (typeof Platform !== 'undefined' && !Platform.hasHardwareKeyboard) {
                if (Qt.inputMethod.visible && !virtualKeyboard.active) {
                    Logger.info("Shell", "Text input focused - auto-showing virtual keyboard");
                    virtualKeyboard.active = true;
                } else if (!Qt.inputMethod.visible && virtualKeyboard.active) {
                    // Don't auto-hide - let user dismiss manually or by clicking outside
                    // This prevents keyboard from hiding when cycling between inputs
                    Logger.debug("Shell", "Text input unfocused - keeping keyboard visible");
                }
            }
        }
    }

    // Auto-dismiss keyboard when clicking above it (user request)
    MouseArea {
        id: keyboardDismissArea
        anchors.fill: parent
        anchors.bottomMargin: virtualKeyboard.height
        z: Constants.zIndexKeyboard - 1
        visible: virtualKeyboard.active
        enabled: virtualKeyboard.active

        onClicked: {
            Logger.info("Shell", "Click outside keyboard - auto-dismissing");
            HapticService.light();
            virtualKeyboard.active = false;
        }

        // Don't propagate to items below
        propagateComposedEvents: false
    }

    // Keyboard visibility managed by: 1) Auto-show on input focus (no hardware KB), 2) Manual nav bar toggle

    // Power button press timer for long-press detection
    Timer {
        id: powerButtonTimer
        interval: 800  // 800ms for long press
        onTriggered: {
            Logger.info("Shell", "Power button LONG PRESS detected - showing power menu");
            powerMenu.show();
        }
    }

    // Track volume up state for screenshot combo
    property bool volumeUpPressed: false
    property bool powerButtonPressed: false

    Keys.onPressed: event => {
        // Volume Up button
        if (event.key === Qt.Key_VolumeUp) {
            volumeUpPressed = true;

            // Check for Power + Volume Up combo (screenshot)
            if (powerButtonPressed) {
                Logger.info("Shell", "Power + Volume Up combo - Taking Screenshot");
                screenshotFlash.trigger();
                ScreenshotService.captureScreen(shell);
                event.accepted = true;
                return;
            }

            SystemControlStore.setVolume(SystemControlStore.volume + 10);
            systemHUD.showVolume(AudioManagerCpp.volume);
            event.accepted = true;
            return;
        }

        // Volume Down button
        if (event.key === Qt.Key_VolumeDown) {
            SystemControlStore.setVolume(SystemControlStore.volume - 10);
            systemHUD.showVolume(AudioManagerCpp.volume);
            event.accepted = true;
            return;
        }

        // Power button - start timer for long press
        if (event.key === Qt.Key_PowerOff || event.key === Qt.Key_Sleep || event.key === Qt.Key_Suspend) {
            powerButtonPressed = true;

            // Check for Power + Volume Up combo (screenshot)
            if (volumeUpPressed) {
                Logger.info("Shell", "Power + Volume Up combo - Taking Screenshot");
                screenshotFlash.trigger();
                ScreenshotService.captureScreen(shell);
                event.accepted = true;
                return;
            }

            if (!powerButtonTimer.running) {
                powerButtonTimer.start();
            }
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
            Logger.debug("Shell", "Escape key pressed");
            if (showPinScreen) {
                showPinScreen = false;
                lockScreen.swipeProgress = 0;
                pinScreen.reset();
            } else if (UIStore.searchOpen) {
                UIStore.closeSearch();
            } else if (UIStore.shareSheetOpen) {
                UIStore.closeShareSheet();
            } else if (UIStore.clipboardManagerOpen) {
                UIStore.closeClipboardManager();
            } else if (peekFlow.peekProgress > 0) {
                peekFlow.closePeek();
            } else if (UIStore.quickSettingsOpen) {
                UIStore.closeQuickSettings();
            } else if (messagingHub.showVertical) {
                messagingHub.showVertical = false;
            }
        } else if ((event.key === Qt.Key_Space) && (event.modifiers & Qt.ControlModifier)) {
            Logger.debug("Shell", "Cmd+Space pressed - Opening Universal Search");
            UIStore.toggleSearch();
            HapticService.light();
            event.accepted = true;
        } else if ((event.key === Qt.Key_K) && (event.modifiers & Qt.ControlModifier)) {
            Logger.debug("Shell", "Cmd+K pressed - Toggling Virtual Keyboard");
            virtualKeyboard.active = !virtualKeyboard.active;
            HapticService.light();
            event.accepted = true;
        } else if (event.key === Qt.Key_Menu) {
            Logger.debug("Shell", "Menu key pressed - Toggling Virtual Keyboard");
            virtualKeyboard.active = !virtualKeyboard.active;
            HapticService.light();
            event.accepted = true;
        } else if (event.key === Qt.Key_Print || event.key === Qt.Key_SysReq) {
            // Print Screen key (standard on Linux/Windows)
            Logger.debug("Shell", "Print Screen pressed - Taking Screenshot");
            screenshotFlash.trigger();
            ScreenshotService.captureScreen(shell);
            HapticService.medium();
            event.accepted = true;
        } else if ((event.key === Qt.Key_3) && (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier)) {
            // Ctrl+Shift+3 (Cmd+Shift+3 on macOS) - macOS-style shortcut
            Logger.debug("Shell", "Ctrl+Shift+3 pressed - Taking Screenshot");
            screenshotFlash.trigger();
            ScreenshotService.captureScreen(shell);
            HapticService.medium();
            event.accepted = true;
        } else if ((event.key === Qt.Key_V) && (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier)) {
            Logger.debug("Shell", "Cmd+Shift+V pressed - Opening Clipboard Manager");
            UIStore.openClipboardManager();
            HapticService.light();
            event.accepted = true;
        } else if (shell.state === "home" && !UIStore.searchOpen && !UIStore.appWindowOpen) {
            // Alphanumeric keys trigger search with that character
            if (event.text.length > 0 && event.text.match(/[a-zA-Z0-9]/)) {
                Logger.info("Shell", "Global search triggered with: '" + event.text + "'");
                UIStore.openSearch();
                Qt.callLater(function () {
                    universalSearch.appendToSearch(event.text);
                });
                event.accepted = true;
            }
        }
    }

    Comp.CompositorConnections {
        id: compositorConnections
    }

    // NOTE: Compositor signal connections are made manually in Component.onCompleted
    // because the compositor property is null when this file is first loaded

    Keys.onReleased: event => {
        // Reset volume up state
        if (event.key === Qt.Key_VolumeUp) {
            volumeUpPressed = false;
            event.accepted = true;
        }

        if (event.key === Qt.Key_PowerOff || event.key === Qt.Key_Sleep || event.key === Qt.Key_Suspend) {
            powerButtonPressed = false;

            if (powerButtonTimer.running) {
                PowerBatteryHandler.handlePowerButtonPress();
                powerButtonTimer.stop();
            }
            event.accepted = true;
        }
    }

    PowerMenu {
        id: powerMenu

        onSleepRequested: {
            Logger.info("Shell", "Sleep requested from power menu");
            SessionStore.lock();  // Lock first
            PowerManager.sleep();  // Then sleep
        }

        onRebootRequested: {
            Logger.info("Shell", "Reboot requested from power menu");
            PowerManager.restart();
        }

        onShutdownRequested: {
            Logger.info("Shell", "Shutdown requested from power menu");
            PowerManager.shutdown();
        }
    }

    // Screenshot flash overlay
    Rectangle {
        id: screenshotFlash
        anchors.fill: parent
        color: "white"
        opacity: 0
        z: Constants.zIndexModalOverlay + 200  // Above everything

        function trigger() {
            flashAnimation.restart();
        }

        SequentialAnimation {
            id: flashAnimation

            NumberAnimation {
                target: screenshotFlash
                property: "opacity"
                from: 0
                to: 0.9
                duration: 100
                easing.type: Easing.OutQuad
            }

            NumberAnimation {
                target: screenshotFlash
                property: "opacity"
                from: 0.9
                to: 0
                duration: 200
                easing.type: Easing.InQuad
            }
        }
    }

    Loader {
        id: incomingCallOverlayLoader
        anchors.fill: parent
        z: Constants.zIndexModalOverlay + 100
        active: false
        source: "qrc:/MarathonOS/Shell/qml/components/IncomingCallOverlay.qml"
    }

    Connections {
        target: incomingCallOverlayLoader.item
        enabled: incomingCallOverlayLoader.item !== null
        function onAnswered() {
            TelephonyIntegration.callWasAnswered = true;
        }
        function onDeclined() {
            TelephonyIntegration.callWasAnswered = false;
        }
    }

    Connections {
        target: typeof TelephonyService !== 'undefined' ? TelephonyService : null

        function onIncomingCall(number) {
            incomingCallOverlayLoader.active = true;
            TelephonyIntegration.incomingCallOverlay = incomingCallOverlayLoader.item;
            TelephonyIntegration.handleIncomingCall(number);
        }

        function onCallStateChanged(state) {
            TelephonyIntegration.handleCallStateChanged(state);
            if ((state === "active" || state === "idle" || state === "terminated") && incomingCallOverlayLoader.item && incomingCallOverlayLoader.item.visible) {
                incomingCallOverlayLoader.item.hide();
                incomingCallOverlayLoader.active = false;
            }
        }
    }

    Connections {
        target: typeof SMSService !== 'undefined' ? SMSService : null

        function onMessageReceived(sender, text, timestamp) {
            TelephonyIntegration.handleMessageReceived(sender, text, timestamp);
        }
    }

    // Public function to show power menu (used by Quick Settings)
    function showPowerMenu() {
        Logger.info("Shell", "Showing power menu from quick settings");
        powerMenu.show();
    }
    // Global Mouse Trap for "Blind" Trackpad Scrolling
    // Since there is no visible cursor, we capture all mouse movement and
    // route it to the currently focused scrollable item.
    MouseArea {
        anchors.fill: parent
        z: 99999 // Topmost
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons // Capture everything to be safe
        propagateComposedEvents: true // Let clicks pass through if needed
        
        property real lastY: 0
        
        onEntered: {
            lastY = mouseY
            Logger.info("Input", "Global Trap: Mouse entered at " + mouseY);
        }

        onPositionChanged: (mouse) => {
            var delta = mouse.y - lastY
            lastY = mouse.y
            
            if (Math.abs(delta) > 0) {
                // Find focused item
                var focusedItem = Window.activeFocusItem
                
                // Check if it (or its parent) is scrollable
                // We traverse up a few levels to find the MScrollView
                var scrollTarget = null
                var candidate = focusedItem
                
                // Search up the tree (max 5 levels)
                for (var i = 0; i < 5; i++) {
                    if (candidate && candidate.isScrollable) {
                        scrollTarget = candidate
                        break
                    }
                    if (candidate && candidate.parent) {
                        candidate = candidate.parent
                    } else {
                        break
                    }
                }
                
                if (scrollTarget) {
                    scrollTarget.scrollBy(-delta)
                } else {
                    // Debug: Log if no scroll target found
                    // Logger.debug("Input", "Global Trap: No scroll target found for focus: " + focusedItem);
                }
            }
        }
        
        onPressed: (mouse) => {
             Logger.info("Input", "Global Trap: Pressed at " + mouse.x + "," + mouse.y);
             mouse.accepted = false; // Let it pass through to clicks
        }
    }
}
