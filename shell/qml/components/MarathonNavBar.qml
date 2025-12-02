import QtQuick
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Theme

Rectangle {
    id: navBar
    height: Constants.navBarHeight
    color: MColors.background

    Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: Constants.borderWidthThin
        color: MColors.border
    }

    signal swipeLeft
    signal swipeRight
    signal swipeBack
    signal shortSwipeUp
    signal longSwipeUp
    signal minimizeApp
    signal startPageTransition
    signal toggleKeyboard
    signal toggleSearch

    property real startX: 0
    property real startY: 0
    property real currentX: 0
    property real currentY: 0
    property real shortSwipeThreshold: Constants.gestureSwipeShort
    property real longSwipeThreshold: Constants.gestureSwipeLong

    Rectangle {
        id: indicator
        width: Constants.cardBannerHeight
        height: Constants.spacingXSmall
        radius: Constants.borderRadiusSharp
        color: MColors.text
        opacity: pinScreenMode ? 0.0 : 0.9  // Hide in PIN screen mode
        visible: !pinScreenMode
        antialiasing: Constants.enableAntialiasing

        property real targetX: parent.width / 2 - width / 2
        property real targetY: parent.height / 2 - height / 2
        property real dragX: currentX * 0.3
        property real dragY: currentY * 0.3

        x: targetX + dragX
        y: targetY - dragY

        Behavior on x {
            enabled: !navMouseArea.pressed
            SpringAnimation {
                spring: 3
                damping: 0.3
                epsilon: 0.25
            }
        }

        Behavior on y {
            enabled: !navMouseArea.pressed
            SpringAnimation {
                spring: 3
                damping: 0.3
                epsilon: 0.25
            }
        }
    }

    property bool isAppOpen: false
    property real gestureProgress: 0
    property bool keyboardVisible: false
    property bool searchActive: false
    property bool pinScreenMode: false  // When true, hide pill and search button

    // Search button (small, bottom left of nav bar)
    Item {
        id: searchButton
        anchors.left: parent.left
        anchors.leftMargin: MSpacing.sm
        anchors.verticalCenter: parent.verticalCenter
        width: 16
        height: 16
        z: 300
        visible: !pinScreenMode  // Hide in PIN screen mode
        opacity: pinScreenMode ? 0.0 : 1.0

        Rectangle {
            anchors.fill: parent
            radius: MRadius.sm
            color: navBar.searchActive ? MColors.accent : MColors.surface
            opacity: navBar.searchActive ? 0.3 : 0.15

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }
        }

        Icon {
            name: "search"
            size: 12
            color: navBar.searchActive ? MColors.accentBright : MColors.text
            anchors.centerIn: parent
            opacity: navBar.searchActive ? 1.0 : 0.6

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }

            Behavior on color {
                ColorAnimation {
                    duration: 150
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            onClicked: {
                HapticService.light();
                navBar.toggleSearch();
            }
        }
    }

    // Keyboard button (small, bottom right of nav bar)
    Item {
        id: keyboardButton
        anchors.right: parent.right
        anchors.rightMargin: MSpacing.sm
        anchors.verticalCenter: parent.verticalCenter
        width: 16
        height: 16
        z: 300

        Rectangle {
            anchors.fill: parent
            radius: MRadius.sm
            color: navBar.keyboardVisible ? MColors.accent : MColors.surface
            opacity: navBar.keyboardVisible ? 0.3 : 0.15

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }
        }

        Icon {
            name: "keyboard"
            size: 12
            color: navBar.keyboardVisible ? MColors.accentBright : MColors.text
            anchors.centerIn: parent
            opacity: navBar.keyboardVisible ? 1.0 : 0.6

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }

            Behavior on color {
                ColorAnimation {
                    duration: 150
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            onClicked: {
                HapticService.light();
                navBar.toggleKeyboard();
            }
        }
    }

    MouseArea {
        id: navMouseArea
        anchors.fill: parent
        anchors.topMargin: 0
        z: 200

        property real velocityX: 0
        property real velocityY: 0
        property real lastX: 0
        property real lastY: 0
        property real lastTime: 0
        property bool isVerticalGesture: false
        property bool isLeftZone: false
        property bool isRightZone: false

        onPressed: mouse => {
            startX = mouse.x;
            startY = mouse.y;
            lastX = mouse.x;
            lastY = mouse.y;
            lastTime = Date.now();
            velocityX = 0;
            velocityY = 0;
            isVerticalGesture = false;

            // Detect if press is in left or right zone (narrower zones, more centered on buttons)
            var leftBoundary = parent.width * 0.15;  // Left 15% for search button
            var rightBoundary = parent.width * 0.85;  // Right 15% for keyboard button
            isLeftZone = !pinScreenMode && mouse.x < leftBoundary;  // Left zone disabled in PIN mode (no search)
            isRightZone = mouse.x > rightBoundary;  // Right zone (keyboard) always enabled

            if (isLeftZone) {
                Logger.info("NavBar", "🔵 Touch in LEFT ZONE (x=" + mouse.x + ")");
            } else if (isRightZone) {
                Logger.info("NavBar", "🔴 Touch in RIGHT ZONE (keyboard) (x=" + mouse.x + ", pinScreenMode=" + pinScreenMode + ")");
            }
        }

        onPositionChanged: mouse => {
            var now = Date.now();
            var dt = now - lastTime;
            if (dt > 0) {
                velocityX = (mouse.x - lastX) / dt * 1000;
                velocityY = (mouse.y - lastY) / dt * 1000;  // Positive = downward, negative = upward (standard)
            }
            lastX = mouse.x;
            lastY = mouse.y;
            lastTime = now;

            var diffX = mouse.x - startX;
            var diffY = startY - mouse.y;

            if (Math.abs(diffY) > Math.abs(diffX) && Math.abs(diffY) > 10) {
                if (!isVerticalGesture) {}
                isVerticalGesture = true;
            }

            if (isVerticalGesture) {
                currentY = Math.max(0, diffY);
                currentX = 0;

                // Drag Quick Settings up when open
                if (UIStore.quickSettingsOpen || UIStore.quickSettingsHeight > 0) {
                    if (!UIStore.quickSettingsDragging) {
                        UIStore.quickSettingsDragging = true;
                    }
                    var newHeight = UIStore.quickSettingsHeight - diffY;
                    var maxHeight = UIStore.shellRef ? UIStore.shellRef.maxQuickSettingsHeight : 1000;
                    UIStore.quickSettingsHeight = Math.max(0, Math.min(maxHeight, newHeight));
                    startY = mouse.y;  // Update startY for continuous tracking
                } else if (isAppOpen) {
                    var oldProgress = gestureProgress;
                    // Density-aware progress: 25% of screen height = 100% progress
                    var progressThreshold = Constants.screenHeight * 0.25;
                    gestureProgress = Math.min(1.0, diffY / progressThreshold);
                    if (oldProgress <= 0.15 && gestureProgress > 0.15) {
                        startPageTransition();
                    }
                }
            } else {
                currentX = diffX;
                currentY = 0;
                gestureProgress = 0;
            }
        }

        onReleased: mouse => {
            var diffX = mouse.x - startX;
            var diffY = startY - mouse.y;

            Logger.gesture("NavBar", "released", {
                diffX: diffX,
                diffY: diffY,
                velocity: velocityX,
                isAppOpen: isAppOpen,
                quickSettingsOpen: UIStore.quickSettingsOpen
            });

            // Check for left/right zone swipe-up quick actions
            if ((isLeftZone || isRightZone) && diffY > 50) {
                if (isLeftZone) {
                    Logger.info("NavBar", "🔵 LEFT ZONE SWIPE-UP → Toggle Search (diffY: " + diffY + ")");
                    HapticService.medium();
                    navBar.toggleSearch();
                } else if (isRightZone) {
                    Logger.info("NavBar", "🔴 RIGHT ZONE SWIPE-UP → Toggle Keyboard (diffY: " + diffY + ")");
                    HapticService.medium();
                    navBar.toggleKeyboard();
                }
                // Reset state and return
                startX = 0;
                startY = 0;
                currentX = 0;
                currentY = 0;
                velocityX = 0;
                velocityY = 0;
                isVerticalGesture = false;
                isLeftZone = false;
                isRightZone = false;
                gestureProgress = 0;
                return;
            }

            // Snap Quick Settings open/closed based on threshold or velocity
            if ((UIStore.quickSettingsOpen || UIStore.quickSettingsHeight > 0) && isVerticalGesture) {
                Logger.info("NavBar", "Quick Settings height: " + UIStore.quickSettingsHeight + ", diffY: " + diffY);
                UIStore.quickSettingsDragging = false;
                var threshold = UIStore.shellRef ? UIStore.shellRef.quickSettingsThreshold : 400;

                // Check for fling up gesture (velocity < -500 px/s = upward swipe, closing)
                var isFlingUp = velocityY < -500;

                if (isFlingUp || UIStore.quickSettingsHeight < threshold) {
                    UIStore.closeQuickSettings();
                } else {
                    UIStore.openQuickSettings();
                }
                Logger.gesture("NavBar", "Quick Settings gesture end", {
                    height: UIStore.quickSettingsHeight,
                    velocityY: velocityY,
                    flingUp: isFlingUp
                });

                // Reset gesture state
                startX = 0;
                startY = 0;
                velocityX = 0;
                velocityY = 0;
                isVerticalGesture = false;
                isVerticalGesture = false;
                currentX = 0;
                currentY = 0;
                gestureProgress = 0;
                return;
            }

            // Close Search with upward gesture - ONLY close search, don't navigate
            if (UIStore.searchOpen && isVerticalGesture && diffY > 60) {
                Logger.info("NavBar", "Closing Search with upward gesture");
                UIStore.closeSearch();
                // Reset all state and RETURN to prevent further navigation
                startX = 0;
                startY = 0;
                velocityX = 0;
                isVerticalGesture = false;
                currentX = 0;
                currentY = 0;
                gestureProgress = 0;
                return;
            }

            // Only process navigation gestures if search is NOT open
            if (isVerticalGesture && diffY > 30 && !UIStore.searchOpen) {
                if (diffY > longSwipeThreshold) {
                    // Long swipe up - Always go to task switcher
                    Logger.info("NavBar", " LONG SWIPE UP TRIGGERED ");
                    Logger.info("NavBar", "  diffY: " + diffY + ", longSwipeThreshold: " + longSwipeThreshold);
                    Logger.info("NavBar", "  isAppOpen: " + isAppOpen);
                    Logger.info("NavBar", "  UIStore.appWindowOpen: " + UIStore.appWindowOpen);
                    Logger.info("NavBar", "  UIStore.settingsOpen: " + UIStore.settingsOpen);
                    longSwipeUp();
                    currentX = 0;
                    currentY = 0;
                    gestureProgress = 0;
                } else if (isAppOpen && (diffY > 100 || gestureProgress > 0.4)) {
                    // Short swipe up while app is open - Minimize app
                    Logger.info("NavBar", "⬆⬆⬆ MINIMIZE GESTURE TRIGGERED ⬆⬆⬆");
                    Logger.info("NavBar", "  diffY: " + diffY + ", gestureProgress: " + gestureProgress);
                    Logger.info("NavBar", "  isAppOpen: " + isAppOpen);
                    Logger.info("NavBar", "  UIStore.appWindowOpen: " + UIStore.appWindowOpen);
                    Logger.info("NavBar", "  UIStore.settingsOpen: " + UIStore.settingsOpen);
                    // Pass negative velocityY (upward is negative in Qt coordinate system usually, but here diffY is positive up)
                    // Wait, velocityY calculation: velocityY = (mouse.y - lastY) / dt * 1000;
                    // If moving UP, mouse.y decreases, so velocityY is NEGATIVE.
                    minimizeApp(velocityY);
                    gestureProgressResetTimer.start();
                } else if (diffY > shortSwipeThreshold) {
                    // Short swipe up - Go home
                    Logger.info("NavBar", "Short swipe up - Go home");
                    shortSwipeUp();
                    currentX = 0;
                    currentY = 0;
                    gestureProgress = 0;
                }
            } else if (!isVerticalGesture && (Math.abs(diffX) > 50 || Math.abs(velocityX) > 500)) {
                if (diffX < 0 || velocityX < 0) {
                    Logger.gesture("NavBar", "swipeLeft", {
                        velocity: velocityX,
                        isAppOpen: isAppOpen
                    });
                    if (isAppOpen) {
                        // When app is open, swipe left = back gesture
                        swipeBack();
                    } else {
                        // Otherwise, navigate pages left
                        swipeLeft();
                    }
                } else {
                    Logger.gesture("NavBar", "swipeRight", {
                        velocity: velocityX,
                        isAppOpen: isAppOpen,
                        diffX: diffX
                    });
                    swipeRight();
                }
                currentX = 0;
                currentY = 0;
                gestureProgress = 0;
            } else {
                // Cancelled gesture - reset immediately
                Logger.info("NavBar", " GESTURE CANCELLED - diffX: " + diffX + ", diffY: " + diffY);
                currentX = 0;
                currentY = 0;
                gestureProgress = 0;
            }

            startX = 0;
            startY = 0;
            velocityX = 0;
            isVerticalGesture = false;
            isLeftZone = false;
            isRightZone = false;
        }
    }

    Timer {
        id: gestureProgressResetTimer
        interval: 300
        onTriggered: {
            Logger.info("NavBar", "⏱ GESTURE PROGRESS RESET");
            navBar.gestureProgress = 0;
            navBar.currentX = 0;
            navBar.currentY = 0;
        }
    }

    Behavior on gestureProgress {
        enabled: !navMouseArea.pressed && !gestureProgressResetTimer.running
        SpringAnimation {
            spring: 2.5
            damping: 0.5
            epsilon: 0.01
        }
    }
}
