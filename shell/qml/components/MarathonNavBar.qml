pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

Rectangle {
    id: navBar

    property real startX: 0
    property real startY: 0
    property real shortSwipeThreshold: Constants.gestureSwipeShort
    property real longSwipeThreshold: Constants.gestureSwipeLong
    property bool isAppOpen: false
    // Swipe up on an app: 0..1 over a quarter screen, the minimise path's input.
    readonly property real gestureProgress: minimizeDrag.progress
    readonly property GestureTracker minimizeTracker: minimizeDrag
    // The finger's sideways travel (px) during a swipe up on an app.
    property real minimizeThumbX: 0
    property bool keyboardVisible: false
    property bool searchActive: false
    property bool pinScreenMode: false
    // Touch and hold asks Shipwright Pilot (pilotRequested) while true.
    property bool pilotEnabled: false
    // Held still: lit, and the charge rises until Pilot is asked.
    property bool pilotLit: false
    property real pilotCharge: 0

    // Back: the pill's leftward travel with an app open, in px (backTracker)
    // and 0..1 over backProgressTravel. The shell draws the app aside by it.
    readonly property real backProgress: backDrag.progress
    readonly property GestureTracker backTracker: backDrag
    readonly property real backProgressTravel: width * 0.55

    signal swipeLeft
    signal swipeRight
    signal swipeBack
    signal shortSwipeUp
    signal longSwipeUp
    signal minimizeApp(real velocityY)
    signal startPageTransition
    signal toggleKeyboard
    signal toggleSearch
    signal pilotRequested

    height: Constants.navBarHeight
    color: Silica.Theme.overlayBackgroundColor

    Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: Constants.borderWidthThin
        color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.1)
    }

    // Shipwright Pilot's bottom-edge notch: a slim highlight pill in a halo
    // of wider, fainter ones, which brightens and widens while held.
    Item {
        id: indicator

        property real targetX: parent.width / 2 - width / 2
        property real targetY: parent.height / 2 - height / 2
        property real dragX: pillX.value * 0.3
        property real dragY: pillY.value * 0.3

        objectName: "navPill"
        width: Silica.Theme.itemSizeExtraLarge
        height: Silica.Theme.paddingSmall
        visible: !navBar.pinScreenMode
        x: targetX + dragX
        y: targetY - dragY

        // Light rising above the thumb that covers the pill.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.verticalCenter
            anchors.bottomMargin: -navBar.height / 2
            width: Silica.Theme.itemSizeHuge * 1.8
            height: Silica.Theme.itemSizeExtraLarge * 1.6
            radius: width / 2
            visible: navBar.pilotCharge > 0
            opacity: navBar.pilotCharge
            scale: 0.6 + 0.4 * navBar.pilotCharge
            transformOrigin: Item.Bottom
            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: Silica.Theme.rgba(Silica.Theme.highlightColor, 0.0)
                }
                GradientStop {
                    position: 0.55
                    color: Silica.Theme.rgba(Silica.Theme.highlightColor, 0.18)
                }
                GradientStop {
                    position: 1.0
                    color: Silica.Theme.rgba(Silica.Theme.highlightColor, 0.55)
                }
            }
        }

        Repeater {
            model: 3

            Rectangle {
                required property int index
                readonly property real spread: index * Silica.Theme.paddingSmall * (navBar.pilotLit ? 1.6 : 1)

                anchors.centerIn: parent
                width: indicator.width * (navBar.pilotLit ? 0.75 : 0.55) + 2 * spread
                height: Silica.Theme.paddingSmall + 2 * spread
                radius: height / 2
                color: Silica.Theme.highlightColor
                opacity: (index === 0 ? 0.6 : 0.16 / index) * (navBar.pilotLit ? 1.6 : 1)
                antialiasing: Constants.enableAntialiasing

                Behavior on width {
                    NumberAnimation {
                        duration: MMotion.quick
                        easing.type: MMotion.easingFor("tap")
                    }
                }
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
                    easing.type: MMotion.easingFor("hover")
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
                    easing.type: MMotion.easingFor("hover")
                }
            }
        }

        Accessible.role: Accessible.Button
        Accessible.name: "Keyboard"
        Accessible.onPressAction: navBar.toggleKeyboard()
    }

    MouseArea {
        id: navMouseArea

        property bool isVerticalGesture: false
        property bool isHorizontalGesture: false
        // Previous-frame cumulative diffY. Lets the QS-drag path compute
        // a per-frame height delta without resetting startY — preserving
        // a true cumulative diffY for isVerticalGesture detection and
        // release-time decisions.
        property real prevDiffY: 0
        // The hold asked Pilot: the rest of this touch does nothing.
        property bool pilotAsked: false
        // Where an interrupted settle was caught, so the press picks it up.
        property real pillBaseX: 0
        property real pillBaseY: 0
        property real backBase: 0
        property real minimizeBase: 0
        // The pull down from the pill drives the quick settings shade.
        property bool pullingQuickSettings: false

        anchors.fill: parent
        anchors.topMargin: 0
        z: 200
        // keepBack: swipeBack went out, and the shell owns the back settle.
        function resetGesture(keepBack) {
            pillX.settleTo(0);
            pillY.settleTo(0);
            minimizeDrag.settleTo(0);
            if (!keepBack)
                backDrag.settleTo(0);
            if (pullingQuickSettings) {
                pullingQuickSettings = false;
                UIStore.quickSettingsDragging = false;
                UIStore.closeQuickSettings();
            }
            navBar.startX = 0;
            navBar.startY = 0;
            navBar.minimizeThumbX = 0;
            isVerticalGesture = false;
            isHorizontalGesture = false;
            prevDiffY = 0;
            stopPilot();
        }

        function stopPilot() {
            pilotAsked = false;
            pilotStill.stop();
            pilotCharging.stop();
            navBar.pilotLit = false;
            navBar.pilotCharge = 0;
        }

        function pressedOn(button) {
            return button.visible && button.contains(button.mapFromItem(navBar, navBar.startX, navBar.startY));
        }

        // A grab stolen mid-drag ends here instead of in onReleased.
        onCanceled: resetGesture(false)
        onPressed: mouse => {
            navBar.startX = mouse.x;
            navBar.startY = mouse.y;
            pillX.press();
            pillY.press();
            backDrag.press();
            minimizeDrag.press();
            pillBaseX = pillX.value;
            pillBaseY = pillY.value;
            backBase = backDrag.value;
            minimizeBase = minimizeDrag.value;
            isVerticalGesture = false;
            isHorizontalGesture = false;
            pullingQuickSettings = false;
            prevDiffY = 0;
            stopPilot();
            if (navBar.pilotEnabled && !pressedOn(searchButton) && !pressedOn(keyboardButton))
                pilotStill.restart();
        }
        onPositionChanged: mouse => {
            if (pilotAsked)
                return;
            var diffX = mouse.x - navBar.startX;
            var diffY = navBar.startY - mouse.y;
            // Lock the axis once; a thumb arcs upward during a back swipe.
            if (!isVerticalGesture && !isHorizontalGesture && Math.max(Math.abs(diffX), Math.abs(diffY)) > 10) {
                if (Math.abs(diffY) > Math.abs(diffX)) {
                    isVerticalGesture = true;
                    pillX.settleTo(0);
                    backDrag.settleTo(0);
                } else {
                    isHorizontalGesture = true;
                    pillY.settleTo(0);
                    minimizeDrag.settleTo(0);
                }
                stopPilot();
            }
            if (!isHorizontalGesture)
                pillY.move(pillBaseY + diffY);
            if (!isVerticalGesture)
                pillX.move(pillBaseX + diffX);
            if (isVerticalGesture) {
                if (UIStore.quickSettingsOpen || (UIStore.quickSettingsHeight > 0 && !pullingQuickSettings)) {
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
                } else if (pullingQuickSettings || (diffY < 0 && !navBar.pinScreenMode && !SessionStore.isLocked)) {
                    // The bar sits at the screen edge with only its own
                    // height to travel, so the shade follows at a gain:
                    // fully open at 40 % of the bar.
                    pullingQuickSettings = true;
                    UIStore.quickSettingsDragging = true;
                    var shadeMax = UIStore.shellRef ? UIStore.shellRef.maxQuickSettingsHeight : 1000; // qmllint disable missing-property
                    UIStore.quickSettingsHeight = shadeMax * Math.max(0, Math.min(1, -diffY / Math.max(1, navBar.height * 0.4)));
                } else if (navBar.isAppOpen) {
                    var oldProgress = navBar.gestureProgress;
                    navBar.minimizeThumbX = diffX;
                    minimizeDrag.move(Math.max(0, minimizeBase + diffY));
                    if (oldProgress <= 0.15 && navBar.gestureProgress > 0.15)
                        navBar.startPageTransition();
                }
            } else if (navBar.isAppOpen) {
                backDrag.move(Math.max(0, backBase - diffX));
            }
        }
        onReleased: mouse => {
            if (pilotAsked) {
                resetGesture(false);
                return;
            }
            stopPilot();
            var diffX = mouse.x - navBar.startX;
            var diffY = navBar.startY - mouse.y;
            pillX.release();
            pillY.release();
            var horizontalCommit = pillX.decide(Math.abs(diffX), pillX.velocity * Math.sign(diffX));
            var backCommit = backDrag.release();
            var minimizeCommit = minimizeDrag.release();
            // px/s, up and right positive.
            var velocityX = pillX.velocity;
            var velocityUp = pillY.velocity;
            var projectedUp = diffY + velocityUp * 0.1;
            Logger.gesture("NavBar", "released", {
                "diffX": diffX,
                "diffY": diffY,
                "velocityX": velocityX,
                "velocityUp": velocityUp,
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
            if (pullingQuickSettings) {
                pullingQuickSettings = false;
                UIStore.quickSettingsDragging = false;
                // Any locked pull opens, unless the finger came back up.
                if (-projectedUp > 10)
                    UIStore.openQuickSettings();
                else
                    UIStore.closeQuickSettings();
                resetGesture(false);
                return;
            }
            if ((UIStore.quickSettingsOpen || UIStore.quickSettingsHeight > 0) && isVerticalGesture) {
                UIStore.quickSettingsDragging = false;
                var threshold = UIStore.shellRef ? UIStore.shellRef.quickSettingsThreshold : 400; // qmllint disable missing-property
                // Dismiss on any of: upward fling, drag pulled the panel
                // below threshold, or a deliberate upward swipe of ≥40 px
                // while QS is open (the documented swipe-up-from-nav
                // dismissal).
                var isFlingUp = velocityUp > 500;
                var isDeliberateSwipeUp = UIStore.quickSettingsOpen && diffY > 40;
                if (isFlingUp || isDeliberateSwipeUp || UIStore.quickSettingsHeight < threshold)
                    UIStore.closeQuickSettings();
                else
                    UIStore.openQuickSettings();
                Logger.gesture("NavBar", "Quick Settings gesture end", {
                    "height": UIStore.quickSettingsHeight,
                    "diffY": diffY,
                    "velocityUp": velocityUp,
                    "flingUp": isFlingUp,
                    "deliberateUp": isDeliberateSwipeUp
                });
                resetGesture(false);
                return;
            }
            if (UIStore.searchOpen && isVerticalGesture && diffY > 60) {
                Logger.info("NavBar", "Closing Search with upward gesture");
                UIStore.closeSearch();
                resetGesture(false);
                return;
            }
            if (isVerticalGesture && diffY > 30 && !UIStore.searchOpen) {
                if (projectedUp > navBar.longSwipeThreshold && (!navBar.isAppOpen || minimizeCommit)) {
                    Logger.info("NavBar", "Long swipe up, isAppOpen: " + navBar.isAppOpen);
                    navBar.longSwipeUp();
                    minimizeDrag.value = 0;
                } else if (navBar.isAppOpen && minimizeCommit) {
                    Logger.info("NavBar", "Minimise, diffY: " + diffY + ", velocityUp: " + velocityUp);
                    navBar.minimizeApp(-velocityUp);
                    minimizeDrag.value = 0;
                } else if (projectedUp > navBar.shortSwipeThreshold) {
                    Logger.info("NavBar", "Short swipe up - Go home");
                    navBar.shortSwipeUp();
                }
            } else if (isHorizontalGesture && navBar.isAppOpen && diffX < 0) {
                // The shell may hold the app where it is (back out of the
                // app), so the settle starts before swipeBack is sent.
                backDrag.settleTo(0);
                if (backCommit) {
                    Logger.gesture("NavBar", "swipeBack", {
                        "velocityX": velocityX,
                        "backProgress": navBar.backProgress
                    });
                    navBar.swipeBack();
                }
                resetGesture(true);
                return;
            } else if (isHorizontalGesture && horizontalCommit) {
                if (diffX < 0) {
                    navBar.swipeLeft();
                } else {
                    Logger.gesture("NavBar", "swipeRight", {
                        "velocityX": velocityX,
                        "isAppOpen": navBar.isAppOpen,
                        "diffX": diffX
                    });
                    navBar.swipeRight();
                }
            }
            resetGesture(false);
        }
    }

    GestureTracker {
        id: pillX

        commitDistance: 50
        settleDuration: MMotion.reduceMotion ? MMotion.micro : MMotion.moderate
    }

    GestureTracker {
        id: pillY

        settleDuration: MMotion.reduceMotion ? MMotion.micro : MMotion.moderate
    }

    GestureTracker {
        id: backDrag

        to: navBar.backProgressTravel
        commitDistance: Silica.Theme.itemSizeMedium
        settleDuration: MMotion.reduceMotion ? MMotion.micro : MMotion.moderate
        onWillCommitChanged: if (backDrag.active)
            HapticManager.tick()
    }

    GestureTracker {
        id: minimizeDrag

        to: Constants.screenHeight * 0.25
        commitDistance: 0.15 * Math.min(navBar.width, Constants.screenHeight)
        settleDuration: MMotion.reduceMotion ? MMotion.micro : MMotion.moderate
        onWillCommitChanged: if (minimizeDrag.active)
            HapticManager.tick()
    }

    // A still touch lights the pill, and asks Pilot once the charge is up;
    // a swipe locks an axis first and cancels it.
    Timer {
        id: pilotStill

        interval: 300
        onTriggered: {
            navBar.pilotLit = true;
            pilotCharging.restart();
        }
    }

    SequentialAnimation {
        id: pilotCharging

        NumberAnimation {
            target: navBar
            property: "pilotCharge"
            from: 0
            to: 1
            duration: 250
            easing.type: Easing.OutCubic
        }
        ScriptAction {
            script: {
                navMouseArea.pilotAsked = true;
                HapticManager.medium();
                navBar.pilotRequested();
            }
        }
    }
}
