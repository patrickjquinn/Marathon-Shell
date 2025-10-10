import QtQuick
import "./components"
import "./stores"
import "./theme"

Item {
    id: shell
    
    property bool isLocked: true
    property bool showPinScreen: false
    property bool showQuickSettings: false
    property bool showTaskSwitcher: false
    property real quickSettingsHeight: 0
    property int currentPage: 0
    property int totalPages: 1
    
    // State-based navigation
    state: isLocked ? (showPinScreen ? "pinEntry" : "locked") : "unlocked"
    
    states: [
        State {
            name: "locked"
            PropertyChanges { target: lockScreen; visible: true; enabled: true; opacity: 1.0 }
            PropertyChanges { target: pinScreen; visible: false; enabled: false }
            PropertyChanges { target: mainContent; visible: false; enabled: false }
        },
        State {
            name: "pinEntry"
            PropertyChanges { target: lockScreen; visible: false; enabled: false }
            PropertyChanges { target: pinScreen; visible: true; enabled: true }
            PropertyChanges { target: mainContent; visible: false; enabled: false }
        },
        State {
            name: "unlocked"
            PropertyChanges { target: lockScreen; visible: false; enabled: false; opacity: 0.0 }
            PropertyChanges { target: pinScreen; visible: false; enabled: false }
            PropertyChanges { target: mainContent; visible: true; enabled: true }
        }
    ]
    
    transitions: [
        Transition {
            from: "locked"
            to: "unlocked"
            SequentialAnimation {
                NumberAnimation {
                    target: lockScreen
                    property: "opacity"
                    to: 0
                    duration: 300
                }
                PropertyAction {
                    target: lockScreen
                    property: "visible"
                    value: false
                }
                PropertyAction {
                    target: mainContent
                    property: "visible"
                    value: true
                }
            }
        }
    ]
    
    Image {
        anchors.fill: parent
        source: WallpaperStore.path
        fillMode: Image.PreserveAspectCrop
    }
    
    // Debug overlay - tap anywhere to test logging
    MouseArea {
        anchors.fill: parent
        z: -10
        onPressed: console.log("🔴 BACKGROUND PRESSED - LOGGING WORKS!")
        onClicked: console.log("🔴 BACKGROUND CLICKED - LOGGING WORKS!")
    }
    
    // Main home screen content - controlled by State system
    Column {
        id: mainContent
        anchors.fill: parent
        z: 90  // CRITICAL: Must be above dragArea (z: 80) to receive touch events!
        // visible and enabled now controlled by State system
        
        Behavior on opacity {
            NumberAnimation {
                duration: 400
                easing.type: Easing.InCubic
            }
        }
        
        MarathonStatusBar {
            id: statusBar
            width: parent.width
        }
        
        Item {
            width: parent.width
            height: parent.height - statusBar.height - navBar.height
            z: 100
            
            MarathonAppGrid {
                id: appGrid
                anchors.fill: parent
                z: 100
                
                onPageChanged: (page, total) => {
                    currentPage = page
                    totalPages = total
                }
                
                onAppLaunched: (app) => {
                    console.log("============ APP LAUNCHED FROM GRID:", app.name, "============")
                    AppStore.launchApp(app.id)
                    appWindow.show(app.id, app.name, app.icon)
                }
                
                onLongPress: {
                    console.log("Long press - show wallpaper switcher")
                }
            }
            
            Item {
                id: bottomSection
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: messagingHub.height + bottomBar.height
                z: 150
                
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
                }
            }
        }
        
        MarathonNavBar {
            id: navBar
            width: parent.width
            
            onSwipeLeft: console.log("Swipe left")
            onSwipeRight: console.log("Swipe right")
            onShortSwipeUp: {
                showTaskSwitcher = true
                console.log("Short swipe up - show task switcher")
            }
            onLongSwipeUp: {
                showTaskSwitcher = false
                console.log("Long swipe up - go home")
            }
        }
    }
    
    // Task Switcher (Active Frames)
    MarathonTaskSwitcher {
        id: taskSwitcher
        anchors.fill: parent
        visible: showTaskSwitcher && !isLocked
        z: 200
        
        onClosed: {
            showTaskSwitcher = false
        }
        
        onTaskSelected: (task) => {
            console.log("Task selected:", task.name)
            showTaskSwitcher = false
        }
    }
    
    // Peek & Flow - THE signature BlackBerry 10 feature
    MarathonPeek {
        id: peekFlow
        anchors.fill: parent
        visible: !isLocked && !showTaskSwitcher
        z: 250
        
        Component.onCompleted: {
            console.log("🌊 MarathonPeek created. Visible:", visible, "isLocked:", isLocked, "showTaskSwitcher:", showTaskSwitcher)
        }
        
        onVisibleChanged: {
            console.log("🌊 MarathonPeek visibility changed:", visible, "isLocked:", isLocked, "showTaskSwitcher:", showTaskSwitcher)
        }
        
        onClosed: {
            console.log("Peek closed")
        }
        
        onFullyOpened: {
            console.log("Hub fully opened")
        }
    }
    
    // App Window - shows when an app is launched
    MarathonAppWindow {
        id: appWindow
        anchors.fill: parent
        visible: false
        z: 600
        
        onMinimized: {
            console.log("App minimized")
            appWindow.hide()
        }
        
        onClosed: {
            console.log("App closed")
        }
    }
    
    MarathonQuickSettings {
        id: quickSettings
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: quickSettingsHeight
        visible: !isLocked && quickSettingsHeight > 0
        z: 100
        clip: true
        
        Behavior on height {
            NumberAnimation {
                duration: 300
                easing.type: Easing.OutCubic
            }
        }
        
        onClosed: {
            quickSettingsHeight = 0
        }
    }
    
    // Status Bar Drag Area - ONLY 44px tall, only intercepts when dragging DOWN from status bar
    MouseArea {
        id: statusBarDragArea
        anchors.top: parent.top
        anchors.left: parent.left
        width: parent.width
        height: 44  // Only covers status bar, not app grid below!
        z: 92  // ABOVE main content Column (z: 90) to receive touches on status bar
        enabled: !isLocked && !showTaskSwitcher && quickSettingsHeight === 0
        visible: enabled
        preventStealing: false  // Allow other areas to steal if they need to
        
        property real startY: 0
        property bool isDraggingDown: false
        
        onPressed: (mouse) => {
            startY = mouse.y
            isDraggingDown = false
            console.log("📊 Status bar touch started at:", startY)
        }
        
        onPositionChanged: (mouse) => {
            var dragDistance = mouse.y - startY
            console.log("📊 Drag distance:", dragDistance, "mouse.y:", mouse.y, "startY:", startY)
            
            // If dragged down more than 5px, start opening Quick Settings
            if (dragDistance > 5 && !isDraggingDown) {
                isDraggingDown = true
                console.log("📊 Started dragging down!")
            }
            
            if (isDraggingDown) {
                quickSettingsHeight = Math.min(700, dragDistance)
                console.log("📊 Quick Settings height set to:", quickSettingsHeight)
            }
        }
        
        onReleased: (mouse) => {
            console.log("📊 Released. isDraggingDown:", isDraggingDown, "height:", quickSettingsHeight)
            if (isDraggingDown) {
                if (quickSettingsHeight > 350) {
                    quickSettingsHeight = 700
                    console.log("📊 Snapping to fully open: 700")
                } else {
                    quickSettingsHeight = 0
                    console.log("📊 Snapping to closed: 0")
                }
            }
            startY = 0
            isDraggingDown = false
        }
        
        onCanceled: {
            console.log("📊 Touch canceled")
            startY = 0
            isDraggingDown = false
            quickSettingsHeight = 0
        }
    }
    
    // Full-screen overlay when Quick Settings is OPEN - for dragging to close
    MouseArea {
        id: quickSettingsOverlay
        anchors.fill: parent
        z: 95  // Above main content but below Quick Settings
        enabled: quickSettingsHeight > 0 && !isLocked
        visible: enabled
        
        property real startY: 0
        
        onPressed: (mouse) => {
            startY = mouse.y
            console.log("⚙️ Quick Settings overlay drag started")
        }
        
        onPositionChanged: (mouse) => {
            var dragDistance = mouse.y - startY
            var newHeight = quickSettingsHeight + dragDistance
            quickSettingsHeight = Math.max(0, Math.min(700, newHeight))
            startY = mouse.y
        }
        
        onReleased: (mouse) => {
            if (quickSettingsHeight > 350) {
                quickSettingsHeight = 700
            } else {
                quickSettingsHeight = 0
            }
            startY = 0
        }
    }
    
    // Lock Screen - visibility controlled by State system
    MarathonLockScreen {
        id: lockScreen
        anchors.fill: parent
        z: 1000
        // visible and enabled controlled by State system
        
        onUnlockRequested: {
            console.log("🔓 Unlock requested - showing PIN screen")
            showPinScreen = true
            pinScreen.show()
        }
        
        onCameraLaunched: {
            console.log("📷 Camera launched from lock screen")
            // TODO: Launch camera app
        }
        
        onHubOpened: {
            console.log("📨 Hub opened from lock screen")
            // TODO: Open Hub (peek & flow)
        }
    }
    
    // PIN Entry Screen - visibility controlled by State system
    MarathonPinScreen {
        id: pinScreen
        anchors.fill: parent
        z: 1100
        // visible and enabled controlled by State system
        
        onPinCorrect: {
            console.log("✅ PIN verified - unlocking")
            console.log("Before: isLocked:", isLocked, "showPinScreen:", showPinScreen)
            showPinScreen = false
            isLocked = false
            lockScreen.swipeProgress = 0  // Reset progress
            pinScreen.reset()
            console.log("After: isLocked:", isLocked, "showPinScreen:", showPinScreen)
            console.log("Lock screen visible:", lockScreen.visible, "enabled:", lockScreen.enabled)
            console.log("Main Column visible:", !isLocked, "opacity:", isLocked ? lockScreen.swipeProgress : 1.0)
        }
        
        onCancelled: {
            console.log("❌ PIN entry cancelled")
            showPinScreen = false
            lockScreen.swipeProgress = 0
            pinScreen.reset()
        }
    }
    
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            if (showPinScreen) {
                showPinScreen = false
                lockScreen.swipeProgress = 0
                pinScreen.reset()
            } else if (peekFlow.peekProgress > 0) {
                peekFlow.closePeek()
            } else if (showTaskSwitcher) {
                showTaskSwitcher = false
            } else if (quickSettingsHeight > 40) {
                quickSettingsHeight = 40
            } else if (messagingHub.showVertical) {
                messagingHub.showVertical = false
            }
        }
    }
    
    Component.onCompleted: {
        forceActiveFocus()
    }
}



