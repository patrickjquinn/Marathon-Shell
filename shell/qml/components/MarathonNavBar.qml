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
    // Setup's own bar: a swipe up reports gestureProgress with no app open
    // and sends minimizeApp past the minimise threshold, and search and the
    // keyboard hide, leaving the whole bar to the pill.
    property bool setupMode: false
    // What a tap on the pill does, for screen readers; empty hides the pill from them.
    property string pillAction: ""
    // Touch and hold asks Shipwright Pilot (pilotRequested) while true.
    property bool pilotEnabled: false
    // Held still: lit, and the charge rises until Pilot is asked.
    property bool pilotLit: false
    property real pilotCharge: 0
    // Charging: the pill's breath, 0 at rest to 1 at full swell.
    property real chargeGlow: 0

    Behavior on chargeGlow {
        enabled: !chargeBreath.running

        NumberAnimation {
            duration: MMotion.durationFor("hero")
            easing.type: MMotion.easingFor("hero")
        }
    }

    // Back: the pill's leftward travel with an app open, in px (backTracker)
    // and 0..1 over backProgressTravel. The shell draws the app aside by it.
    readonly property real backProgress: backDrag.progress
    readonly property GestureTracker backTracker: backDrag
    readonly property real backProgressTravel: width * 0.55

    // The bar takes the tone of the content along its top edge.
    readonly property bool lightBackdrop: backdrop.light
    property color primary: lightBackdrop ? Silica.Theme.darkPrimaryColor : Silica.Theme.lightPrimaryColor
    property color secondary: lightBackdrop ? Silica.Theme.darkSecondaryColor : Silica.Theme.lightSecondaryColor
    property color accent: Silica.Theme.highlightFromColor(Silica.Theme.highlightColor, lightBackdrop ? Silica.Theme.DarkOnLight : Silica.Theme.LightOnDark)
    // The pill and active glyphs: an ambience highlight can't be trusted to
    // reach 3:1 on the light bar, so there they go black.
    property color highlight: lightBackdrop ? Silica.Theme.darkPrimaryColor : Silica.Theme.highlightFromColor(Silica.Theme.highlightColor, Silica.Theme.LightOnDark)

    signal swipeLeft
    signal swipeRight
    signal swipeBack
    // The back drag moved (progress 0..1, finger in scene coordinates), and
    // a horizontal drag ended, after any swipeBack it sent.
    signal backDragged(real progress, point position)
    signal backGestureEnded
    signal shortSwipeUp
    signal longSwipeUp
    signal minimizeApp(real velocityY)
    signal startPageTransition
    signal toggleKeyboard
    signal toggleSearch
    signal pilotRequested
    // A tap on the bar off the search and keyboard buttons.
    signal pillTapped

    height: Constants.navBarHeight
    color: lightBackdrop ? MColors.barLight : MColors.barDark

    Behavior on color {
        ColorAnimation {
            duration: MMotion.durationFor("hover")
            easing.type: MMotion.easingFor("hover")
        }
    }
    Behavior on primary {
        ColorAnimation {
            duration: MMotion.durationFor("hover")
            easing.type: MMotion.easingFor("hover")
        }
    }
    Behavior on secondary {
        ColorAnimation {
            duration: MMotion.durationFor("hover")
            easing.type: MMotion.easingFor("hover")
        }
    }
    Behavior on accent {
        ColorAnimation {
            duration: MMotion.durationFor("hover")
            easing.type: MMotion.easingFor("hover")
        }
    }
    Behavior on highlight {
        ColorAnimation {
            duration: MMotion.durationFor("hover")
            easing.type: MMotion.easingFor("hover")
        }
    }

    BackdropProbe {
        id: backdrop

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.top
        height: Silica.Theme.paddingSmall
        // Pilot's light, and the pill when dragged up, rise over this strip.
        visible: navBar.pilotCharge === 0 && Math.abs(indicator.dragY) < 1
        fallbackLight: Silica.Theme.colorScheme === Silica.Theme.DarkOnLight
    }

    Rectangle {
        anchors.top: parent.top
        width: parent.width
        height: Constants.borderWidthThin
        color: Silica.Theme.rgba(navBar.primary, 0.1)
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

        Accessible.role: Accessible.Button
        Accessible.name: navBar.pillAction
        Accessible.ignored: navBar.pillAction === ""
        Accessible.onPressAction: navBar.pillTapped()

        // One breath per MMotion "breathe", sampled at 15 Hz rather than
        // run as an animation, which renders every frame: the shell draws
        // 15 times a second instead of 60, and a step moves the light by
        // under 1.5%. 67 ms, not 66: a tick shorter than four 60 Hz frames
        // costs a fifth.
        Timer {
            id: chargeBreath

            property double start: 0

            interval: 67
            repeat: true
            running: MMotion.gate(Power.isCharging && Display.screenOn && navBar.visible && indicator.visible && !navBar.pilotLit)
            onRunningChanged: {
                start = Date.now();
                if (!running)
                    navBar.chargeGlow = 0;
            }
            onTriggered: navBar.chargeGlow = 0.5 - 0.5 * Math.cos(2 * Math.PI * (Date.now() - start) / MMotion.durationFor("breathe"))
        }

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
                    color: Silica.Theme.rgba(navBar.accent, 0.0)
                }
                GradientStop {
                    position: 0.55
                    color: Silica.Theme.rgba(navBar.accent, 0.18)
                }
                GradientStop {
                    position: 1.0
                    color: Silica.Theme.rgba(navBar.accent, 0.55)
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
                color: index === 0 ? navBar.highlight : navBar.accent
                opacity: (index === 0 ? 0.6 + 0.2 * navBar.chargeGlow : 0.16 / index * (1 + navBar.chargeGlow)) * (navBar.pilotLit ? 1.6 : 1)
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
        visible: !navBar.pinScreenMode && !navBar.setupMode
        opacity: navBar.pinScreenMode ? 0 : 1

        // On the page margin, in line with the status bar and the dock.
        GlyphIcon {
            name: "search"
            size: Silica.Theme.iconSizeExtraSmall
            color: navBar.searchActive ? navBar.highlight : navBar.secondary
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
        visible: !navBar.setupMode

        GlyphIcon {
            name: "keyboard"
            size: Silica.Theme.iconSizeExtraSmall
            color: navBar.keyboardVisible ? navBar.highlight : navBar.secondary
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
        // This touch is dragging the open shade closed.
        property bool draggingQuickSettings: false
        // About a millimetre: the bar sits at the screen edge, so a pull
        // down from the pill runs off the panel after a few pixels.
        readonly property real pullSlop: Math.max(3, Math.round(2 * Constants.scaleFactor))
        // The last millimetre of the panel.
        readonly property real edgeBand: Constants.dpi / 25.4
        readonly property real directionLockDistance: 10
        readonly property real verticalIntentRatio: 0.72

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
            if (isHorizontalGesture)
                navBar.backGestureEnded();
            if (pullingQuickSettings) {
                pullingQuickSettings = false;
                UIStore.quickSettingsDragging = false;
                UIStore.closeQuickSettings();
            }
            if (draggingQuickSettings) {
                draggingQuickSettings = false;
                UIStore.quickSettingsDragging = false;
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

        // Up/down gestures get a small directional bias. A thumb naturally
        // arcs across the pill, and requiring |dy| > |dx| made a deliberate
        // diagonal home/switcher gesture become Back. Ambiguous motion waits
        // for another sample instead of locking to the wrong axis.
        function gestureAxis(diffX, diffY) {
            const ax = Math.abs(diffX);
            const ay = Math.abs(diffY);
            if (Math.max(ax, ay) <= directionLockDistance)
                return 0;
            if (ay >= ax * verticalIntentRatio)
                return 1;
            if (ax >= ay / verticalIntentRatio)
                return 2;
            return 0;
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
            // A thumb pulled back to the palm runs sideways off the glass, so
            // reaching the edge on the way down is a pull, however sideways.
            const intoEdge = -diffY > pullSlop && mouse.y >= height - edgeBand && !navBar.pinScreenMode && !SessionStore.isLocked;
            if (isHorizontalGesture && intoEdge) {
                navBar.backGestureEnded();
                isHorizontalGesture = false;
            }
            const pullingDown = -diffY > pullSlop && (Math.abs(diffY) >= Math.abs(diffX) || intoEdge);
            if (!isVerticalGesture && !isHorizontalGesture && (pullingDown || Math.max(Math.abs(diffX), Math.abs(diffY)) > 10)) {
                const axis = pullingDown ? 1 : gestureAxis(diffX, diffY);
                if (axis === 1) {
                    isVerticalGesture = true;
                    pillX.settleTo(0);
                    backDrag.settleTo(0);
                } else if (axis === 2) {
                    isHorizontalGesture = true;
                    pillY.settleTo(0);
                    minimizeDrag.settleTo(0);
                }
                if (axis !== 0)
                    stopPilot();
            }
            if (!isHorizontalGesture)
                pillY.move(pillBaseY + diffY);
            if (!isVerticalGesture)
                pillX.move(pillBaseX + diffX);
            if (isVerticalGesture) {
                if (UIStore.quickSettingsOpen || (UIStore.quickSettingsHeight > 0 && !pullingQuickSettings)) {
                    draggingQuickSettings = true;
                    if (!UIStore.quickSettingsDragging)
                        UIStore.quickSettingsDragging = true;

                    // Per-frame height delta — startY is left alone so
                    // diffY stays cumulative for the release decision.
                    var frameDeltaY = diffY - prevDiffY;
                    prevDiffY = diffY;
                    var newHeight = UIStore.quickSettingsHeight - frameDeltaY;
                    UIStore.quickSettingsHeight = Math.max(0, Math.min(UIStore.maxQuickSettingsHeight, newHeight));
                } else if (pullingQuickSettings || (diffY < 0 && !navBar.pinScreenMode && !SessionStore.isLocked)) {
                    // The bar sits at the screen edge with only its own
                    // height to travel, so the shade follows at a gain:
                    // fully open at 40 % of the bar.
                    pullingQuickSettings = true;
                    UIStore.quickSettingsDragging = true;
                    UIStore.quickSettingsHeight = UIStore.maxQuickSettingsHeight * Math.max(0, Math.min(1, -diffY / Math.max(1, navBar.height * 0.4)));
                } else if (navBar.isAppOpen || navBar.setupMode) {
                    var oldProgress = navBar.gestureProgress;
                    navBar.minimizeThumbX = diffX;
                    minimizeDrag.move(Math.max(0, minimizeBase + diffY));
                    if (oldProgress <= 0.15 && navBar.gestureProgress > 0.15)
                        navBar.startPageTransition();
                }
            } else if (navBar.isAppOpen) {
                backDrag.move(Math.max(0, backBase - diffX));
                if (backDrag.value > 0)
                    navBar.backDragged(backDrag.progress, navBar.mapToItem(null, mouse.x, mouse.y));
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
                } else {
                    navBar.pillTapped();
                }
            }
            if (pullingQuickSettings) {
                pullingQuickSettings = false;
                UIStore.quickSettingsDragging = false;
                // Any locked pull opens, unless the finger came back up.
                if (-projectedUp > pullSlop)
                    UIStore.openQuickSettings();
                else
                    UIStore.closeQuickSettings();
                resetGesture(false);
                return;
            }
            if (draggingQuickSettings || ((UIStore.quickSettingsOpen || UIStore.quickSettingsHeight > 0) && isVerticalGesture)) {
                UIStore.quickSettingsDragging = false;
                var threshold = UIStore.quickSettingsThreshold;
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
                if (navBar.setupMode && minimizeCommit)
                    navBar.minimizeApp(-velocityUp);
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
                if (backCommit) {
                    Logger.gesture("NavBar", "swipeBack", {
                        "velocityX": velocityX,
                        "backProgress": navBar.backProgress
                    });
                    navBar.swipeBack();
                }
                backDrag.settleTo(0);
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

    // A thumb aiming at the pill often lands just above the bar. A pull down
    // from here takes the touch; taps, scrolls and swipes up stay with what
    // is underneath. apronPoint sees the finger while they hold it.
    Item {
        id: apron

        // Down from the press, px, and its speed, px/s.
        property real pull: 0
        property real pullVelocity: 0

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.top
        height: 3 * navMouseArea.edgeBand
        enabled: apronDrag.active || (!navBar.pinScreenMode && !navBar.keyboardVisible && !navBar.searchActive && !SessionStore.isLocked && !UIStore.quickSettingsOpen && UIStore.quickSettingsHeight === 0)

        PointHandler {
            id: apronPoint

            acceptedDevices: PointerDevice.TouchScreen
            onPointChanged: {
                if (!active)
                    return;
                apron.pull = point.position.y - point.pressPosition.y;
                apron.pullVelocity = point.velocity.y;
                if (apronDrag.active)
                    UIStore.quickSettingsHeight = UIStore.maxQuickSettingsHeight * Math.max(0, Math.min(1, apron.pull / Math.max(1, navBar.height * 0.4)));
            }
        }

        DragHandler {
            id: apronDrag

            target: null
            acceptedDevices: PointerDevice.TouchScreen
            xAxis.enabled: false
            grabPermissions: apron.pull > 0 ? PointerHandler.CanTakeOverFromAnything : PointerHandler.ApprovesTakeOverByAnything
            onActiveChanged: {
                UIStore.quickSettingsDragging = active;
                if (active)
                    return;
                Logger.gesture("NavBar", "apron released", {
                    "pull": apron.pull,
                    "velocity": apron.pullVelocity
                });
                if (apron.pull + apron.pullVelocity * 0.1 > navMouseArea.pullSlop)
                    UIStore.openQuickSettings();
                else
                    UIStore.closeQuickSettings();
            }
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
