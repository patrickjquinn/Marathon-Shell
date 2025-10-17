import QtQuick
import QtQuick.Window
import "./components"
import MarathonOS.Shell

Item {
    id: shell
    focus: true  // Enable keyboard input
    
    property var compositor: null
    property var pendingNativeApp: null
    property alias appWindowContainer: appWindowContainer
    
    // State management moved to stores
    property bool showPinScreen: false
    property bool isTransitioningToActiveFrames: false
    property int currentPage: 0
    property int totalPages: 1
    
    // Dynamic Quick Settings sizing
    readonly property real maxQuickSettingsHeight: shell.height - Constants.statusBarHeight
    readonly property real quickSettingsThreshold: maxQuickSettingsHeight * 0.43  // 43% threshold
    
    // Handle deep link requests from NavigationRouter
    Connections {
        target: NavigationRouter
        
        function onDeepLinkRequested(appId, route, params) {
            Logger.info("Shell", "Deep link requested: " + appId)
            
            // Launch the app
            var app = AppStore.getApp(appId)
            if (app) {
                UIStore.openApp(app.id, app.name, app.icon)
                appWindow.show(app.id, app.name, app.icon, app.type)
                if (typeof AppLifecycleManager !== 'undefined') {
                    AppLifecycleManager.bringToForeground(app.id)
                }
            } else {
                Logger.warn("Shell", "App not found for deep link: " + appId)
            }
        }
    }
    
    Component.onCompleted: {
        // Load persisted settings
        Constants.userScaleFactor = SettingsManagerCpp.userScaleFactor
        WallpaperStore.currentWallpaper = SettingsManagerCpp.wallpaperPath
        
        // Initialize responsive sizing system
        Constants.updateScreenSize(shell.width, shell.height, Screen.pixelDensity * 25.4)
        UIStore.shellRef = shell
        Logger.info("Shell", "Screen size: " + shell.width + "x" + shell.height + " @ " + Math.round(Screen.pixelDensity * 25.4) + " DPI")
        Logger.info("Shell", "Scale factor: " + Constants.scaleFactor + " (base: " + (Constants.screenHeight / Constants.baseHeight) + " x user: " + Constants.userScaleFactor + ")")
        
        forceActiveFocus()
        Logger.info("Shell", "Marathon Shell initialized")
        
        try {
            var rootWindow = Window.window
            if (rootWindow) {
                compositor = Qt.createQmlObject('import QtQuick; import MarathonOS.Wayland 1.0; WaylandCompositor {}', shell, "compositor")
                if (compositor) {
                    compositor.parent = rootWindow
                    Logger.info("Shell", "Wayland Compositor initialized: " + compositor.socketName)
                }
            }
        } catch (e) {
            Logger.info("Shell", "Wayland Compositor not available on this platform (expected on macOS)")
            compositor = null
        }
    }
    
    // Handle window resize (for desktop/tablet)
    onWidthChanged: {
        if (Constants.screenWidth > 0) {  // Only after initialization
            Constants.updateScreenSize(shell.width, shell.height, Screen.pixelDensity * 25.4)
        }
    }
    onHeightChanged: {
        if (Constants.screenHeight > 0) {  // Only after initialization
            Constants.updateScreenSize(shell.width, shell.height, Screen.pixelDensity * 25.4)
        }
    }
    
    // State-based navigation using centralized stores
    state: SessionStore.isLocked ? (showPinScreen ? "pinEntry" : "locked") : 
           (UIStore.appWindowOpen ? "app" : "home")
    
    states: [
        State {
            name: "locked"
            PropertyChanges { target: lockScreen; visible: true; enabled: true; opacity: 1.0 }
            PropertyChanges { target: pinScreen; visible: false; enabled: false }
            PropertyChanges { target: mainContent; visible: false; enabled: false }
            PropertyChanges { target: appWindow; visible: false }
            PropertyChanges { target: navBar; visible: false }
        },
        State {
            name: "pinEntry"
            PropertyChanges { target: lockScreen; visible: false; enabled: false }
            PropertyChanges { target: pinScreen; visible: true; enabled: true }
            PropertyChanges { target: mainContent; visible: false; enabled: false }
            PropertyChanges { target: appWindow; visible: false }
            PropertyChanges { target: navBar; visible: false }
        },
        State {
            name: "home"
            PropertyChanges { target: lockScreen; visible: false; enabled: false; opacity: 0.0 }
            PropertyChanges { target: pinScreen; visible: false; enabled: false }
            PropertyChanges { target: mainContent; visible: true; enabled: true }
            PropertyChanges { target: appWindow; visible: false }
            PropertyChanges { target: navBar; visible: true }
        },
        State {
            name: "app"
            PropertyChanges { target: lockScreen; visible: false; enabled: false }
            PropertyChanges { target: pinScreen; visible: false; enabled: false }
            PropertyChanges { target: mainContent; visible: false; enabled: false }
            PropertyChanges { target: appWindow; visible: true }
            PropertyChanges { target: statusBar; visible: true; z: Constants.zIndexStatusBarApp }
            PropertyChanges { target: navBar; visible: true; z: Constants.zIndexNavBarApp }
        }
    ]
    
    transitions: [
        Transition {
            from: "locked"
            to: "home"
            SequentialAnimation {
                NumberAnimation {
                    target: lockScreen
                    property: "opacity"
                    to: 0
                    duration: Constants.animationSlow
                    easing.type: Easing.OutCubic
                }
                PropertyAction {
                    target: lockScreen
                    property: "visible"
                    value: false
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
        
        Behavior on opacity {
            NumberAnimation {
                duration: 400
                easing.type: Easing.InCubic
            }
        }
        
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
                
                onCurrentPageChanged: {
                    Logger.nav("page" + shell.currentPage, "page" + currentPage, "navigation")
                    shell.currentPage = currentPage
                    if (currentPage >= 0) {
                        shell.totalPages = Math.max(1, Math.ceil(AppModel.count / 16))
                    }
                }
                
                onAppLaunched: (app) => {
                    Logger.info("Shell", "App launched: " + app.name + " (type: " + app.type + ")")
                    
                    if (app.type === "native") {
                        if (compositor) {
                            shell.pendingNativeApp = app
                            compositor.launchApp(app.exec)
                        } else {
                            Logger.warn("Shell", "Cannot launch native app - compositor not available")
                        }
                    } else {
                        // All Marathon apps (including Settings) go through same path
                        UIStore.openApp(app.id, app.name, app.icon)
                        appWindow.show(app.id, app.name, app.icon, app.type)
                        if (typeof AppLifecycleManager !== 'undefined') {
                            AppLifecycleManager.bringToForeground(app.id)
                        }
                    }
                }
                
                Component.onCompleted: {
                    shell.totalPages = Math.max(1, Math.ceil(AppModel.count / 16))
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
                    
                    onAppLaunched: (app) => {
                        Logger.info("Shell", "Bottom bar launched: " + app.name + " (type: " + app.type + ")")
                        
                        if (app.type === "native") {
                            if (compositor) {
                                shell.pendingNativeApp = app
                                compositor.launchApp(app.exec)
                            } else {
                                Logger.warn("Shell", "Cannot launch native app - compositor not available")
                            }
                        } else {
                            // All Marathon apps go through same path
                            UIStore.openApp(app.id, app.name, app.icon)
                            appWindow.show(app.id, app.name, app.icon, app.type)
                            if (typeof AppLifecycleManager !== 'undefined') {
                                AppLifecycleManager.bringToForeground(app.id)
                            }
                        }
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
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        z: Constants.zIndexNavBarApp
        isAppOpen: UIStore.appWindowOpen || UIStore.settingsOpen
            
            onSwipeLeft: {
                if (pageView.currentIndex < pageView.count - 1) {
                    pageView.incrementCurrentIndex()
                    Router.navigateLeft()
                }
            }
        
            onSwipeRight: {
                // Check if app can handle forward navigation first
                if (UIStore.appWindowOpen && typeof AppLifecycleManager !== 'undefined') {
                    var handled = AppLifecycleManager.handleSystemForward()
                    if (handled) {
                        return
                    }
                }
                
                // Otherwise, navigate pages
                if (pageView.currentIndex > 0) {
                    pageView.decrementCurrentIndex()
                    Router.navigateRight()
                }
            }
        
        onSwipeBack: {
            Logger.info("NavBar", "Back gesture detected")
            
            if (typeof AppLifecycleManager !== 'undefined') {
                var handled = AppLifecycleManager.handleSystemBack()
                if (!handled) {
                    Logger.info("NavBar", "App didn't handle back, closing")
                    if (UIStore.appWindowOpen) {
                        UIStore.closeApp()
                    }
                }
            } else {
                Logger.info("NavBar", "AppLifecycleManager unavailable, closing directly")
                if (UIStore.appWindowOpen) {
                    UIStore.closeApp()
                }
            }
        }
        
            onShortSwipeUp: {
                Logger.gesture("NavBar", "shortSwipeUp", {target: "home"})
                pageView.currentIndex = 2
                Router.goToAppPage(0)
            }
        
            onLongSwipeUp: {
                Logger.gesture("NavBar", "longSwipeUp", {target: "activeFrames"})
            
            if (UIStore.appWindowOpen && !UIStore.settingsOpen) {
                Logger.info("NavBar", "Minimizing app to active frames")
                appWindow.hide()
                UIStore.closeApp()
            }
            
            pageView.currentIndex = 1
            Router.goToFrames()
        }
        
        onStartPageTransition: {
            if ((UIStore.appWindowOpen || UIStore.settingsOpen) && pageView.currentIndex !== 1) {
                pageView.currentIndex = 1
                Router.goToFrames()
            }
        }
        
        onMinimizeApp: {
            Logger.info("Shell", "NavBar minimize gesture detected")
            
            // Use AppLifecycleManager for proper snapshot capture and task management
            if (typeof AppLifecycleManager !== 'undefined') {
                AppLifecycleManager.minimizeForegroundApp()
            }
            
            shell.isTransitioningToActiveFrames = true
            snapIntoGridAnimation.start()
        }
    }
    
    // Peek & Flow
    MarathonPeek {
        id: peekFlow
        anchors.fill: parent
        visible: !SessionStore.isLocked
        z: Constants.zIndexPeek
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
        
        onPressed: (mouse) => {
            startX = mouse.x
            lastX = mouse.x
            peekFlow.startPeekGesture(mouse.x)
        }
        
        onPositionChanged: (mouse) => {
            if (pressed) {
                var absoluteX = peekGestureCapture.x + mouse.x
                var deltaX = absoluteX - startX
                peekFlow.updatePeekGesture(deltaX)
                lastX = absoluteX
            }
        }
        
        onReleased: {
            peekFlow.endPeekGesture()
        }
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
        
        scale: shell.isTransitioningToActiveFrames ? finalScale : (navBar.gestureProgress > 0 ? currentGestureScale : 1.0)
        opacity: shell.isTransitioningToActiveFrames ? 0.0 : (navBar.gestureProgress > 0 ? currentGestureOpacity : 1.0)
        
        property bool showCardFrame: navBar.gestureProgress > 0.3 || shell.isTransitioningToActiveFrames
        
        // Watch for app switching (when restoring from task switcher)
        Connections {
            target: UIStore
            function onCurrentAppIdChanged() {
                if (UIStore.appWindowOpen && UIStore.currentAppId) {
                    Logger.info("Shell", "App ID changed, showing: " + UIStore.currentAppId)
                    appWindow.show(UIStore.currentAppId, UIStore.currentAppName, UIStore.currentAppIcon, "marathon")
                }
            }
            
            function onAppWindowOpenChanged() {
                // Also trigger when appWindowOpen becomes true (covers case where appId hasn't changed)
                if (UIStore.appWindowOpen && UIStore.currentAppId) {
                    Logger.info("Shell", "App window opened, showing: " + UIStore.currentAppId)
                    appWindow.show(UIStore.currentAppId, UIStore.currentAppName, UIStore.currentAppIcon, "marathon")
                }
            }
        }
        
        Behavior on opacity {
            enabled: shell.isTransitioningToActiveFrames
            NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
        }
        
        Behavior on scale {
            enabled: false
        }
        
        Behavior on anchors.margins {
            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
        }
        
        Rectangle {
            id: cardBorder
            anchors.fill: parent
            color: "transparent"
            radius: 4
            border.width: appWindowContainer.showCardFrame ? 1 : 0
            border.color: Qt.rgba(255, 255, 255, 0.12)
            layer.enabled: appWindowContainer.showCardFrame
            clip: true
            
            Behavior on border.width {
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }
            
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                color: "transparent"
                border.width: appWindowContainer.showCardFrame ? 1 : 0
                border.color: Qt.rgba(255, 255, 255, 0.03)
                
                Behavior on border.width {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }
            }
            
            Rectangle {
                id: appCardBackground
                anchors.fill: parent
                color: Colors.backgroundDark
                radius: parent.radius
                opacity: appWindowContainer.showCardFrame ? 1.0 : 0.0
                
                Behavior on opacity {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }
            }
            
            MarathonAppWindow {
                id: appWindow
                anchors.fill: parent
                anchors.topMargin: Constants.safeAreaTop
                anchors.bottomMargin: Constants.safeAreaBottom
                visible: true
        
        onMinimized: {
                    Logger.info("AppWindow", "Minimized: " + appWindow.appName)
                    UIStore.minimizeApp()
                    pageView.currentIndex = 1
                    Router.goToFrames()
                }
                
                onClosed: {
                    Logger.info("AppWindow", "Closed: " + appWindow.appName)
            UIStore.closeApp()
                }
            }
        }
        
        Rectangle {
            id: appCardFrameOverlay
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: Constants.touchTargetSmall
            color: Colors.surfaceLight
            opacity: (navBar.gestureProgress > 0.3 || shell.isTransitioningToActiveFrames) ? (1.0 / Math.max(0.1, appWindowContainer.opacity)) : 0.0
            visible: opacity > 0
            z: 100
            
            Rectangle {
                width: parent.width
                height: 6
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
                    width: 32
                    height: 32
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                    smooth: true
                }
                
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 80
                    spacing: 2
                    
                    Text {
                        text: appWindow.appName
                        color: Colors.text
                        font.pixelSize: Typography.sizeSmall
                        font.weight: Font.DemiBold
                        font.family: Typography.fontFamily
                        elide: Text.ElideRight
                        width: parent.width
                    }
                    
                    Text {
                        text: "Running"
                        color: Colors.textSecondary
                        font.pixelSize: Typography.sizeXSmall
                        font.family: Typography.fontFamily
                        opacity: 0.7
                    }
                }
                
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32
                    height: 32
                    
                    Rectangle {
                        anchors.centerIn: parent
                        width: 28
                        height: 28
                        radius: Colors.cornerRadiusSmall
                        color: Colors.surfaceLight
                        
                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            color: Colors.text
                            font.pixelSize: Typography.sizeLarge
                            font.weight: Font.Bold
                        }
                        
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -8
                            onClicked: {
            UIStore.closeApp()
                            }
                        }
                    }
                }
            }
        }
    }
    
    SequentialAnimation {
        id: snapIntoGridAnimation
        
        PauseAnimation {
            duration: 100
        }
        
        ScriptAction {
            script: {
                if (UIStore.settingsOpen) {
                    UIStore.minimizeSettings()
                } else if (UIStore.appWindowOpen) {
                    UIStore.minimizeApp()
                }
                shell.isTransitioningToActiveFrames = false
            }
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
            UIStore.closeQuickSettings()
        }
        
        onLaunchApp: (app) => {
            UIStore.openApp(app.id, app.name, app.icon)
            appWindow.show(app.id, app.name, app.icon, app.type)
            if (typeof AppLifecycleManager !== 'undefined') {
                AppLifecycleManager.bringToForeground(app.id)
            }
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
        
        onPressed: (mouse) => {
            if (UIStore.quickSettingsHeight > 0) {
                mouse.accepted = false
                return
            }
            startY = mouse.y
            isDraggingDown = false
        }
        
        onPositionChanged: (mouse) => {
            var dragDistance = mouse.y - startY
            
            if (dragDistance > 5 && !isDraggingDown) {
                isDraggingDown = true
                UIStore.quickSettingsDragging = true
                Logger.gesture("StatusBar", "dragStart", {y: startY})
            }
            
            if (isDraggingDown) {
                UIStore.quickSettingsHeight = Math.min(shell.maxQuickSettingsHeight, dragDistance)
            }
        }
        
        onReleased: (mouse) => {
            if (isDraggingDown) {
                UIStore.quickSettingsDragging = false
                if (UIStore.quickSettingsHeight > shell.quickSettingsThreshold) {
                    UIStore.openQuickSettings()
                } else {
                    UIStore.closeQuickSettings()
                }
                Logger.gesture("StatusBar", "dragEnd", {height: UIStore.quickSettingsHeight})
            }
            startY = 0
            isDraggingDown = false
        }
        
        onCanceled: {
            Logger.debug("StatusBar", "Touch canceled")
            startY = 0
            isDraggingDown = false
            UIStore.quickSettingsDragging = false
            UIStore.closeQuickSettings()
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
        
        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: parent.enabled ? 0.3 : 0
            
            Behavior on opacity {
                NumberAnimation { duration: Constants.animationFast }
            }
        }
        
        onPressed: (mouse) => {
            startY = mouse.y
            UIStore.quickSettingsDragging = true
            Logger.gesture("QuickSettings", "overlayDragStart", {y: startY})
        }
        
        onPositionChanged: (mouse) => {
            var dragDistance = mouse.y - startY
            var newHeight = UIStore.quickSettingsHeight + dragDistance
            UIStore.quickSettingsHeight = Math.max(0, Math.min(shell.maxQuickSettingsHeight, newHeight))
            startY = mouse.y
        }
        
        onReleased: (mouse) => {
            UIStore.quickSettingsDragging = false
            if (UIStore.quickSettingsHeight > shell.quickSettingsThreshold) {
                UIStore.openQuickSettings()
            } else {
                UIStore.closeQuickSettings()
            }
            startY = 0
            Logger.gesture("QuickSettings", "overlayDragEnd", {height: UIStore.quickSettingsHeight})
        }
    }
    
    // Lock Screen
    MarathonLockScreen {
        id: lockScreen
        anchors.fill: parent
        z: Constants.zIndexLockScreen
        
        onUnlockRequested: {
            if (SessionStore.checkSession()) {
                Logger.state("Shell", "locked", "unlocked")
                SessionStore.unlock()
            } else {
                Logger.state("Shell", "locked", "pinEntry")
                showPinScreen = true
                pinScreen.show()
            }
        }
        
        onCameraLaunched: {
            Logger.info("LockScreen", "Camera launched")
            AppStore.launchApp("camera")
        }
        
        onNotificationTapped: (id) => {
            Logger.info("LockScreen", "Notification tapped: " + id)
            NotificationModel.markAsRead(id)
        }
    }
    
    // PIN Entry Screen
    MarathonPinScreen {
        id: pinScreen
        anchors.fill: parent
        z: Constants.zIndexPinScreen
        
        onPinCorrect: {
            Logger.state("Shell", "pinEntry", "unlocked")
            showPinScreen = false
            SessionStore.unlock()
            lockScreen.swipeProgress = 0
            pinScreen.reset()
        }
        
        onCancelled: {
            Logger.info("PinScreen", "Cancelled by user")
            showPinScreen = false
            lockScreen.swipeProgress = 0
            pinScreen.reset()
        }
    }
    
    NotificationToast {
        id: notificationToast
        
        Connections {
            target: NotificationService
            function onNotificationReceived(notification) {
                notificationToast.showToast(notification)
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
                    systemHUD.showVolume(SystemControlStore.volume / 100.0)
                }
            }
            function onBrightnessChanged() {
                if (systemHUD.initialized) {
                    systemHUD.showBrightness(SystemControlStore.brightness / 100.0)
                }
            }
        }
        
        Component.onCompleted: {
            initTimer.start()
        }
        
        Timer {
            id: initTimer
            interval: 500
            onTriggered: {
                systemHUD.initialized = true
            }
        }
    }
    
    ConfirmDialog {
        id: confirmDialog
        
        Connections {
            target: UIStore
            function onShowConfirmDialog(title, message, onConfirm) {
                confirmDialog.show(title, message, onConfirm)
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
            UIStore.closeSearch()
            shell.forceActiveFocus()
        }
    }
    
    ScreenshotPreview {
        id: screenshotPreview
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
    
    VirtualKeyboard {
        id: virtualKeyboard
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
    }
    
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            Logger.debug("Shell", "Escape key pressed")
            if (showPinScreen) {
                showPinScreen = false
                lockScreen.swipeProgress = 0
                pinScreen.reset()
            } else if (UIStore.searchOpen) {
                UIStore.closeSearch()
            } else if (UIStore.shareSheetOpen) {
                UIStore.closeShareSheet()
            } else if (UIStore.clipboardManagerOpen) {
                UIStore.closeClipboardManager()
            } else if (peekFlow.peekProgress > 0) {
                peekFlow.closePeek()
            } else if (UIStore.quickSettingsOpen) {
                UIStore.closeQuickSettings()
            } else if (messagingHub.showVertical) {
                messagingHub.showVertical = false
            }
        } else if ((event.key === Qt.Key_Space) && (event.modifiers & Qt.ControlModifier)) {
            Logger.debug("Shell", "Cmd+Space pressed - Opening Universal Search")
            UIStore.toggleSearch()
            HapticService.light()
            event.accepted = true
        } else if ((event.key === Qt.Key_3) && (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier)) {
            Logger.debug("Shell", "Cmd+Shift+3 pressed - Taking Screenshot")
            ScreenshotService.captureScreen(shell)
            HapticService.medium()
            event.accepted = true
        } else if ((event.key === Qt.Key_V) && (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier)) {
            Logger.debug("Shell", "Cmd+Shift+V pressed - Opening Clipboard Manager")
            UIStore.openClipboardManager()
            HapticService.light()
            event.accepted = true
        } else if (shell.state === "home" && !UIStore.searchOpen && !UIStore.appWindowOpen) {
            // Alphanumeric keys trigger search with that character
            if (event.text.length > 0 && event.text.match(/[a-zA-Z0-9]/)) {
                Logger.info("Shell", "Global search triggered with: '" + event.text + "'")
                UIStore.openSearch()
                Qt.callLater(function() {
                    universalSearch.appendToSearch(event.text)
                })
                event.accepted = true
            }
        }
    }
    
    Connections {
        target: compositor
        
        function onSurfaceCreated(surface) {
            Logger.info("Shell", "Native app surface created")
            
            if (shell.pendingNativeApp) {
                var app = shell.pendingNativeApp
                var surfaceId = surface.property("surfaceId")
                
                Logger.info("Shell", "Showing native app window: " + app.name + " (surfaceId: " + surfaceId + ")")
                
                UIStore.openApp(app.id, app.name, app.icon)
                appWindow.show(app.id, app.name, app.icon, "native", surface, surfaceId)
                
                if (typeof AppLifecycleManager !== 'undefined') {
                    AppLifecycleManager.bringToForeground(app.id)
                }
                
                shell.pendingNativeApp = null
            }
        }
        
        function onAppLaunched(command, pid) {
            Logger.info("Shell", "Native app process started: " + command + " (PID: " + pid + ")")
        }
        
        function onSurfaceDestroyed(surface) {
            Logger.info("Shell", "Native app surface destroyed")
            
            if (UIStore.appWindowOpen && appWindow.appType === "native") {
                var surfaceId = surface.property("surfaceId")
                if (appWindow.surfaceId === surfaceId) {
                    Logger.info("Shell", "Closing native app window due to surface destruction")
                    UIStore.closeApp()
                    appWindow.hide()
                }
            }
        }
    }
}
