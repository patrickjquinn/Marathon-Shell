import "./components" as Comp
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtQuick.Window

Item {
    id: shell

    property var compositor: null
    property alias appWindowContainer: appWindowContainer
    property bool showPinScreen: false
    property bool isTransitioningToActiveFrames: false
    property int currentPage: 0
    property int totalPages: 1
    property var pendingNotification: null
    readonly property real maxQuickSettingsHeight: shell.height - Constants.statusBarHeight
    readonly property real quickSettingsThreshold: maxQuickSettingsHeight * Constants.quickSettingsDismissThreshold
    property var pendingLaunch: null
    property bool volumeUpPressed: false
    property bool powerButtonPressed: false

    function handleBackKey() {
        var overlayClosed = false;
        if (showPinScreen) {
            showPinScreen = false;
            lockScreen.swipeProgress = 0;
            pinScreen.reset();
            overlayClosed = true;
        } else if (UIStore.searchOpen) {
            UIStore.closeSearch();
            overlayClosed = true;
        } else if (UIStore.shareSheetOpen) {
            UIStore.closeShareSheet();
            overlayClosed = true;
        } else if (UIStore.clipboardManagerOpen) {
            UIStore.closeClipboardManager();
            overlayClosed = true;
        } else if (peekFlow.peekProgress > 0) {
            peekFlow.closePeek();
            overlayClosed = true;
        } else if (UIStore.quickSettingsOpen) {
            UIStore.closeQuickSettings();
            overlayClosed = true;
        } else if (messagingHub.showVertical) {
            messagingHub.showVertical = false;
            overlayClosed = true;
        }
        if (overlayClosed) {
            Logger.info("Shell", "Back Key closed overlay");
            return;
        }
        Logger.info("Shell", "Back Key Triggered - Calling handleSystemBack");
        if (typeof AppLifecycleManager !== 'undefined') {
            var handled = AppLifecycleManager.handleSystemBack();
            if (!handled) {
                Logger.info("Shell", "Back not handled by app, closing");
                if (UIStore.appWindowOpen)
                    UIStore.closeApp();
            }
        } else if (UIStore.appWindowOpen) {
            UIStore.closeApp();
        }
    }

    function handleHomeKey() {
        if (virtualKeyboard.active) {
            HapticService.light();
            virtualKeyboard.active = false;
            return;
        }
        if (UIStore.appWindowOpen) {
            if (typeof AppLifecycleManager !== 'undefined')
                AppLifecycleManager.minimizeForegroundApp();

            var appInstance = appWindow.detachCurrentApp();
            if (appInstance) {
                if (appInstance.isMinimized !== undefined)
                    appInstance.isMinimized = true;

                appInstance.parent = backgroundAppsContainer;
                appInstance.visible = true;
            }
            appWindow.hide();
            UIStore.minimizeApp();
        }
        pageView.currentIndex = 1;
        Router.goToFrames();
    }

    function showPowerMenu() {
        Logger.info("Shell", "Showing power menu from quick settings");
        powerMenu.show();
    }

    focus: true
    Keys.onReleased: event => {
        if (event.key === Qt.Key_VolumeUp) {
            volumeUpPressed = false;
            event.accepted = true;
        } else if (event.key === Qt.Key_PowerOff || event.key === Qt.Key_Sleep || event.key === Qt.Key_Suspend) {
            powerButtonPressed = false;
            if (powerButtonTimer.running) {
                PowerBatteryHandler.handlePowerButtonPress();
                powerButtonTimer.stop();
            }
            event.accepted = true;
        }
    }
    Component.onCompleted: {
        shell.forceActiveFocus();
        compositor = shellInitialization.initialize(shell, Window.window);
        AppLaunchService.compositor = compositor;
        AppLaunchService.appWindow = appWindow;
        AppLaunchService.uiStore = UIStore;
        AppLaunchService.appLifecycleManager = AppLifecycleManager;
        ScreenshotService.shellWindow = shell;
        if (compositor) {
            compositor.systemBackTriggered.connect(handleBackKey);
            compositor.systemHomeTriggered.connect(handleHomeKey);
        }
    }
    onWidthChanged: {
        if (Constants.screenWidth > 0)
            resizeDebounceTimer.restart();
    }
    onHeightChanged: {
        if (Constants.screenHeight > 0)
            resizeDebounceTimer.restart();
    }
    state: SettingsManagerCpp.firstRunComplete ? (SessionStore.showLockScreen ? (showPinScreen ? "pinEntry" : "locked") : (UIStore.appWindowOpen ? "app" : "home")) : "home"
    Keys.onPressed: event => {
        if (event.key === Qt.Key_VolumeUp) {
            volumeUpPressed = true;
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
        if (event.key === Qt.Key_VolumeDown) {
            SystemControlStore.setVolume(SystemControlStore.volume - 10);
            systemHUD.showVolume(AudioManagerCpp.volume);
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_PowerOff || event.key === Qt.Key_Sleep || event.key === Qt.Key_Suspend) {
            powerButtonPressed = true;
            if (volumeUpPressed) {
                Logger.info("Shell", "Power + Volume Up combo - Taking Screenshot");
                screenshotFlash.trigger();
                ScreenshotService.captureScreen(shell);
                event.accepted = true;
                return;
            }
            if (!powerButtonTimer.running)
                powerButtonTimer.start();

            event.accepted = true;
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
            Logger.debug("Shell", "Print Screen pressed - Taking Screenshot");
            screenshotFlash.trigger();
            ScreenshotService.captureScreen(shell);
            HapticService.medium();
            event.accepted = true;
        } else if ((event.key === Qt.Key_3) && (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier)) {
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
    states: [
        State {
            name: "locked"

            PropertyChanges {
                lockScreen.visible: true
                lockScreen.enabled: true
                lockScreen.expandedCategory: ""
            }

            StateChangeScript {
                script: {
                    lockScreen.swipeProgress = 0;
                }
            }

            PropertyChanges {
                pinScreen.visible: false
                pinScreen.enabled: false
                pinScreen.opacity: 0
            }

            PropertyChanges {
                mainContent.visible: SessionStore.checkSession()
                mainContent.enabled: false
                mainContent.opacity: SessionStore.checkSession() ? Math.pow(lockScreen.swipeProgress, 0.7) : 0
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
                pinScreen.opacity: 1
            }

            PropertyChanges {
                mainContent.visible: false
                mainContent.enabled: false
                mainContent.opacity: 0
            }

            PropertyChanges {
                appWindow.visible: false
            }

            PropertyChanges {
                navBar.visible: true
                navBar.pinScreenMode: true
            }
        },
        State {
            name: "home"

            StateChangeScript {
                script: {
                    shell.forceActiveFocus();
                }
            }

            PropertyChanges {
                lockScreen.visible: false
                lockScreen.enabled: false
            }

            PropertyChanges {
                pinScreen.visible: false
                pinScreen.enabled: false
                pinScreen.opacity: 0
            }

            PropertyChanges {
                mainContent.visible: true
                mainContent.enabled: true
                mainContent.opacity: 1
            }

            PropertyChanges {
                appWindow.visible: false
            }

            PropertyChanges {
                navBar.visible: true
                navBar.pinScreenMode: false
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
                navBar.pinScreenMode: false
            }
        }
    ]
    transitions: [
        Transition {
            from: "locked"
            to: "home"

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
                    to: 1
                    duration: 200
                    easing.type: Easing.OutCubic
                }

                NumberAnimation {
                    target: pinScreen
                    property: "opacity"
                    to: 1
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

    MouseArea {
        id: cursorTracker

        anchors.fill: parent
        z: 10000
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        enabled: true
        focus: false
        onPositionChanged: mouse => {
            if (typeof CursorManager !== 'undefined')
                CursorManager.onMouseActivity();

            mouse.accepted = false;
        }
        onPressed: mouse => {
            mouse.accepted = false;
        }
        onReleased: mouse => {
            mouse.accepted = false;
        }
        onClicked: mouse => {
            mouse.accepted = false;
        }
    }

    Timer {
        id: resizeDebounceTimer

        interval: 100
        onTriggered: {
            Constants.updateScreenSize(shell.width, shell.height, Screen.pixelDensity * 25.4);
        }
    }

    Connections {
        function onDeepLinkRequested(appId, route, params) {
            var appInfo = typeof MarathonAppRegistry !== "undefined" ? MarathonAppRegistry.getApp(appId) : null;
            if (appInfo && appInfo.id) {
                UIStore.openApp(appInfo.id, appInfo.name, appInfo.icon);
                if (appWindow)
                    appWindow.show(appInfo.id, appInfo.name, appInfo.icon, appInfo.type);

                if (typeof AppLifecycleManager !== "undefined")
                    AppLifecycleManager.bringToForeground(appInfo.id);
            } else {
                Logger.warn("Shell", "App not found for deep link: " + appId);
            }
        }

        target: NavigationRouter
    }

    Connections {
        function onNotificationClicked(id) {
            NotificationHandler.handleNotificationClick(id);
        }

        function onNotificationActionTriggered(id, action) {
            NotificationHandler.handleNotificationAction(id, action);
        }

        target: NotificationService
    }

    Comp.ShellInitialization {
        id: shellInitialization
    }

    Image {
        anchors.fill: parent
        source: WallpaperStore.path
        fillMode: Image.PreserveAspectCrop
        z: Constants.zIndexBackground
    }

    Column {
        id: mainContent

        anchors.fill: parent
        z: Constants.zIndexMainContent

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
                compositor: shell.compositor
                onCurrentPageChanged: {
                    Logger.nav("page" + shell.currentPage, "page" + currentPage, "navigation");
                    if (currentPage >= 0) {
                        shell.currentPage = pageView.internalAppGridPage;
                        shell.totalPages = Math.max(1, Math.ceil(AppModel.count / 16));
                    } else {
                        shell.currentPage = currentPage;
                    }
                }
                onInternalAppGridPageChanged: {
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
        anchors.bottom: parent.bottom
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
            if (UIStore.appWindowOpen || UIStore.settingsOpen)
                return;

            if (pageView.currentIndex < pageView.count - 1) {
                pageView.incrementCurrentIndex();
                Router.navigateLeft();
            }
        }
        onSwipeRight: {
            if (UIStore.appWindowOpen && typeof AppLifecycleManager !== 'undefined') {
                var handled = AppLifecycleManager.handleSystemForward();
                if (handled)
                    return;
            }
            if (UIStore.appWindowOpen || UIStore.settingsOpen)
                return;

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
                    if (UIStore.appWindowOpen)
                        UIStore.closeApp();
                }
            } else {
                Logger.info("NavBar", "AppLifecycleManager unavailable, closing directly");
                if (UIStore.appWindowOpen)
                    UIStore.closeApp();
            }
        }
        onShortSwipeUp: {
            if (virtualKeyboard.active) {
                Logger.info("NavBar", "Dismissing keyboard with short swipe up");
                HapticService.light();
                virtualKeyboard.active = false;
                return;
            }
            Logger.gesture("NavBar", "shortSwipeUp", {
                "target": "home"
            });
            pageView.currentIndex = 2;
            Router.goToAppPage(0);
        }
        onLongSwipeUp: {
            Logger.info("NavBar", "━━━━━━━ LONG SWIPE UP RECEIVED ━━━━━━━");
            if (virtualKeyboard.active) {
                Logger.info("NavBar", "Dismissing keyboard with long swipe up");
                HapticService.light();
                virtualKeyboard.active = false;
                return;
            }
            Logger.gesture("NavBar", "longSwipeUp", {
                "target": "activeFrames"
            });
            if (UIStore.appWindowOpen) {
                Logger.info("NavBar", "📱 APP WINDOW OPEN - Minimizing to task switcher");
                Logger.info("NavBar", "  UIStore.appWindowOpen: " + UIStore.appWindowOpen);
                Logger.info("NavBar", "  UIStore.settingsOpen: " + UIStore.settingsOpen);
                if (typeof AppLifecycleManager !== 'undefined') {
                    Logger.info("NavBar", "  🔄 Calling AppLifecycleManager.minimizeForegroundApp()");
                    var result = AppLifecycleManager.minimizeForegroundApp();
                    Logger.info("NavBar", "   AppLifecycleManager.minimizeForegroundApp() returned: " + result);
                } else {
                    Logger.error("NavBar", "   AppLifecycleManager is undefined!");
                }
                Logger.info("NavBar", "   Triggering snapIntoGridAnimation for smooth transition");
                shell.isTransitioningToActiveFrames = true;
                snapIntoGridAnimation.startWithVelocity(-1500);
            } else {
                Logger.info("NavBar", "📍 No app open - just navigating to task switcher");
                pageView.currentIndex = 1;
                Router.goToFrames();
            }
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
            if (typeof AppLifecycleManager !== 'undefined')
                AppLifecycleManager.minimizeForegroundApp();

            shell.isTransitioningToActiveFrames = true;
            var initialVelocity = velocity < 0 ? velocity : -1000;
            snapIntoGridAnimation.startWithVelocity(initialVelocity);
        }
    }

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

    MouseArea {
        id: peekGestureCapture

        property real startX: 0
        property real lastX: 0

        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Constants.spacingSmall
        z: Constants.zIndexPeekGesture
        visible: !SessionStore.isLocked && !peekFlow.isFullyOpen
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

    Item {
        id: backgroundAppsContainer

        anchors.fill: parent
        visible: true
        opacity: 0
        z: -1
    }

    Item {
        id: appWindowContainer

        property real finalScale: 0.65
        property real currentGestureScale: 1 - (navBar.gestureProgress * 0.35)
        property real currentGestureOpacity: 1 - (navBar.gestureProgress * 0.3)
        property bool showCardFrame: navBar.gestureProgress > 0.3 || shell.isTransitioningToActiveFrames

        anchors.fill: parent
        anchors.margins: navBar.gestureProgress > 0 ? 8 : 0
        visible: UIStore.appWindowOpen || shell.isTransitioningToActiveFrames
        z: Constants.zIndexAppWindow
        scale: shell.isTransitioningToActiveFrames ? scale : (navBar.gestureProgress > 0 ? currentGestureScale : 1)
        opacity: shell.isTransitioningToActiveFrames ? opacity : (navBar.gestureProgress > 0 ? currentGestureOpacity : 1)

        Connections {
            function onCurrentAppIdChanged() {
                if (UIStore.appWindowOpen && UIStore.currentAppId) {
                    if (AppLaunchService.isAppLaunching(UIStore.currentAppId)) {
                        Logger.info("Shell", "AppLaunchService is launching " + UIStore.currentAppId + " - skipping redundant show()");
                        return;
                    }
                    Logger.info("Shell", "🔄 App ID changed, showing: " + UIStore.currentAppId);
                    var task = TaskModel.getTaskByAppId(UIStore.currentAppId);
                    if (task && task.appType === "native") {
                        Logger.info("Shell", "Restoring native app from task switcher");
                        if (compositor) {
                            var surface = compositor.getSurfaceById(task.surfaceId);
                            if (surface) {
                                appWindow.show(UIStore.currentAppId, UIStore.currentAppName, UIStore.currentAppIcon, "native", surface, task.surfaceId);
                                return;
                            } else {
                                Logger.warn("Shell", "Native app surface not found for surfaceId: " + task.surfaceId);
                                for (var i = 0; i < backgroundAppsContainer.children.length; i++) {
                                    var child = backgroundAppsContainer.children[i];
                                    if (child.appId === UIStore.currentAppId) {
                                        Logger.info("Shell", "Found detached native app instance in background, re-attaching: " + UIStore.currentAppId);
                                        appWindow.reattachInstance(child, UIStore.currentAppId, UIStore.currentAppName, UIStore.currentAppIcon, "native");
                                        return;
                                    }
                                }
                                Logger.warn("Shell", "No detached instance found in backgroundAppsContainer for: " + UIStore.currentAppId);
                            }
                        }
                    }
                    AppLaunchService.launchApp(UIStore.currentAppId, compositor, appWindow);
                }
            }

            function onAppWindowOpenChanged() {
                if (UIStore.appWindowOpen && UIStore.currentAppId) {
                    if (AppLaunchService.isAppLaunching(UIStore.currentAppId)) {
                        Logger.info("Shell", "AppLaunchService is launching " + UIStore.currentAppId + " - skipping redundant show()");
                        return;
                    }
                    Logger.info("Shell", "App window opened, showing: " + UIStore.currentAppId);
                    var task = TaskModel.getTaskByAppId(UIStore.currentAppId);
                    if (task && task.appType === "native") {
                        Logger.info("Shell", "Restoring native app from app window open");
                        if (compositor) {
                            var surface = compositor.getSurfaceById(task.surfaceId);
                            if (surface) {
                                appWindow.show(UIStore.currentAppId, UIStore.currentAppName, UIStore.currentAppIcon, "native", surface, task.surfaceId);
                                return;
                            } else {
                                Logger.warn("Shell", "Native app surface not found for surfaceId: " + task.surfaceId);
                                for (var i = 0; i < backgroundAppsContainer.children.length; i++) {
                                    var child = backgroundAppsContainer.children[i];
                                    if (child.appId === UIStore.currentAppId) {
                                        Logger.info("Shell", "Found detached native app instance in background, re-attaching: " + UIStore.currentAppId);
                                        appWindow.reattachInstance(child, UIStore.currentAppId, UIStore.currentAppName, UIStore.currentAppIcon, "native");
                                        return;
                                    }
                                }
                                Logger.warn("Shell", "No detached instance found in backgroundAppsContainer for: " + UIStore.currentAppId);
                            }
                        }
                    }
                    AppLaunchService.launchApp(UIStore.currentAppId, compositor, appWindow);
                }
            }

            target: UIStore
            enabled: UIStore !== null
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
                opacity: appWindowContainer.showCardFrame ? 1 : 0

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

            Behavior on border.width {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
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
            opacity: (navBar.gestureProgress > 0.3 || shell.isTransitioningToActiveFrames) ? (1 / Math.max(0.1, appWindowContainer.opacity)) : 0
            visible: opacity > 0
            z: 100

            Rectangle {
                width: parent.width
                height: Math.round(6 * Constants.scaleFactor)
                color: parent.color
                anchors.top: parent.top
            }

            Row {
                anchors.fill: parent
                anchors.leftMargin: Constants.spacingSmall
                anchors.rightMargin: Constants.spacingSmall
                spacing: Constants.spacingSmall

                MAppIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    source: appWindow.appIcon
                    size: Constants.iconSizeMedium
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

            Behavior on opacity {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }
        }

        Behavior on anchors.margins {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutCubic
            }
        }
    }

    ParallelAnimation {
        id: snapIntoGridAnimation

        property real velocity: -1000

        function startWithVelocity(v) {
            velocity = v;
            var velocityFactor = Math.min(2, Math.abs(v) / 1000);
            var duration = Math.max(150, 350 - (velocityFactor * 100));
            scaleAnim.duration = duration;
            opacityAnim.duration = duration;
            if (typeof Router !== 'undefined')
                Router.goToFrames();

            start();
        }

        onFinished: {
            var appInstance = appWindow.detachCurrentApp();
            if (appInstance) {
                appInstance.parent = backgroundAppsContainer;
                appInstance.visible = true;
            }
            if (UIStore.settingsOpen)
                UIStore.minimizeSettings();
            else if (UIStore.appWindowOpen)
                UIStore.minimizeApp();
            shell.isTransitioningToActiveFrames = false;
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
            to: 1
            duration: 300
            easing.type: Easing.OutCubic
        }
    }

    MarathonQuickSettings {
        id: quickSettings

        anchors.left: parent.left
        anchors.right: parent.right
        y: Constants.statusBarHeight
        height: UIStore.quickSettingsHeight
        visible: !SessionStore.isLocked && UIStore.quickSettingsHeight > 0
        z: Constants.zIndexQuickSettings
        clip: true
        onClosed: {
            UIStore.closeQuickSettings();
        }
        onLaunchApp: app => {
            AppLaunchService.launchApp(app, compositor, appWindow);
        }

        Behavior on height {
            enabled: !UIStore.quickSettingsDragging

            NumberAnimation {
                duration: Constants.animationSlow
                easing.type: Easing.OutCubic
            }
        }
    }

    MouseArea {
        id: statusBarDragArea

        property real startY: 0
        property bool isDraggingDown: false
        property real lastY: 0
        property real lastTime: 0
        property real velocityY: 0

        anchors.top: parent.top
        anchors.left: parent.left
        width: parent.width
        height: Constants.statusBarHeight
        z: UIStore.settingsOpen || UIStore.appWindowOpen ? Constants.zIndexStatusBarApp + 1 : Constants.zIndexStatusBarDrag
        enabled: !SessionStore.isLocked
        preventStealing: false
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
            var now = Date.now();
            var dt = now - lastTime;
            if (dt > 0)
                velocityY = (mouse.y - lastY) / dt * 1000;

            lastY = mouse.y;
            lastTime = now;
            if (dragDistance > 5 && !isDraggingDown) {
                isDraggingDown = true;
                UIStore.quickSettingsDragging = true;
                Logger.gesture("StatusBar", "dragStart", {
                    "y": startY
                });
            }
            if (isDraggingDown)
                UIStore.quickSettingsHeight = Math.min(shell.maxQuickSettingsHeight, dragDistance);
        }
        onReleased: mouse => {
            if (isDraggingDown) {
                UIStore.quickSettingsDragging = false;
                var isFlingDown = velocityY > 500;
                if (isFlingDown || UIStore.quickSettingsHeight > shell.quickSettingsThreshold)
                    UIStore.openQuickSettings();
                else
                    UIStore.closeQuickSettings();
                Logger.gesture("StatusBar", "dragEnd", {
                    "height": UIStore.quickSettingsHeight,
                    "velocity": velocityY,
                    "fling": isFlingDown
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

    MouseArea {
        id: quickSettingsOverlay

        property real startY: 0
        property real lastY: 0
        property real lastTime: 0
        property real velocityY: 0

        anchors.fill: parent
        anchors.topMargin: Constants.statusBarHeight + UIStore.quickSettingsHeight
        z: Constants.zIndexQuickSettingsOverlay
        enabled: UIStore.quickSettingsHeight > 0 && !SessionStore.isLocked
        visible: enabled
        onPressed: mouse => {
            startY = mouse.y;
            lastY = mouse.y;
            lastTime = Date.now();
            velocityY = 0;
            UIStore.quickSettingsDragging = true;
            Logger.gesture("QuickSettings", "overlayDragStart", {
                "y": startY
            });
        }
        onPositionChanged: mouse => {
            var dragDistance = mouse.y - startY;
            var newHeight = UIStore.quickSettingsHeight + dragDistance;
            UIStore.quickSettingsHeight = Math.max(0, Math.min(shell.maxQuickSettingsHeight, newHeight));
            var now = Date.now();
            var dt = now - lastTime;
            if (dt > 0)
                velocityY = (mouse.y - lastY) / dt * 1000;

            lastY = mouse.y;
            lastTime = now;
            startY = mouse.y;
        }
        onReleased: mouse => {
            UIStore.quickSettingsDragging = false;
            var isFlingUp = velocityY < -500;
            if (isFlingUp || UIStore.quickSettingsHeight < shell.quickSettingsThreshold)
                UIStore.closeQuickSettings();
            else
                UIStore.openQuickSettings();
            startY = 0;
            lastY = 0;
            velocityY = 0;
            Logger.gesture("QuickSettings", "overlayDragEnd", {
                "height": UIStore.quickSettingsHeight,
                "velocity": velocityY,
                "fling": isFlingUp
            });
        }
        onCanceled: {
            UIStore.quickSettingsDragging = false;
            if (UIStore.quickSettingsHeight > shell.quickSettingsThreshold)
                UIStore.openQuickSettings();
            else
                UIStore.closeQuickSettings();
            startY = 0;
            Logger.gesture("QuickSettings", "overlayDragCanceled", {
                "height": UIStore.quickSettingsHeight
            });
        }

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
    }

    MarathonLockScreen {
        id: lockScreen

        anchors.fill: parent
        z: Constants.zIndexLockScreen
        onUnlockRequested: {
            if (SessionStore.checkSession()) {
                Logger.state("Shell", "locked", "unlocked");
                SessionStore.unlock();
                if (pendingLaunch) {
                    Logger.info("Shell", "Executing pending launch: " + pendingLaunch.appName);
                    UIStore.openApp(pendingLaunch.appId, pendingLaunch.appName, "");
                    pendingLaunch = null;
                }
            } else {
                Logger.state("Shell", "locked", "pinEntry");
                showPinScreen = true;
                pinScreen.show();
            }
        }
        onNotificationTapped: function (notifId, appId, title) {
            Logger.info("Shell", "Lock screen notification tapped: " + title + " (id: " + notifId + ", app: " + appId + ")");
            if (SessionStore.checkSession()) {
                Logger.info("Shell", "Session valid, unlocking and navigating to notification");
                SessionStore.unlock();
                NotificationService.dismissNotification(notifId);
                if (appId)
                    NavigationRouter.navigateToDeepLink(appId, "", {
                        "notificationId": notifId,
                        "action": "view",
                        "from": "lockscreen"
                    });
            } else {
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
                SessionStore.unlock();
                UIStore.openApp("camera", "Camera", "");
            } else {
                Logger.info("LockScreen", "Session locked - requesting PIN for Camera");
                pendingLaunch = {
                    "appId": "camera",
                    "appName": "Camera"
                };
                showPinScreen = true;
                pinScreen.show();
            }
            HapticService.medium();
        }
        onPhoneLaunched: {
            Logger.info("LockScreen", "Phone quick action tapped");
            if (SessionStore.checkSession()) {
                SessionStore.unlock();
                UIStore.openApp("phone", "Phone", "");
            } else {
                Logger.info("LockScreen", "Session locked - requesting PIN for Phone");
                pendingLaunch = {
                    "appId": "phone",
                    "appName": "Phone"
                };
                showPinScreen = true;
                pinScreen.show();
            }
            HapticService.medium();
        }
    }

    MarathonPinScreen {
        id: pinScreen

        anchors.fill: parent
        z: Constants.zIndexPinScreen
        onPinCorrect: {
            Logger.state("Shell", "pinEntry", "unlocked");
            showPinScreen = false;
            pinScreen.reset();
            SessionStore.unlock();
            if (pendingLaunch) {
                Logger.info("Shell", "Executing pending launch: " + pendingLaunch.appName);
                UIStore.openApp(pendingLaunch.appId, pendingLaunch.appName, "");
                pendingLaunch = null;
            }
            if (pendingNotification) {
                Logger.info("Shell", "Executing pending notification action: " + pendingNotification.title);
                NotificationService.dismissNotification(pendingNotification.id);
                if (pendingNotification.appId)
                    NavigationRouter.navigateToDeepLink(pendingNotification.appId, "", {
                        "notificationId": pendingNotification.id,
                        "action": "view",
                        "from": "lockscreen"
                    });

                pendingNotification = null;
            }
        }
        onCancelled: {
            Logger.info("PinScreen", "Cancelled by user");
            showPinScreen = false;
            lockScreen.swipeProgress = 0;
            pinScreen.reset();
            if (pendingLaunch) {
                Logger.info("Shell", "Clearing pending launch");
                pendingLaunch = null;
            }
            if (pendingNotification) {
                Logger.info("Shell", "Clearing pending notification action");
                pendingNotification = null;
            }
        }
    }

    NotificationToast {
        id: notificationToast

        Connections {
            function onNotificationReceived(notification) {
                notificationToast.showToast(notification);
            }

            target: NotificationService
        }
    }

    SystemHUD {
        id: systemHUD

        property bool initialized: false

        Component.onCompleted: {
            initTimer.start();
        }

        Connections {
            function onVolumeChanged() {
                if (systemHUD.initialized)
                    systemHUD.showVolume(SystemControlStore.volume / 100);
            }

            function onBrightnessChanged() {
                if (systemHUD.initialized)
                    systemHUD.showBrightness(SystemControlStore.brightness / 100);
            }

            target: SystemControlStore
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
            function onShowConfirmDialog(title, message, onConfirm) {
                confirmDialog.show(title, message, onConfirm);
            }

            target: UIStore
        }
    }

    MarathonSearch {
        id: universalSearch

        anchors.fill: parent
        z: Constants.zIndexSearch
        active: UIStore.searchOpen
        pullProgress: pageView.searchPullProgress
        onClosed: {
            UIStore.closeSearch();
            shell.forceActiveFocus();
        }
        onResultSelected: result => {
            if (result.type === "app") {
                var app = {
                    "id": result.data.id,
                    "name": result.data.name,
                    "icon": result.data.icon,
                    "type": result.data.type || "marathon"
                };
                AppLaunchService.launchApp(app, compositor, appWindow);
            } else if (result.type === "deeplink")
                UnifiedSearchService.executeSearchResult(result);
            else if (result.type === "setting")
                UnifiedSearchService.executeSearchResult(result);
            UIStore.closeSearch();
        }
    }

    ScreenshotPreview {
        id: screenshotPreview
    }

    Connections {
        function onScreenshotCaptured(filePath, thumbnailPath) {
            Logger.info("Shell", "Screenshot captured: " + filePath);
            screenshotPreview.show(filePath, thumbnailPath);
            HapticService.medium();
        }

        function onScreenshotFailed(error) {
            Logger.error("Shell", "Screenshot failed: " + error);
        }

        target: ScreenshotService
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

    ErrorToast {
        id: errorToast
    }

    Comp.PermissionDialog {
        id: permissionDialog

        z: Constants.zIndexModalOverlay + 50
    }

    Connections {
        function onWifiConnectedChanged() {
            if (typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp && NetworkManagerCpp.wifiConnected)
                connectionToast.show("Connected to Wi-Fi", "wifi");
            else if (typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp && NetworkManagerCpp.wifiEnabled && !NetworkManagerCpp.wifiConnected)
                connectionToast.show("Wi-Fi disconnected", "wifi-off");
        }

        function onEthernetConnectedChanged() {
            if (typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp && NetworkManagerCpp.ethernetConnected)
                connectionToast.show("Connected to Ethernet", "plug-zap");
            else if (typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp && !NetworkManagerCpp.ethernetConnected && !NetworkManagerCpp.wifiConnected)
                connectionToast.show("No network connection", "wifi-off");
        }

        target: typeof NetworkManagerCpp !== "undefined" ? NetworkManagerCpp : null
    }

    Connections {
        function onBatteryWarning(title, body, iconName, hapticLevel) {
            if (errorToast)
                errorToast.show(title, body, iconName);

            if (typeof HapticService !== "undefined" && HapticService) {
                if (hapticLevel >= 3)
                    HapticService.heavy();
                else if (hapticLevel === 2)
                    HapticService.medium();
                else if (hapticLevel === 1)
                    HapticService.light();
            }
        }

        function onEmergencyShutdownArmed(secondsUntilShutdown) {
            criticalBatteryShutdownTimer.interval = Math.max(0, secondsUntilShutdown * 1000);
            criticalBatteryShutdownTimer.start();
        }

        function onEmergencyShutdownDisarmed() {
            criticalBatteryShutdownTimer.stop();
        }

        target: typeof PowerPolicyControllerCpp !== "undefined" ? PowerPolicyControllerCpp : null
    }

    Timer {
        id: criticalBatteryShutdownTimer

        interval: 10000
        repeat: false
        onTriggered: {
            Logger.critical("Battery", "Emergency critical power action due to battery");
            if (typeof PowerPolicyControllerCpp !== "undefined" && PowerPolicyControllerCpp)
                PowerPolicyControllerCpp.performCriticalPowerAction();
            else if (typeof PowerManagerService !== "undefined" && PowerManagerService)
                PowerManagerService.shutdown();
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

    MarathonOOBE {
        id: oobeWizard

        onSetupComplete: {
            Logger.info("Shell", "OOBE setup completed");
        }
    }

    Connections {
        function onAlarmTriggered(alarm) {
            Logger.info("Shell", "Alarm triggered: " + (alarm && alarm.label ? alarm.label : "(unknown)"));
            alarmOverlay.show(alarm);
            HapticService.heavy();
        }

        target: typeof AlarmManager !== 'undefined' ? AlarmManager : null
    }

    VirtualKeyboard {
        id: virtualKeyboard

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        Component.onCompleted: {
            focusConnection.target = Window.window;
        }

        Connections {
            id: focusConnection

            function onActiveFocusItemChanged() {
                var item = focusConnection.target ? focusConnection.target.activeFocusItem : null;
                if (!item) {
                    // Internal focus lost. If InputMethodEngine is also not active, hide.
                    if (!InputMethodEngine.active)
                        virtualKeyboard.active = false;

                    return;
                }
                var isInput = (item.toString().indexOf("TextInput") !== -1 || item.toString().indexOf("TextEdit") !== -1);
                if (isInput && !Platform.hasHardwareKeyboard)
                    virtualKeyboard.active = true;
                else if (virtualKeyboard.active && !InputMethodEngine.active)
                    virtualKeyboard.active = false;
            }

            target: null
        }

        Connections {
            function onKeyboardRequested() {
                Logger.info("Shell", "InputMethodEngine: Keyboard requested");
                if (!Platform.hasHardwareKeyboard)
                    virtualKeyboard.active = true;
            }

            function onKeyboardHideRequested() {
                Logger.info("Shell", "InputMethodEngine: Keyboard hide requested");
                virtualKeyboard.active = false;
            }

            function onInputItemFocused() {
                Logger.info("Shell", "InputMethodEngine: Input item focused");
                if (!Platform.hasHardwareKeyboard)
                    virtualKeyboard.active = true;
            }

            function onInputItemUnfocused() {
                // If internal focus is NOT on an input, hide.
                var item = Window.window ? Window.window.activeFocusItem : null;
                var isInternalInput = item && (item.toString().indexOf("TextInput") !== -1 || item.toString().indexOf("TextEdit") !== -1);
                if (!isInternalInput) {
                    Logger.info("Shell", "InputMethodEngine: Input item unfocused");
                    virtualKeyboard.active = false;
                }
            }

            target: InputMethodEngine
        }
    }

    Connections {
        function onNativeTextInputPanelRequested(show) {
            if (typeof Platform !== 'undefined' && !Platform.hasHardwareKeyboard) {
                Logger.info("Shell", "Native app text input panel requested: " + show);
                if (show && !virtualKeyboard.active)
                    virtualKeyboard.active = true;
                else if (!show && virtualKeyboard.active)
                    virtualKeyboard.active = false;
            }
        }

        target: typeof compositor !== 'undefined' ? compositor : null
        enabled: typeof compositor !== 'undefined'
    }

    MouseArea {
        id: keyboardDismissArea

        anchors.fill: parent
        anchors.bottomMargin: virtualKeyboard.height
        z: Constants.zIndexKeyboard - 1
        visible: virtualKeyboard.active
        enabled: virtualKeyboard.active
        propagateComposedEvents: true
        onPressed: function (mouse) {
            Logger.info("Shell", "Tap outside keyboard - dismissing and forwarding tap");
            virtualKeyboard.active = false;
            mouse.accepted = false;
        }
    }

    Timer {
        id: powerButtonTimer

        interval: 800
        onTriggered: {
            Logger.info("Shell", "Power button LONG PRESS detected - showing power menu");
            powerMenu.show();
        }
    }

    PowerMenu {
        id: powerMenu

        onSleepRequested: {
            Logger.info("Shell", "Sleep requested from power menu");
            var locked = SessionStore.isLocked;
            if (typeof PowerPolicyControllerCpp !== "undefined" && PowerPolicyControllerCpp) {
                var action = PowerPolicyControllerCpp.sleepAction(locked);
                if (action === PowerPolicyControllerCpp.LockThenSleep)
                    SessionStore.lock();
            } else if (!locked) {
                SessionStore.lock();
            }
            if (typeof PowerPolicyControllerCpp !== "undefined" && PowerPolicyControllerCpp)
                PowerPolicyControllerCpp.sleep();
            else
                PowerManagerService.suspend();
        }
        onRebootRequested: {
            Logger.info("Shell", "Reboot requested from power menu");
            if (typeof PowerManagerService !== "undefined" && PowerManagerService)
                PowerManagerService.restart();
        }
        onShutdownRequested: {
            Logger.info("Shell", "Shutdown requested from power menu");
            if (typeof PowerManagerService !== "undefined" && PowerManagerService)
                PowerManagerService.shutdown();
        }
    }

    Rectangle {
        id: screenshotFlash

        function trigger() {
            flashAnimation.restart();
        }

        anchors.fill: parent
        color: "white"
        opacity: 0
        z: Constants.zIndexModalOverlay + 200

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
        source: Qt.resolvedUrl("components/IncomingCallOverlay.qml")
    }

    Connections {
        function onAnswered() {
            TelephonyIntegration.callWasAnswered = true;
        }

        function onDeclined() {
            TelephonyIntegration.callWasAnswered = false;
        }

        target: incomingCallOverlayLoader.item
        enabled: incomingCallOverlayLoader.item !== null
    }

    Connections {
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

        target: typeof TelephonyService !== 'undefined' ? TelephonyService : null
    }

    Connections {
        function onMessageReceived(sender, text, timestamp) {
            TelephonyIntegration.handleMessageReceived(sender, text, timestamp);
        }

        target: typeof SMSService !== 'undefined' ? SMSService : null
    }
}
