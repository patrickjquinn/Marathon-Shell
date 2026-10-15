pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

Rectangle {
    id: navBar

    property real startX: 0
    property real startY: 0
    property real currentX: 0
    property real currentY: 0
    property real shortSwipeThreshold: Constants.gestureSwipeShort
    property real longSwipeThreshold: Constants.gestureSwipeLong
    property bool isAppOpen: false
    property real gestureProgress: 0
    property bool keyboardVisible: false
    property bool searchActive: false
    property bool pinScreenMode: false

    // ── Predictive back progress (0..1) ───────────────────────────
    // Drives appWindowContainer scale + opacity in MarathonShell while
    // the user holds + drags LEFT on the nav-bar pill. 0 = idle, 1 =
    // committed (about to fire swipeBack on release). The shell binds
    // this to backExitScaleStart→backExitScaleEnd (1.0 → 0.9) from
    // MMotion via lerp so the foreground page shrinks proportionally
    // to the gesture. On release: commit if >= 0.5 OR strong leftward
    // velocity, otherwise spring back to 0 (cancel = rubber-band).
    property real backProgress: 0
    // Tunable: how far the finger must travel (px) to reach progress=1.
    readonly property real backProgressTravel: width * 0.55

    // Eased settle on cancel only; tracks the finger 1:1 while pressed.
    Behavior on backProgress {
        enabled: !navMouseArea.pressed

        NumberAnimation {
            duration: MMotion.moderate
            easing.type: Easing.OutCubic
        }
    }

    signal swipeLeft
    signal swipeRight
    signal swipeBack
    signal shortSwipeUp
    signal longSwipeUp
    signal minimizeApp(real velocityY)
    signal startPageTransition
    signal toggleKeyboard
    signal toggleSearch

    height: Constants.navBarHeight
    color: Silica.Theme.overlayBackgroundColor

    Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: Constants.borderWidthThin
        color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.1)
    }

    // Shipwright Pilot's bottom-edge notch: a slim highlight pill in a halo
    // of wider, fainter ones.
    Item {
        id: indicator

        property real targetX: parent.width / 2 - width / 2
        property real targetY: parent.height / 2 - height / 2
        property real dragX: navBar.currentX * 0.3
        property real dragY: navBar.currentY * 0.3

        objectName: "navPill"
        width: Silica.Theme.itemSizeExtraLarge
        height: Silica.Theme.paddingSmall
        visible: !navBar.pinScreenMode
        x: targetX + dragX
        y: targetY - dragY

        Repeater {
            model: 3

            Rectangle {
                required property int index
                readonly property real spread: index * Silica.Theme.paddingSmall

                anchors.centerIn: parent
                width: indicator.width * 0.55 + 2 * spread
                height: Silica.Theme.paddingSmall + 2 * spread
                radius: height / 2
                color: Silica.Theme.highlightColor
                opacity: index === 0 ? 0.6 : 0.16 / index
                antialiasing: Constants.enableAntialiasing
            }
        }

        Behavior on x {
            enabled: !navMouseArea.pressed

            NumberAnimation {
                duration: MMotion.moderate
                easing.type: Easing.OutCubic
            }
        }

        Behavior on y {
            enabled: !navMouseArea.pressed

            NumberAnimation {
                duration: MMotion.moderate
                easing.type: Easing.OutCubic
            }
        }
    }

    // Taps on the buttons are read by navMouseArea, so a swipe that starts
    // on one still navigates.
    Item {
        id: searchButton

        objectName: "searchButton"
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(Silica.Theme.itemSizeExtraSmall, Silica.Theme.horizontalPageMargin + Silica.Theme.iconSizeExtraSmall + Silica.Theme.paddingMedium)
        height: parent.height
        visible: !navBar.pinScreenMode
        opacity: navBar.pinScreenMode ? 0 : 1

        // On the page margin, in line with the status bar and the dock.
        GlyphIcon {
            name: "search"
            size: Silica.Theme.iconSizeExtraSmall
            color: navBar.searchActive ? Silica.Theme.highlightColor : Silica.Theme.secondaryColor
            x: Silica.Theme.horizontalPageMargin
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color {
                ColorAnimation {
                    duration: MMotion.quick
                }
            }
        }

        Accessible.role: Accessible.Button
        Accessible.name: "Search"
        Accessible.onPressAction: navBar.toggleSearch()
    }

    Item {
        id: keyboardButton

        objectName: "keyboardButton"
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: searchButton.width
        height: parent.height

        GlyphIcon {
            name: "keyboard"
            size: Silica.Theme.iconSizeExtraSmall
            color: navBar.keyboardVisible ? Silica.Theme.highlightColor : Silica.Theme.secondaryColor
            anchors.right: parent.right
            anchors.rightMargin: Silica.Theme.horizontalPageMargin
            anchors.verticalCenter: parent.verticalCenter

            Behavior on color {
                ColorAnimation {
                    duration: MMotion.quick
                }
            }
        }

        Accessible.role: Accessible.Button
        Accessible.name: "Keyboard"
        Accessible.onPressAction: navBar.toggleKeyboard()
    }

    MouseArea {
        id: navMouseArea

        property real velocityX: 0
        property real velocityY: 0
        property real lastX: 0
        property real lastY: 0
        property real lastTime: 0
        property bool isVerticalGesture: false
        property bool isHorizontalGesture: false
        // Previous-frame cumulative diffY. Lets the QS-drag path compute
        // a per-frame height delta without resetting startY — preserving
        // a true cumulative diffY for isVerticalGesture detection and
        // release-time decisions.
        property real prevDiffY: 0

        anchors.fill: parent
        anchors.topMargin: 0
        z: 200
        function resetGesture() {
            navBar.currentX = 0;
            navBar.currentY = 0;
            navBar.gestureProgress = 0;
            navBar.backProgress = 0;
            navBar.startX = 0;
            navBar.startY = 0;
            velocityX = 0;
            isVerticalGesture = false;
            isHorizontalGesture = false;
            prevDiffY = 0;
        }

        function pressedOn(button) {
            return button.visible && button.contains(button.mapFromItem(navBar, navBar.startX, navBar.startY));
        }

        // A grab stolen mid-drag ends here instead of in onReleased.
        onCanceled: resetGesture()
        onPressed: mouse => {
            navBar.startX = mouse.x;
            navBar.startY = mouse.y;
            lastX = mouse.x;
            lastY = mouse.y;
            lastTime = Date.now();
            velocityX = 0;
            velocityY = 0;
            isVerticalGesture = false;
            isHorizontalGesture = false;
            prevDiffY = 0;
        }
        onPositionChanged: mouse => {
            var now = Date.now();
            var dt = now - lastTime;
            if (dt > 0) {
                velocityX = (mouse.x - lastX) / dt * 1000;
                velocityY = (mouse.y - lastY) / dt * 1000;
            }
            lastX = mouse.x;
            lastY = mouse.y;
            lastTime = now;
            var diffX = mouse.x - navBar.startX;
            var diffY = navBar.startY - mouse.y;
            // Lock the axis once; a thumb arcs upward during a back swipe.
            if (!isVerticalGesture && !isHorizontalGesture && Math.max(Math.abs(diffX), Math.abs(diffY)) > 10) {
                if (Math.abs(diffY) > Math.abs(diffX))
                    isVerticalGesture = true;
                else
                    isHorizontalGesture = true;
            }
            if (isVerticalGesture) {
                navBar.currentY = diffY;
                navBar.currentX = 0;
                if (UIStore.quickSettingsOpen || UIStore.quickSettingsHeight > 0) {
                    if (!UIStore.quickSettingsDragging)
                        UIStore.quickSettingsDragging = true;

                    // Per-frame height delta — startY is left alone so
                    // diffY stays cumulative for the release decision.
                    var frameDeltaY = diffY - prevDiffY;
                    prevDiffY = diffY;
                    var newHeight = UIStore.quickSettingsHeight - frameDeltaY;
                    // shellRef is plain QObject* in C++; `as MarathonShell`
                    // returns null because MarathonShell is a QML composite
                    // with no class. Duck-type the property access — qmllint
                    // will flag it as missing-property, but it resolves at
                    // runtime.
                    var maxHeight = UIStore.shellRef ? UIStore.shellRef.maxQuickSettingsHeight : 1000; // qmllint disable missing-property
                    UIStore.quickSettingsHeight = Math.max(0, Math.min(maxHeight, newHeight));
                } else if (navBar.isAppOpen && diffY > 0) {
                    var oldProgress = navBar.gestureProgress;
                    var progressThreshold = Constants.screenHeight * 0.25;
                    navBar.gestureProgress = Math.min(1, diffY / progressThreshold);
                    if (oldProgress <= 0.15 && navBar.gestureProgress > 0.15)
                        navBar.startPageTransition();
                }
            } else {
                navBar.currentX = diffX;
                navBar.currentY = 0;
                navBar.gestureProgress = 0;
                // Predictive back — only when an app is open and
                // user is dragging LEFT (diffX < 0). Progress is
                // the leftward distance normalised against backProgressTravel,
                // clamped to [0, 1]. The shell listens to backProgress
                // and shrinks appWindowContainer toward backExitScaleEnd.
                if (navBar.isAppOpen && diffX < 0) {
                    navBar.backProgress = Math.min(1, -diffX / Math.max(1, navBar.backProgressTravel));
                } else if (navBar.backProgress !== 0) {
                    navBar.backProgress = 0;
                }
            }
        }
        onReleased: mouse => {
            var diffX = mouse.x - navBar.startX;
            var diffY = navBar.startY - mouse.y;
            Logger.gesture("NavBar", "released", {
                "diffX": diffX,
                "diffY": diffY,
                "velocity": velocityX,
                "isAppOpen": navBar.isAppOpen,
                "quickSettingsOpen": UIStore.quickSettingsOpen
            });
            if (!isVerticalGesture && !isHorizontalGesture) {
                if (pressedOn(searchButton)) {
                    HapticManager.light();
                    navBar.toggleSearch();
                } else if (pressedOn(keyboardButton)) {
                    HapticManager.light();
                    navBar.toggleKeyboard();
                }
            }
            if ((UIStore.quickSettingsOpen || UIStore.quickSettingsHeight > 0) && isVerticalGesture) {
                Logger.info("NavBar", "Quick Settings height: " + UIStore.quickSettingsHeight + ", diffY: " + diffY);
                UIStore.quickSettingsDragging = false;
                var threshold = UIStore.shellRef ? UIStore.shellRef.quickSettingsThreshold : 400; // qmllint disable missing-property
                // Dismiss on any of: upward fling (velocity < -500), drag
                // pulled the panel below threshold, or a deliberate upward
                // swipe of ≥40 px while QS is open (the documented
                // swipe-up-from-nav dismissal).
                var isFlingUp = velocityY < -500;
                var isDeliberateSwipeUp = UIStore.quickSettingsOpen && diffY > 40;
                if (isFlingUp || isDeliberateSwipeUp || UIStore.quickSettingsHeight < threshold)
                    UIStore.closeQuickSettings();
                else
                    UIStore.openQuickSettings();
                Logger.gesture("NavBar", "Quick Settings gesture end", {
                    "height": UIStore.quickSettingsHeight,
                    "diffY": diffY,
                    "velocityY": velocityY,
                    "flingUp": isFlingUp,
                    "deliberateUp": isDeliberateSwipeUp
                });
                navBar.startX = 0;
                navBar.startY = 0;
                velocityX = 0;
                velocityY = 0;
                isVerticalGesture = false;
                prevDiffY = 0;
                navBar.currentX = 0;
                navBar.currentY = 0;
                navBar.gestureProgress = 0;
                return;
            }
            // Pull down on the pill: quick settings. The bar sits at the
            // screen edge, so any locked downward drag commits.
            if (isVerticalGesture && diffY < 0) {
                if (!navBar.pinScreenMode && !SessionStore.isLocked)
                    UIStore.openQuickSettings();
                resetGesture();
                return;
            }
            if (UIStore.searchOpen && isVerticalGesture && diffY > 60) {
                Logger.info("NavBar", "Closing Search with upward gesture");
                UIStore.closeSearch();
                navBar.startX = 0;
                navBar.startY = 0;
                velocityX = 0;
                isVerticalGesture = false;
                navBar.currentX = 0;
                navBar.currentY = 0;
                navBar.gestureProgress = 0;
                return;
            }
            if (isVerticalGesture && diffY > 30 && !UIStore.searchOpen) {
                if (diffY > navBar.longSwipeThreshold) {
                    Logger.info("NavBar", " LONG SWIPE UP TRIGGERED ");
                    Logger.info("NavBar", "  diffY: " + diffY + ", longSwipeThreshold: " + navBar.longSwipeThreshold);
                    Logger.info("NavBar", "  isAppOpen: " + navBar.isAppOpen);
                    Logger.info("NavBar", "  UIStore.appWindowOpen: " + UIStore.appWindowOpen);
                    Logger.info("NavBar", "  UIStore.settingsOpen: " + UIStore.settingsOpen);
                    navBar.longSwipeUp();
                    navBar.currentX = 0;
                    navBar.currentY = 0;
                    navBar.gestureProgress = 0;
                } else if (navBar.isAppOpen && (diffY > 100 || navBar.gestureProgress > 0.4)) {
                    Logger.info("NavBar", "⬆⬆⬆ MINIMIZE GESTURE TRIGGERED ⬆⬆⬆");
                    Logger.info("NavBar", "  diffY: " + diffY + ", gestureProgress: " + navBar.gestureProgress);
                    Logger.info("NavBar", "  isAppOpen: " + navBar.isAppOpen);
                    Logger.info("NavBar", "  UIStore.appWindowOpen: " + UIStore.appWindowOpen);
                    Logger.info("NavBar", "  UIStore.settingsOpen: " + UIStore.settingsOpen);
                    navBar.minimizeApp(velocityY);
                    navBar.currentX = 0;
                    navBar.currentY = 0;
                    navBar.gestureProgress = 0;
                } else if (diffY > navBar.shortSwipeThreshold) {
                    Logger.info("NavBar", "Short swipe up - Go home");
                    navBar.shortSwipeUp();
                    navBar.currentX = 0;
                    navBar.currentY = 0;
                    navBar.gestureProgress = 0;
                }
            } else if (!isVerticalGesture && (Math.abs(diffX) > 50 || Math.abs(velocityX) > 500)) {
                if (diffX < 0 || velocityX < 0) {
                    Logger.gesture("NavBar", "swipeLeft", {
                        "velocity": velocityX,
                        "isAppOpen": navBar.isAppOpen,
                        "backProgress": navBar.backProgress
                    });
                    if (navBar.isAppOpen)
                        navBar.swipeBack();
                    else
                        navBar.swipeLeft();
                } else {
                    Logger.gesture("NavBar", "swipeRight", {
                        "velocity": velocityX,
                        "isAppOpen": navBar.isAppOpen,
                        "diffX": diffX
                    });
                    navBar.swipeRight();
                }
                navBar.currentX = 0;
                navBar.currentY = 0;
                navBar.gestureProgress = 0;
                // commit — shell pop transition takes over from here.
                navBar.backProgress = 0;
            } else {
                Logger.info("NavBar", " GESTURE CANCELLED - diffX: " + diffX + ", diffY: " + diffY);
                navBar.currentX = 0;
                navBar.currentY = 0;
                navBar.gestureProgress = 0;
                // cancel — Behavior spring-snaps backProgress to 0.
                navBar.backProgress = 0;
            }
            // Unconditional — the branch chain above has non-resetting gaps.
            resetGesture();
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

        NumberAnimation {
            duration: MMotion.moderate
            easing.type: Easing.OutCubic
        }
    }
}
