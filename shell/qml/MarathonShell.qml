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
        
        // Request compositor initialization from C++
        console.log("========== COMPOSITOR INITIALIZATION ==========")
        console.log("  WaylandCompositorManager defined?", typeof WaylandCompositorManager !== 'undefined')
        
        if (typeof WaylandCompositorManager !== 'undefined') {
            console.log("  Getting Window.window...")
            var rootWindow = Window.window
            console.log("  rootWindow:", rootWindow)
            
            if (rootWindow) {
                console.log("  Calling WaylandCompositorManager.createCompositor...")
                compositor = WaylandCompositorManager.createCompositor(rootWindow)
                console.log("  compositor returned:", compositor)
                
                if (compositor) {
                    console.log("  compositor.socketName:", compositor.socketName)
                    Logger.info("Shell", "Wayland Compositor initialized: " + compositor.socketName)
                } else {
                    console.log("  compositor is NULL")
                    Logger.info("Shell", "Wayland Compositor not available on this platform")
                }
            } else {
                console.log("  rootWindow is NULL!")
            }
        } else {
            console.log("  WaylandCompositorManager is UNDEFINED")
            Logger.info("Shell", "Wayland Compositor not available on this platform (expected on macOS)")
            compositor = null
        }
        Logger.info("Shell", compositor ? "Compositor created successfully" : "Compositor is NULL")
        
        // Test if compositor signals are connected
        if (compositor) {
            Logger.info("Shell", "Testing compositor signal connection...")
            compositor.surfaceCreated.connect(function(surface, surfaceId, xdgSurface) {
                Logger.info("Shell", "!!!!! DIRECT SIGNAL CONNECTION FIRED - surfaceId: " + surfaceId)
            })
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
            PropertyChanges {
                lockScreen.visible: true
                lockScreen.enabled: true
                lockScreen.opacity: 1.0
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
            }
            PropertyChanges {
                mainContent.visible: false
                mainContent.enabled: false
            }
            PropertyChanges {
                appWindow.visible: false
            }
            PropertyChanges {
                navBar.visible: false
            }
        },
        State {
            name: "home"
            PropertyChanges {
                lockScreen.visible: false
                lockScreen.enabled: false
                lockScreen.opacity: 0.0
            }
            PropertyChanges {
                pinScreen.visible: false
                pinScreen.enabled: false
            }
            PropertyChanges {
                mainContent.visible: true
                mainContent.enabled: true
            }
            PropertyChanges {
                appWindow.visible: false
            }
            PropertyChanges {
                navBar.visible: true
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
            }
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
                compositor: shell.compositor  // Pass compositor for native app management
                
                onCurrentPageChanged: {
                    Logger.nav("page" + shell.currentPage, "page" + currentPage, "navigation")
                    // If we're on an app grid page (currentPage >= 0), use the internal page
                    if (currentPage >= 0) {
                        shell.currentPage = pageView.internalAppGridPage
                        shell.totalPages = Math.max(1, Math.ceil(AppModel.count / 16))
                    } else {
                        // For Hub (-2) and Task Switcher (-1), use the regular currentPage
                        shell.currentPage = currentPage
                    }
                }
                
                onInternalAppGridPageChanged: {
                    // Update shell's current page when internal app grid page changes
                    if (pageView.currentPage >= 0) {
                        shell.currentPage = pageView.internalAppGridPage
                        Logger.debug("Shell", "Internal app grid page changed to: " + pageView.internalAppGridPage)
                    }
                }
                
                onAppLaunched: (app) => {
                    Logger.info("Shell", "App launched: " + app.name + " (type: " + app.type + ")")
                    
                    if (app.type === "native") {
                        if (compositor) {
                            shell.pendingNativeApp = app
                            
                            // Show splash screen IMMEDIATELY (before surface connects)
                            UIStore.openApp(app.id, app.name, app.icon)
                            appWindow.show(app.id, app.name, app.icon, "native", null, -1)
                            Logger.info("Shell", "Showing splash screen for native app: " + app.name)
                            
                            // Now launch the app (surface will connect later)
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
                                
                                // Show splash screen IMMEDIATELY (before surface connects)
                                UIStore.openApp(app.id, app.name, app.icon)
                                appWindow.show(app.id, app.name, app.icon, "native", null, -1)
                                Logger.info("Shell", "Showing splash screen for native app: " + app.name)
                                
                                // Now launch the app (surface will connect later)
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
                UIStore.minimizeApp()  // Use minimizeApp() instead of closeApp() to preserve app state
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
                    
                    // Check TaskModel for app type - if native, get surface
                    var task = TaskModel.getTaskByAppId(UIStore.currentAppId)
                    if (task && task.appType === "native") {
                        Logger.info("Shell", "Restoring native app from task switcher")
                        if (compositor) {
                            var surface = compositor.getSurfaceById(task.surfaceId)
                            if (surface) {
                                // Pass surface so native app renders correctly
                                appWindow.show(UIStore.currentAppId, UIStore.currentAppName, UIStore.currentAppIcon, "native", surface, task.surfaceId)
                                return
                            } else {
                                Logger.warn("Shell", "Native app surface not found for surfaceId: " + task.surfaceId)
                            }
                        }
                    }
                    
                    // Default: Marathon app or native app fallback
                    appWindow.show(UIStore.currentAppId, UIStore.currentAppName, UIStore.currentAppIcon, "marathon")
                }
            }
            
            function onAppWindowOpenChanged() {
                // Also trigger when appWindowOpen becomes true (covers case where appId hasn't changed)
                if (UIStore.appWindowOpen && UIStore.currentAppId) {
                    Logger.info("Shell", "App window opened, showing: " + UIStore.currentAppId)
                    
                    // Check TaskModel for app type - if native, get surface
                    var task = TaskModel.getTaskByAppId(UIStore.currentAppId)
                    if (task && task.appType === "native") {
                        Logger.info("Shell", "Restoring native app from app window open")
                        if (compositor) {
                            var surface = compositor.getSurfaceById(task.surfaceId)
                            if (surface) {
                                // Pass surface so native app renders correctly
                                appWindow.show(UIStore.currentAppId, UIStore.currentAppName, UIStore.currentAppIcon, "native", surface, task.surfaceId)
                                return
                            } else {
                                Logger.warn("Shell", "Native app surface not found for surfaceId: " + task.surfaceId)
                            }
                        }
                    }
                    
                    // Default: Marathon app or native app fallback
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
            UIStore.openApp("camera", "Camera", "")
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
        
        function onSurfaceCreated(surface, surfaceId, xdgSurface) {
            Logger.info("Shell", "========== onSurfaceCreated HANDLER FIRED ==========")
            Logger.info("Shell", "Native app surface created, surfaceId: " + surfaceId)
            Logger.info("Shell", "pendingNativeApp: " + (shell.pendingNativeApp ? shell.pendingNativeApp.name : "NULL"))
            
            if (shell.pendingNativeApp) {
                var app = shell.pendingNativeApp
                Logger.info("Shell", "Surface connected for: " + app.name + " (surfaceId: " + surfaceId + ")")
                
                // Store xdgSurface and toplevel on surface for NativeAppWindow to access
                surface.xdgSurface = xdgSurface
                surface.toplevel = xdgSurface.toplevel
                
                // Only create a task for the FIRST surface (main window), not for popups/subsurfaces
                // Check if a task already exists for this app
                var existingTask = TaskModel.getTaskByAppId(app.id)
                if (!existingTask) {
                    TaskModel.launchTask(app.id, app.name, app.icon, "native", surfaceId)
                    Logger.info("Shell", "Added native app to TaskModel: " + app.name + " (surfaceId: " + surfaceId + ")")
                } else {
                    Logger.info("Shell", "Native app already has task, skipping (surfaceId: " + surfaceId + " is a subsurface/popup)")
                }
                
                // Update the existing window (already showing splash) with the actual surface
                Logger.info("Shell", "Updating window with connected surface")
                appWindow.show(app.id, app.name, app.icon, "native", surface, surfaceId)
                Logger.info("Shell", "Surface attached to window, splash should hide")
                
                // NOTE: Native apps are not registered with AppLifecycleManager
                // They are managed via the Wayland compositor instead
                // UIStore already handles bringing the window to foreground
                
                shell.pendingNativeApp = null
            }
        }
        
        function onAppClosed(pid) {
            Logger.info("Shell", "Native app process closed, PID: " + pid)
            // The window will close automatically via surfaceDestroyed handler
        }
        
        function onAppLaunched(command, pid) {
            Logger.info("Shell", "Native app process started: " + command + " (PID: " + pid + ")")
        }
        
        function onSurfaceDestroyed(surface, surfaceId) {
            Logger.info("Shell", "Native app surface destroyed, surfaceId: " + surfaceId)
            
            if (UIStore.appWindowOpen && appWindow.appType === "native") {
                if (appWindow.surfaceId === surfaceId) {
                    Logger.info("Shell", "Closing native app window due to surface destruction")
                    UIStore.closeApp()
                    appWindow.hide()
                }
            }
        }
    }
}
