import "./components" as Comp
import "./core/BatteryWarning.js" as BatteryWarning
import MarathonOS.Shell 1.0
import QtQuick
import QtQuick.Window
import Sailfish.Silica 1.0 as Silica

Item {
    id: shell

    property var compositor: null
    property alias appWindowContainer: appWindowContainer
    property bool showPinScreen: false
    property bool isTransitioningToActiveFrames: false
    // The lock and PIN screens paint their own full-screen backdrop. While
    // one of them is at rest, the shell wallpaper below is never seen but
    // would still be drawn and blended every frame. It is hidden with
    // opacity, not visible: an invisible Image gets no texture, so the shell
    // (which starts locked) uploaded the full-screen wallpaper mid-way
    // through the first unlock swipe, and lima tiles uploads on the CPU.
    readonly property bool wallpaperCovered: (state === "locked" && lockScreen.swipeProgress === 0) || (state === "pinEntry" && pinScreen.opacity === 1)
    // An app at rest covers everything but the status bar, whose glass lets
    // the wallpaper show through. The wallpaper is clipped to that strip
    // then, instead of being shaded full-screen under every app frame.
    readonly property bool appCoversWallpaper: state === "app" && !isTransitioningToActiveFrames && navBar.gestureProgress === 0 && navBar.backProgress === 0 && appWindowContainer.dock === 0 && appWindowContainer.opacity === 1 && !appWindow.zooming && appWindow.scale === 1 && appWindow.opacity === 1
    property int currentPage: 0
    property int totalPages: 1
    property var pendingNotification: null
    property bool pendingHub: false
    property IncomingCallOverlay incomingCallOverlay: null
    property var shellWindow: Window.window
    readonly property real maxQuickSettingsHeight: shell.height - Constants.statusBarHeight - Constants.navBarHeight
    readonly property real quickSettingsThreshold: maxQuickSettingsHeight * Constants.quickSettingsDismissThreshold
    property var pendingLaunch: null
    property bool volumeUpPressed: false
    property bool powerButtonPressed: false

    // Closes the topmost shell overlay; false when none was open.
    function closeOverlay() {
        var overlayClosed = false;
        if (showPinScreen) {
            showPinScreen = false;
            lockScreen.swipeProgress = 0;
            pinScreen.reset();
            overlayClosed = true;
        } else if (confirmDialog.shown) {
            confirmDialog.cancel();
            overlayClosed = true;
        } else if (shareSheet.shown) {
            shareSheet.close(true);
            overlayClosed = true;
        } else if (filePicker.shown) {
            filePicker.cancel();
            overlayClosed = true;
        } else if (UIStore.searchOpen) {
            UIStore.closeSearch();
            overlayClosed = true;
        } else if (UIStore.clipboardManagerOpen) {
            UIStore.closeClipboardManager();
            overlayClosed = true;
        } else if (peekFlow.peekProgress > 0) {
            if (!peekFlow.closeHubOverlay())
                peekFlow.closePeek();
            overlayClosed = true;
        } else if (UIStore.quickSettingsOpen) {
            UIStore.closeQuickSettings();
            overlayClosed = true;
        } else if (pageView.currentIndex === 0 && pageView.closeHubOverlay()) {
            overlayClosed = true;
        }
        return overlayClosed;
    }

    function handleBackKey() {
        if (PermissionManager.promptActive) {
            denyPermissionPrompt();
            return;
        }
        if (closeOverlay()) {
            Logger.info("Shell", "Back Key closed overlay");
            return;
        }
        Logger.info("Shell", "Back Key Triggered - Calling handleSystemBack");
        var handled = AppLifecycleManager.handleSystemBack();
        if (!handled) {
            Logger.info("Shell", "Back not handled by app, closing");
            if (UIStore.appWindowOpen)
                UIStore.closeApp();
        }
    }

    function dismissPermissionPrompt() {
        if (PermissionManager.promptActive)
            PermissionManager.dismissAll();
    }

    // Back on a permission prompt is Deny.
    function denyPermissionPrompt() {
        PermissionManager.respond(false);
    }

    function handleHomeKey() {
        dismissPermissionPrompt();
        if (virtualKeyboard.active) {
            HapticManager.light();
            virtualKeyboard.active = false;
            return;
        }
        if (UIStore.appWindowOpen) {
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

    // Back lands on home, so home is what shows under the app as it goes.
    function revealHomeUnderApp() {
        if (pageView.currentIndex < 2) {
            pageView.jumpToIndex(2);
            Router.goToAppPage(0);
        }
    }

    // Back on an app's root page: the app recedes and the home grid is underneath.
    function backOutOfApp() {
        if (!UIStore.appWindowOpen || backExit.running)
            return;
        revealHomeUnderApp();
        // The app carries on from where the finger left it.
        navBar.backTracker.stop();
        backExitSlide.to = navBar.backTracker.value > 0 ? navBar.backTracker.value + shell.width * 0.25 : 0;
        backExit.start();
    }

    // A volume key while a call rings silences it, as on every phone.
    // Deferred: the overlay's own handlers end up here while they still run.
    function unloadCallOverlay() {
        Qt.callLater(() => incomingCallOverlayLoader.active = false);
    }

    function silenceRinging() {
        if (!incomingCallOverlay || !incomingCallOverlay.isRinging)
            return false;
        incomingCallOverlay.silence();
        return true;
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
                PowerBatteryHandler.handlePowerButtonPress(SessionStore.isLocked, DisplayPolicyControllerCpp.screenOn, "power key (shell Keys)");
                powerButtonTimer.stop();
            }
            event.accepted = true;
        }
    }
    Component.onCompleted: {
        shell.forceActiveFocus();
        if (SecurityManagerCpp.bootUnlocked && SessionStore.isLocked)
            SessionStore.unlock();
        MHaptics.backend = HapticManager;
        compositor = shellInitialization.initialize(shell, shellWindow);
        AppLaunchService.compositor = compositor;
        AppLaunchService.appWindow = appWindow;
        AppLaunchService.uiStore = UIStore;
        AppLaunchService.appLifecycleManager = AppLifecycleManager;
        // Wire the *actual* QQuickWindow (not the root Item) so the
        // synchronous saveScreenshotTo() path works. Existing call
        // sites still pass `shell` explicitly when they want a frame
        // capture, which falls through to the Item.grabToImage() async
        // path inside captureScreen().
        ScreenshotService.shellWindow = shellWindow;
        ScreenshotService.compositor = compositor;
        SessionStore.reset();
        showPinScreen = false;
        pinScreen.reset();
        lockScreen.swipeProgress = 0;
        if (compositor) {
            compositor.systemBackTriggered.connect(handleBackKey);
            compositor.systemHomeTriggered.connect(handleHomeKey);
            compositor.userActivity.connect(PowerManagerService.updateActivity);
            // Also reset the idle-screen-off timer when the compositor
            // sees ANY input — without this the timer only resets on
            // events that bubble up to the shell's own cursorTracker
            // MouseArea, which never fires while an app's wayland
            // surface holds input focus. Result before this line: the
            // device blanks + locks after exactly screenTimeout ms of
            // inactivity in the shell *coordinate space* regardless of
            // how much the user is actively typing/scrolling inside the
            // foreground app. Was task #338.
            compositor.userActivity.connect(idleScreenTimer.rearm);
        }
        // --start-on=<surface> for visual-validation harness only.
        // Honoured alongside --skip-lock; no-op without it.
        // --demo-notifications seeds five canonical notifications matching
        // the JSX reference (Maya, Calendar, Linear, Cassandra, Missed call)
        // so lock + hub captures aren't empty in dev.
        // --screenshot-after=N --screenshot-to=PATH grabs the composited
        // shell window (including any embedded WebEngine surfaces) after
        // N seconds and writes a PNG, then quits. The shell IS the
        // Wayland compositor, so this captures everything its
        // QQuickWindow has painted — bypassing the host compositor's
        // screenshot policy (GNOME requires portal consent).
        const args = Qt.application.arguments;
        let screenshotPath = "";
        let screenshotAfterMs = 0;
        for (let i = 0; i < args.length; ++i) {
            const a = args[i];
            if (a.indexOf("--start-on=") === 0) {
                const surface = a.substring("--start-on=".length);
                startOnTimer.surface = surface;
                startOnTimer.start();
            }
            if (a === "--demo-notifications") {
                startOnTimer.seedDemo = true;
                if (!startOnTimer.running)
                    startOnTimer.start();
            }
            if (a === "--demo-call") {
                startOnTimer.seedCall = true;
                if (!startOnTimer.running)
                    startOnTimer.start();
            }
            // Visually validate the PermissionDialog without booting an
            // app-runner. Fakes a request for a single permission against
            // a known app id so the dialog's layout (app icon + name + by-
            // line + inline permission row + 2 actions) renders against
            // real shell data. Production paths never hit this.
            if (a.indexOf("--demo-permission") === 0) {
                let perm = "storage";
                let app = "notes";
                const eq = a.indexOf("=");
                if (eq > 0) {
                    const spec = a.substring(eq + 1).split(":");
                    if (spec.length >= 1 && spec[0].length > 0)
                        app = spec[0];
                    if (spec.length >= 2 && spec[1].length > 0)
                        perm = spec[1];
                }
                startOnTimer.demoPermissionApp = app;
                startOnTimer.demoPermissionId = perm;
                if (!startOnTimer.running)
                    startOnTimer.start();
            }
            if (a.indexOf("--screenshot-after=") === 0) {
                const secs = parseFloat(a.substring("--screenshot-after=".length));
                if (!isNaN(secs) && secs > 0)
                    screenshotAfterMs = Math.round(secs * 1000);
            }
            if (a.indexOf("--screenshot-to=") === 0) {
                screenshotPath = a.substring("--screenshot-to=".length);
            }
        }
        if (screenshotPath.length > 0 && screenshotAfterMs > 0) {
            screenshotTimer.path = screenshotPath;
            screenshotTimer.interval = screenshotAfterMs;
            screenshotTimer.start();
        }
    }
    AmbienceController {
        service: AmbienceService
        settings: SettingsManagerCpp
    }
    Timer {
        id: screenshotTimer
        property string path: ""
        repeat: false
        onTriggered: {
            if (!path) {
                Qt.quit();
                return;
            }
            if (typeof ScreenshotService !== "undefined" && ScreenshotService) {
                // ScreenshotService.shellWindow was already set on
                // root Component.onCompleted (see line ~132), so the
                // C++ side knows which QQuickWindow to grab. The grab
                // captures every layer the shell is rendering,
                // including embedded WebEngineView surfaces from app
                // processes.
                const ok = ScreenshotService.saveScreenshotTo(path);
                if (!ok)
                    Logger.warn("Shell", "saveScreenshotTo returned false for " + path);
            } else {
                Logger.warn("Shell", "ScreenshotService unavailable for headless capture");
            }
            // Give the file write a beat before quitting so the harness
            // doesn't race the truncated file.
            Qt.callLater(() => Qt.callLater(() => Qt.quit()));
        }
    }

    Timer {
        id: startOnTimer
        property string surface: ""
        property bool seedDemo: false
        property bool seedCall: false
        property string demoPermissionApp: ""
        property string demoPermissionId: ""
        interval: 600
        repeat: false
        onTriggered: {
            if (demoPermissionApp.length > 0 && demoPermissionId.length > 0 && typeof PermissionManager !== "undefined" && PermissionManager) {
                SessionStore.unlock();
                // Revoke first so a stored answer doesn't short-circuit the
                // prompt. Protected apps never prompt: pass an unprotected one.
                if (PermissionManager.revokePermission)
                    PermissionManager.revokePermission(demoPermissionApp, demoPermissionId);
                PermissionManager.requestPermission(demoPermissionApp, demoPermissionId);
                Logger.info("Shell", "demo-permission triggered: " + demoPermissionApp + ":" + demoPermissionId);
            }
            if (seedCall) {
                // Fake an active call so the lock-screen NowBar renders
                // for visual validation. Production paths never hit this.
                // Seed a matching contact first so the NowBar resolves to
                // "Maya Chen" rather than the raw number — the contact-
                // lookup path runs against ContactsManager via
                // PhoneApp.resolveContactName.
                if (typeof ContactsManager !== "undefined" && ContactsManager) {
                    const existing = ContactsManager.getContactByNumber ? ContactsManager.getContactByNumber("+1 415 555 0142") : null;
                    if (!existing || !existing.id)
                        ContactsManager.addContact("Maya Chen", "+1 415 555 0142", "maya@example.com");
                }
                TelephonyService.simulateIncomingCall("+1 415 555 0142");
                TelephonyService.simulateCallStateChange("active");
            }
            if (seedDemo) {
                NotificationModel.addNotification("imessage", "Maya Chen", "Heading out, see you at 8 — saved a spot near the back.", "message");
                NotificationModel.addNotification("calendar", "Design review", "Studio B · in 22m", "calendar");
                NotificationModel.addNotification("linear", "Linear", "Devon assigned: investigate compositor frame timing when keyboard is shown over video.", "briefcase");
                NotificationModel.addNotification("mail", "Cassandra Reyes", "Q4 retro — agenda + pre-reads attached. Lmk what you think.", "mail");
                NotificationModel.addNotification("phone", "Missed call · Devon", "No voicemail left", "phone");
                // Toast subscribes to NotificationModel.notificationAdded →
                // NotificationServiceCpp.notificationReceived, so seeding
                // fires the toast queue. Suppress it for validation.
                notificationToast.toastQueue = [];
                notificationToast.currentToast = null;
                notificationToast.visible = false;
            }
            // Force-unlock so peekFlow / quickSettings overlays become
            // visible (their gates are `!SessionStore.isLocked`).
            if (surface) {
                SessionStore.unlock();
                if (surface === "hub") {
                    peekFlow.openPeek();
                } else if (surface === "quicksettings") {
                    UIStore.openQuickSettings();
                } else if (surface.indexOf("app:") === 0) {
                    const appId = surface.substring(4);
                    const app = AppModel.findById ? AppModel.findById(appId) : null;
                    const appName = app && app.name ? app.name : appId;
                    const appIcon = app && app.icon ? app.icon : "";
                    UIStore.openApp(appId, appName, appIcon);
                } else if (surface.indexOf("switcher:") === 0) {
                    startOnSwitcher.apps = surface.substring(9).split(",");
                    startOnSwitcher.start();
                }
                Logger.info("Shell", "start-on=" + surface + " triggered");
            }
        }
    }
    // --start-on=switcher:<id>,<id>,...: open each app in turn, then the switcher.
    Timer {
        id: startOnSwitcher
        property var apps: []
        interval: 3000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (apps.length === 0) {
                stop();
                shell.handleHomeKey();
                return;
            }
            const app = AppModel.findById ? AppModel.findById(apps[0]) : null;
            UIStore.openApp(apps[0], app && app.name ? app.name : apps[0], app && app.icon ? app.icon : "");
            apps = apps.slice(1);
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
    // Pass --skip-lock on the command line to force shell straight to
    // "home" state — used during the Active Frames home redesign while
    // the lock+unlock interaction is being revisited. Production paths
    // (no flag) are unchanged.
    readonly property bool _skipLock: Qt.application.arguments.indexOf("--skip-lock") >= 0
    // --skip-lock is the validation-harness shortcut around the lock+OOBE path.
    // Earlier it hard-pinned to "home" which silently broke --start-on=app:<id>
    // captures (UIStore.openApp toggles appWindowOpen but the state binding
    // ignored it). Honor the app-window state even under skip-lock.
    state: _skipLock ? (UIStore.appWindowOpen ? "app" : "home") : (SettingsManagerCpp.firstRunComplete ? (SessionStore.showLockScreen ? (showPinScreen ? "pinEntry" : "locked") : (UIStore.appWindowOpen ? "app" : "home")) : "home")
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
            if (shell.silenceRinging()) {
                event.accepted = true;
                return;
            }
            SystemControlStore.setVolume(SystemControlStore.volume + 10);
            systemHUD.showVolume(AudioManagerCpp.volume);
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_VolumeDown) {
            if (shell.silenceRinging()) {
                event.accepted = true;
                return;
            }
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
            // A press while the screen is off is a wake press. Waking the
            // display holds this thread for ~800ms on the PinePhone, so the
            // release arrived after the long-press timer had fired and a
            // plain wake opened the power menu.
            if (!powerButtonTimer.running && DisplayPolicyControllerCpp.screenOn)
                powerButtonTimer.start();

            event.accepted = true;
        } else if ((event.key === Qt.Key_Space) && (event.modifiers & Qt.ControlModifier)) {
            Logger.debug("Shell", "Cmd+Space pressed - Opening Universal Search");
            UIStore.toggleSearch();
            HapticManager.light();
            event.accepted = true;
        } else if ((event.key === Qt.Key_K) && (event.modifiers & Qt.ControlModifier)) {
            Logger.debug("Shell", "Cmd+K pressed - Toggling Virtual Keyboard");
            virtualKeyboard.active = !virtualKeyboard.active;
            HapticManager.light();
            event.accepted = true;
        } else if (event.key === Qt.Key_Menu) {
            Logger.debug("Shell", "Menu key pressed - Toggling Virtual Keyboard");
            virtualKeyboard.active = !virtualKeyboard.active;
            HapticManager.light();
            event.accepted = true;
        } else if (event.key === Qt.Key_Print || event.key === Qt.Key_SysReq) {
            Logger.debug("Shell", "Print Screen pressed - Taking Screenshot");
            screenshotFlash.trigger();
            ScreenshotService.captureScreen(shell);
            HapticManager.medium();
            event.accepted = true;
        } else if ((event.key === Qt.Key_3) && (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier)) {
            Logger.debug("Shell", "Ctrl+Shift+3 pressed - Taking Screenshot");
            screenshotFlash.trigger();
            ScreenshotService.captureScreen(shell);
            HapticManager.medium();
            event.accepted = true;
        } else if ((event.key === Qt.Key_V) && (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier)) {
            Logger.debug("Shell", "Cmd+Shift+V pressed - Opening Clipboard Manager");
            UIStore.openClipboardManager();
            HapticManager.light();
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
            }

            StateChangeScript {
                script: {
                    lockScreen.swipeProgress = 0;
                }
            }

            // With a PIN to enter, the pad fades in as the lock screen lifts.
            PropertyChanges {
                pinScreen.visible: !SessionStore.checkSession()
                pinScreen.enabled: false
                pinScreen.opacity: SessionStore.checkSession() ? 0 : Math.pow(lockScreen.swipeProgress, 0.7)
            }

            PropertyChanges {
                mainContent.visible: SessionStore.checkSession()
                mainContent.enabled: false
                mainContent.opacity: SessionStore.checkSession() ? Math.pow(lockScreen.swipeProgress, 0.7) : 0
                // Home rises into place under the lifting lock screen.
                mainContent.scale: 0.94 + 0.06 * lockScreen.swipeProgress
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

            // Back from home, the switcher or the lock screen: the window in
            // front takes the keyboard again.
            StateChangeScript {
                script: {
                    appWindow.focusApp();
                }
            }

            PropertyChanges {
                lockScreen.visible: false
                lockScreen.enabled: false
            }

            PropertyChanges {
                pinScreen.visible: false
                pinScreen.enabled: false
            }

            PropertyChanges {
                // Home and the switcher stay drawn while a window grows out of them or shrinks onto a card.
                mainContent.visible: backExit.running || appWindow.zooming || appWindowContainer.dock > 0 || navBar.backProgress > 0
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
                navBar.z: PermissionManager.promptActive ? permissionDialog.z + 1 : Constants.zIndexNavBarApp
                navBar.pinScreenMode: false
            }
        }
    ]
    transitions: [
        Transition {
            from: "locked"
            to: "home"

            // An unlock that skipped the swipe (PIN, D-Bus) still lifts the
            // lock screen off a rising home instead of cutting to it.
            SequentialAnimation {
                ParallelAnimation {
                    NumberAnimation {
                        target: lockScreen
                        property: "swipeProgress"
                        to: 1
                        duration: MMotion.reduceMotion || lockScreen.swipeProgress >= 1 ? 0 : MMotion.moderate
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: mainContent
                        properties: "opacity,scale"
                        duration: MMotion.reduceMotion || lockScreen.swipeProgress >= 1 ? 0 : MMotion.moderate
                        easing.type: Easing.OutCubic
                    }
                }
                PropertyAction {
                    target: lockScreen
                    property: "visible"
                    value: false
                }
            }
        },
        Transition {
            from: "locked"
            to: "pinEntry"

            // The lock screen stays up until the pad has faded in over it.
            SequentialAnimation {
                ParallelAnimation {
                    NumberAnimation {
                        target: lockScreen
                        property: "swipeProgress"
                        to: 1
                        duration: MMotion.reduceMotion || lockScreen.swipeProgress >= 1 ? 0 : MMotion.moderate
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: pinScreen
                        property: "opacity"
                        duration: MMotion.reduceMotion || pinScreen.opacity >= 1 ? 0 : MMotion.moderate
                        easing.type: Easing.OutCubic
                    }
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

    MouseArea {
        id: cursorTracker

        anchors.fill: parent
        z: 10000
        acceptedButtons: Qt.NoButton
        hoverEnabled: true
        enabled: true
        focus: false
        onPositionChanged: mouse => {
            CursorManager.onMouseActivity();
            idleScreenTimer.rearm();
            mouse.accepted = false;
        }
        onPressed: mouse => {
            idleScreenTimer.rearm();
            mouse.accepted = false;
        }
        onReleased: mouse => {
            mouse.accepted = false;
        }
        onClicked: mouse => {
            mouse.accepted = false;
        }
    }

    // Global idle screen-off + lock. SettingsManager.screenTimeout defaults
    // to 120 s; if the user is past the lock screen and the device sits idle
    // for that long, blank the panel and re-lock. The lock-screen's own
    // 30 s idleTimer continues to apply once locked — that path turns the
    // screen back off if the user wakes the panel to peek at the time but
    // doesn't unlock.
    //
    // Reset triggers (cursorTracker.onPositionChanged + onPressed) fire on
    // ANY touch / pointer activity inside the shell's coordinate space — the
    // MouseArea sits at z: 10000 and propagates events down (mouse.accepted
    // = false) so apps still see the input. Inhibitors (video playback via
    // zwp_idle_inhibit_manager_v1, active calls) postpone the blank by one
    // full cycle so we don't blank during a YouTube video or mid-call.
    Timer {
        id: idleScreenTimer

        property int defaultIntervalMs: 120000
        // 0 = Never (user-selectable in Settings → Display & Brightness).
        // QML Timer with interval 0 fires on next tick, so gate `running`
        // on a positive interval — otherwise selecting "Never" would
        // blank the screen immediately.
        readonly property int effectiveInterval: SettingsManagerCpp ? SettingsManagerCpp.screenTimeout : defaultIntervalMs

        readonly property bool armed: effectiveInterval > 0 && DisplayPolicyControllerCpp.screenOn && !SessionStore.isLocked && !AlarmManagerCpp.hasActiveAlarm

        // restart() on activity would start a timer whose `running` binding
        // says no ("Never", locked, screen off) and break that binding for
        // good, so every start and reset goes through rearm().
        function rearm() {
            if (armed)
                restart();
            else
                stop();
        }

        interval: effectiveInterval > 0 ? effectiveInterval : defaultIntervalMs
        repeat: false
        onArmedChanged: rearm()
        Component.onCompleted: rearm()
        onTriggered: {
            if (typeof compositor !== 'undefined' && shell.compositor && shell.compositor.hasIdleInhibitingSurface) {
                Logger.info("Shell", "Idle inhibitor active (video/call?) — postponing blank");
                idleScreenTimer.rearm();
                return;
            }
            if (PowerPolicyControllerCpp.hasActiveCalls) {
                Logger.info("Shell", "Active call — postponing blank");
                idleScreenTimer.rearm();
                return;
            }
            Logger.info("Shell", "Idle timeout (" + idleScreenTimer.interval + "ms) — blanking + auto-locking");
            SessionStore.isLocked = true;
            DisplayPolicyControllerCpp.turnScreenOff("idle timer (" + idleScreenTimer.interval + "ms)");
        }
    }

    Binding {
        target: SessionStore
        property: "lockDelay"
        value: SettingsManagerCpp ? SettingsManagerCpp.autoLockTimeout : 0
    }

    // ── Idle DIM warning (PWR-5) ────────────────────────────────
    // Fires `dimAdvanceMs` BEFORE idleScreenTimer to dim the backlight
    // to a fraction of its current level. Gives the user a visible
    // warning that the screen is about to blank, and saves continuous
    // backlight power even before the full screen-off engages — the L5
    // panel at 255/255 draws ~0.5 W; at 64/255 it's ~0.2 W. iOS does
    // ~10 s before blank; we go ~30 s because Marathon's screen-off
    // default is more aggressive (120 s vs iOS 60 s).
    //
    // On any user activity, dimRestore() returns the backlight to its
    // pre-dim level and re-arms idleScreenTimer. The dim is purely
    // ephemeral state — it does NOT touch SettingsManagerCpp/the
    // persisted user brightness preference.
    QtObject {
        id: dimState

        property real preDimBrightness: -1
        property bool dimmed: false

        readonly property real dimFraction: 0.25
        readonly property int dimAdvanceMs: 30000

        function dim() {
            if (dimmed || !SystemControlStore || !DisplayPolicyControllerCpp.screenOn)
                return;
            preDimBrightness = SystemControlStore.brightness;
            if (preDimBrightness <= 0)
                return;
            const target = Math.max(5, Math.round(preDimBrightness * dimFraction));
            Logger.info("Shell", "Idle dim — " + preDimBrightness + " → " + target);
            SystemControlStore.setBrightness(target);
            dimmed = true;
        }
        function restore() {
            if (!dimmed)
                return;
            Logger.info("Shell", "Idle dim restore — " + preDimBrightness);
            if (preDimBrightness > 0 && SystemControlStore)
                SystemControlStore.setBrightness(preDimBrightness);
            preDimBrightness = -1;
            dimmed = false;
        }
    }

    Timer {
        id: idleDimTimer

        readonly property int effectiveInterval: Math.max(5000, idleScreenTimer.effectiveInterval - dimState.dimAdvanceMs)

        interval: effectiveInterval
        // Only run when the main screen-off timer is armed AND we
        // haven't already dimmed (avoid re-firing during the 30 s
        // dim window).
        running: idleScreenTimer.running && !dimState.dimmed
        repeat: false
        onTriggered: dimState.dim()
    }

    // Restore on any input. compositor.userActivity already wires to
    // idleScreenTimer.restart in the Component.onCompleted block — we
    // hook the same signal here for the dim restore. Re-arming the
    // restart on activity is the existing behaviour; we add the dim
    // un-dim alongside.
    Connections {
        target: shell.compositor
        ignoreUnknownSignals: true
        function onUserActivity() {
            dimState.restore();
        }
    }

    // Power-key + system-level screen-on must ALSO restore the dim.
    // compositor.userActivity only fires for touch / wayland input, not
    // for /dev/input/event3 KEY_POWER (which PowerKeyListener routes via
    // PowerBatteryHandlerCpp.turnScreenOn → DisplayPolicyController.
    // screenOnChanged). Without this hook, pressing the power key
    // restored bl_power=0 (screen on) but brightness stayed pinned at
    // the dim value (5-25%) — user perceived the screen as dead.
    Connections {
        target: DisplayPolicyControllerCpp
        ignoreUnknownSignals: true
        function onScreenOnChanged() {
            if (DisplayPolicyControllerCpp.screenOn) {
                dimState.restore();
                // Re-arm idle timers from the moment of wake.
                idleScreenTimer.rearm();
            }
        }
    }

    Timer {
        id: resizeDebounceTimer

        interval: 100
        onTriggered: {
            // Prefer ScreenMetricsCpp.dpi when available -- it honors the
            // MARATHON_FORCE_DPI override used for QEMU validation. Fall
            // back to Qt's pixelDensity-derived DPI on real hardware where
            // the env stays unset.
            var deviceDpi = (typeof ScreenMetricsCpp !== 'undefined' && ScreenMetricsCpp && ScreenMetricsCpp.dpi > 0) ? ScreenMetricsCpp.dpi : Screen.pixelDensity * 25.4;
            Constants.updateScreenSize(shell.width, shell.height, deviceDpi);
        }
    }

    Connections {
        function onDeepLinkRequested(appId, route, params) {
            if (!AppLaunchService.launchAppWithRoute(appId, route, JSON.stringify(params || {}), shell.compositor, appWindow))
                Logger.warn("Shell", "Deep link not opened: " + appId + " " + route);
        }

        target: NavigationRouter
    }

    // Back to an out-of-process app is answered asynchronously; a refusal
    // closes the app, as an in-process "not handled" does in onSwipeBack.
    Connections {
        function onSystemBackUnhandled() {
            shell.backOutOfApp();
        }
        target: AppLifecycleManager
    }

    Connections {
        readonly property var warning: ({
                "warnedAt": 101,
                "last": -1
            })

        function onBatteryLevelChanged() {
            const level = SystemStatusStore.batteryLevel;
            const threshold = BatteryWarning.check(warning, level, SystemStatusStore.isPluggedIn);
            if (threshold === 0)
                return;
            NotificationService.sendNotification("system", "Battery at " + level + "%", SystemControlStore.isLowPowerMode ? "Plug in your phone soon." : "Turn on Battery Saver in Quick Settings to make it last longer, or plug in.", {
                "category": "system",
                "priority": threshold <= 10 ? "high" : "normal",
                "icon": "battery-low"
            });
        }

        target: SystemStatusStore
    }

    // A field in the previous app can't report losing focus, so switching apps drops the keyboard.
    Connections {
        function onCurrentAppIdChanged() {
            virtualKeyboard.active = false;
        }
        function onAppWindowOpenChanged() {
            if (!UIStore.appWindowOpen)
                virtualKeyboard.active = false;
        }
        target: UIStore
    }

    // Single-modal rule (iOS HIG / Material): only one backdropped
    // surface visible at a time. Wire new system modals here too.
    Connections {
        function onPromptActiveChanged() {
            if (PermissionManager.promptActive && UIStore.quickSettingsOpen)
                UIStore.closeQuickSettings();
        }
        target: PermissionManager
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

    Connections {
        function onLockRequested() {
            SessionStore.lock();
        }

        target: PowerBatteryHandler
    }

    Connections {
        // marathon CLI `qs` verb → NavigationObject (D-Bus) → AppLaunchService.
        // Lets a dev host drive the shade over IPC; top-edge touch injection
        // never reaches statusBarDragArea. mode: 0 hide, 1 show, 2 toggle.
        // Refuse show/toggle while locked — mirrors the shade's own gate.
        function onQuickSettingsRequested(mode) {
            if (mode === 0)
                UIStore.closeQuickSettings();
            else if (SessionStore.isLocked)
                Logger.info("Shell", "qs request ignored — device is locked");
            else if (mode === 2)
                UIStore.toggleQuickSettings();
            else
                UIStore.openQuickSettings();
        }

        function onHomeRequested(switcher) {
            shell.handleHomeKey();
            if (!switcher) {
                pageView.currentIndex = 2;
                Router.goToAppPage(0);
            }
        }

        target: AppLaunchService
    }

    Comp.ShellInitialization {
        id: shellInitialization
    }

    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: shell.appCoversWallpaper ? Constants.statusBarHeight : parent.height
        clip: true
        z: Constants.zIndexBackground

        Image {
            id: wallpaperImage
            width: shell.width
            height: shell.height
            source: WallpaperStore.path
            fillMode: Image.PreserveAspectCrop
            opacity: shell.wallpaperCovered ? 0 : 1
        }
    }

    // Dither overlay.
    // 64×64 noise tile @ 4 % opacity adds ~1 LSB jitter per pixel,
    // enough to break the gradient banding on 18 bpp DPI panels
    // (HyperPixel 4.0 Square on the Hackberry CM5). No-op cost on
    // higher bit-depth panels; barely visible.
    Image {
        anchors.fill: parent
        source: "file:///usr/share/marathon-shell/wallpapers/dither-noise.png"
        fillMode: Image.Tile
        opacity: shell.wallpaperCovered ? 0 : 0.04
        smooth: false
        cache: true
        visible: DeviceProfile.panelDither
        z: Constants.zIndexBackground + 1
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

            // Pages: 0 the Hub, 1 Active Frames (the task switcher), 2+ the app grid.
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
                        shell.totalPages = pageView.pageCount;
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
                onAppLongPressed: (app, sceneRect) => appContextMenu.show(app, appContextMenu.mapFromItem(null, sceneRect))
                Component.onCompleted: {
                    shell.totalPages = pageView.pageCount;
                }
            }

            Item {
                id: bottomSection

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: bottomBar.height
                z: Constants.zIndexBottomSection
                // The Hub's weather sheet covers the page, this bar included.
                visible: !pageView.hubOverlayOpen

                MarathonBottomBar {
                    id: bottomBar

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    currentPage: shell.currentPage
                    totalPages: shell.totalPages
                    showNotifications: shell.currentPage > 0
                    onAppLaunched: app => {
                        AppLaunchService.launchApp(app, shell.compositor, appWindow);
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
        z: PermissionManager.promptActive ? permissionDialog.z + 1 : Constants.zIndexNavBarApp
        isAppOpen: UIStore.appWindowOpen || UIStore.settingsOpen
        keyboardVisible: virtualKeyboard.active
        searchActive: UIStore.searchOpen
        pilotEnabled: PilotClient.available && SettingsManagerCpp.firstRunComplete && !SessionStore.isLocked && !navBar.pinScreenMode && !virtualKeyboard.active && !UIStore.quickSettingsOpen && !UIStore.searchOpen
        onPilotRequested: {
            pilotGlow.light();
            // The Wayland client is the app itself, not its sandbox or Keel host.
            const s = UIStore.appWindowOpen && appWindow.waylandSurface ? (appWindow.waylandSurface.surface || appWindow.waylandSurface) : null;
            PilotClient.showSheetFor(s && s.client ? s.client.processId : 0);
        }
        onToggleKeyboard: {
            Logger.info("Shell", "Keyboard button clicked, current: " + virtualKeyboard.active);
            virtualKeyboard.active = !virtualKeyboard.active;
            Logger.info("Shell", "Keyboard toggled to: " + virtualKeyboard.active);
        }
        onToggleSearch: {
            Logger.info("Shell", "Search button clicked from nav bar");
            UIStore.toggleSearch();
            HapticManager.light();
        }
        onSwipeLeft: {
            if (PermissionManager.promptActive) {
                shell.denyPermissionPrompt();
                return;
            }
            // Left is back: an open overlay closes before the pages move.
            if (shell.closeOverlay())
                return;
            if (UIStore.appWindowOpen || UIStore.settingsOpen)
                return;

            if (pageView.currentIndex < pageView.count - 1) {
                pageView.incrementCurrentIndex();
                Router.navigateLeft();
            } else {
                pageView.nudgeAtBoundary(1);
            }
        }
        onSwipeRight: {
            if (UIStore.appWindowOpen) {
                var handled = AppLifecycleManager.handleSystemForward();
                if (handled)
                    return;
            }
            if (UIStore.appWindowOpen || UIStore.settingsOpen)
                return;

            if (pageView.currentIndex > 0) {
                pageView.decrementCurrentIndex();
                Router.navigateRight();
            } else {
                pageView.nudgeAtBoundary(-1);
            }
        }
        onBackDragged: (progress, position) => {
            if (shell.compositor)
                shell.compositor.sendBackProgress(appWindow.surfaceId, progress, position);
        }
        onBackGestureEnded: {
            if (shell.compositor)
                shell.compositor.endBackGesture(appWindow.surfaceId);
        }
        onSwipeBack: {
            Logger.info("NavBar", "Back gesture detected");
            if (PermissionManager.promptActive) {
                shell.denyPermissionPrompt();
                return;
            }
            if (powerMenu.showing) {
                powerMenu.cancel();
                return;
            }
            // Apps never report a field losing focus, so back closes the keyboard first.
            if (virtualKeyboard.active) {
                virtualKeyboard.active = false;
                return;
            }
            if (shell.closeOverlay())
                return;
            var handled = AppLifecycleManager.handleSystemBack();
            if (!handled) {
                Logger.info("NavBar", "App didn't handle back, closing");
                shell.backOutOfApp();
            }
        }
        onShortSwipeUp: {
            shell.dismissPermissionPrompt();
            if (peekFlow.peekProgress > 0)
                peekFlow.closePeek();
            if (virtualKeyboard.active) {
                Logger.info("NavBar", "Dismissing keyboard with short swipe up");
                HapticManager.light();
                virtualKeyboard.active = false;
                return;
            }
            Logger.gesture("NavBar", "shortSwipeUp", {
                "target": "home"
            });
            // Hub=0, Frames=1, AppGrid pages start at index 2 (home).
            pageView.currentIndex = 2;
            Router.goToAppPage(0);
        }
        onLongSwipeUp: {
            shell.dismissPermissionPrompt();
            if (peekFlow.peekProgress > 0)
                peekFlow.closePeek();
            Logger.info("NavBar", "------- LONG SWIPE UP RECEIVED -------");
            if (virtualKeyboard.active) {
                Logger.info("NavBar", "Dismissing keyboard with long swipe up");
                HapticManager.light();
                virtualKeyboard.active = false;
                return;
            }
            Logger.gesture("NavBar", "longSwipeUp", {
                "target": "activeFrames"
            });
            if (UIStore.appWindowOpen) {
                Logger.info("NavBar", "APP WINDOW OPEN - Minimizing to task switcher");
                Logger.info("NavBar", "  UIStore.appWindowOpen: " + UIStore.appWindowOpen);
                Logger.info("NavBar", "  UIStore.settingsOpen: " + UIStore.settingsOpen);
                Logger.info("NavBar", " Calling AppLifecycleManager.minimizeForegroundApp()");
                var result = AppLifecycleManager.minimizeForegroundApp();
                Logger.info("NavBar", "   AppLifecycleManager.minimizeForegroundApp() returned: " + result);
                Logger.info("NavBar", "   Triggering snapIntoGridAnimation for smooth transition");
                shell.isTransitioningToActiveFrames = true;
                snapIntoGridAnimation.startWithVelocity(-1500);
            } else {
                Logger.info("NavBar", "No app open - just navigating to task switcher");
                pageView.currentIndex = 1;
                Router.goToFrames();
            }
            Logger.info("NavBar", "------- LONG SWIPE UP COMPLETE -------");
        }
        onStartPageTransition: {
            if ((UIStore.appWindowOpen || UIStore.settingsOpen) && pageView.currentIndex !== 1) {
                pageView.currentIndex = 1;
                Router.goToFrames();
            }
            WindowOrigins.revealCard(UIStore.currentAppId);
        }
        onMinimizeApp: {
            Logger.info("Shell", "NavBar minimize gesture detected");
            AppLifecycleManager.minimizeForegroundApp();
            shell.isTransitioningToActiveFrames = true;
            var initialVelocity = -1000;
            snapIntoGridAnimation.startWithVelocity(initialVelocity);
        }
    }

    MarathonPeek {
        id: peekFlow

        anchors.fill: parent
        visible: !SessionStore.isLocked
        z: Constants.zIndexPeek

        // The Hub and Quick Settings never outlive a lock or an app launch.
        Connections {
            target: SessionStore
            function onIsLockedChanged() {
                if (SessionStore.isLocked)
                    peekFlow.closePeek();
            }
        }
        // Any launch brings an app forward, also over an app already open.
        Connections {
            target: AppLaunchService
            function onAppLaunchStarted() {
                peekFlow.closePeek();
                UIStore.closeQuickSettings();
            }
            // Bringing forward an app that is already running.
            function onAppLaunchCompleted() {
                peekFlow.closePeek();
                UIStore.closeQuickSettings();
            }
        }
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
        // Over an app, the header's back indicator keeps its taps (as in MarathonPeek).
        anchors.topMargin: UIStore.appWindowOpen ? Constants.statusBarHeight + Silica.Theme.itemSizeLarge : 0
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

    // Dims home under a window growing out of it, and lifts as one shrinks onto its card.
    Rectangle {
        anchors.fill: parent
        z: Constants.zIndexAppWindow
        color: "black"
        visible: appWindow.zooming || appWindowContainer.dock > 0
        opacity: appWindow.zooming ? 0.5 * appWindow.zoom : 0.5 * (1 - appWindowContainer.dock)
    }

    Item {
        id: appWindowContainer

        // 0: full screen; 1: sitting on the app's switcher card. The swipe
        // drives it while the finger is down, snapIntoGridAnimation after.
        // TODO(t2): follow the thumb sideways once the nav bar exposes its x travel.
        // Follows the finger over the travel snapIntoGridAnimation assumes for the rest.
        readonly property real gestureDock: Math.min(1, navBar.minimizeTracker.value / (shell.height * 0.6))
        property real dockAnimated: 0
        readonly property real dock: shell.isTransitioningToActiveFrames ? dockAnimated : gestureDock
        property bool landed: false
        // Bumped when the switcher is moved under the window.
        property int dockCardEpoch: 0
        // Shell coordinates of the cover the app lands on, re-read each
        // step: the switcher page slides in under the window.
        readonly property rect dockCard: {
            if (dock <= 0 || dockCardEpoch < 0)
                return Qt.rect(0, 0, 0, 0);
            var r = WindowOrigins.cardRect(UIStore.currentAppId);
            if (r.width > 0)
                return shell.mapFromItem(null, r.x, r.y, r.width, r.height);
            var s = 0.65;
            return Qt.rect(width * (1 - s) / 2, height * (1 - s) / 2 + Constants.safeAreaTop * s, width * s, appWindow.height * s);
        }
        // The window fills the card as the cover does: scaled to cover it,
        // centred across and from its top, the overflow cropped.
        readonly property real dockScale: dockCard.width > 0 ? Math.max(dockCard.width / width, dockCard.height / appWindow.height) : 1
        // The part of the app the card shows, in unscaled px.
        readonly property real dockWidth: dockCard.width > 0 ? dockCard.width / dockScale : width
        readonly property real dockHeight: dockCard.width > 0 ? dockCard.height / dockScale : appWindow.height

        // Apps render full-screen behind the navBar so their content (gradients,
        // backgrounds, hero images) bleeds to the bottom edge. The first
        // attempt at #407 clipped this to `navBar.top` to keep tab-bar taps
        // outside the gesture zone, but that exposed the desktop wallpaper
        // between every app's bottom chrome and the navBar — visually broken
        // on Store / Browser / anything whose content didn't fill that strip.
        // Tab-bar capture is handled at the navBar.MouseArea level instead,
        // where only swipes from the bottom-N px register as gestures.
        anchors.fill: parent
        visible: UIStore.appWindowOpen || shell.isTransitioningToActiveFrames
        z: Constants.zIndexAppWindow
        transform: [
            Scale {
                xScale: 1 + (appWindowContainer.dockScale - 1) * appWindowContainer.dock
                yScale: 1 + (appWindowContainer.dockScale - 1) * appWindowContainer.dock
            },
            Translate {
                x: (appWindowContainer.dockCard.x - (appWindowContainer.width - appWindowContainer.dockWidth) / 2 * appWindowContainer.dockScale) * appWindowContainer.dock
                y: (appWindowContainer.dockCard.y - Constants.safeAreaTop * appWindowContainer.dockScale) * appWindowContainer.dock
            }
        ]
        // Single entry point for bringing UIStore's current app on screen,
        // shared by the currentAppId and appWindowOpen signal paths.
        function showForegroundApp(reason) {
            if (!UIStore.appWindowOpen || !UIStore.currentAppId)
                return;
            var task = TaskModel.getTaskByAppId(UIStore.currentAppId);
            // The launch-hold only guards duplicate spawns; an app that
            // already has a surface is a re-show and must always proceed,
            // or a restore inside the hold window leaves the window blank.
            if ((!task || task.surfaceId < 0) && AppLaunchService.isAppLaunching(UIStore.currentAppId)) {
                Logger.info("Shell", "AppLaunchService is launching " + UIStore.currentAppId + " - skipping redundant show()");
                return;
            }
            Logger.warn("Shell", "Showing " + UIStore.currentAppId + " (" + reason + ")");
            if (task && task.appType === "native" && shell.compositor) {
                var surface = shell.compositor.getSurfaceById(task.surfaceId);
                if (surface) {
                    appWindow.show(UIStore.currentAppId, UIStore.currentAppName, UIStore.currentAppIcon, "native", surface, task.surfaceId);
                    return;
                }
                Logger.warn("Shell", "Native app surface not found for surfaceId: " + task.surfaceId);
                for (var i = 0; i < backgroundAppsContainer.children.length; i++) {
                    var child = backgroundAppsContainer.children[i];
                    if (child.appId === UIStore.currentAppId) {
                        Logger.warn("Shell", "Re-attaching detached native instance: " + UIStore.currentAppId);
                        appWindow.reattachInstance(child, UIStore.currentAppId, UIStore.currentAppName, UIStore.currentAppIcon, "native");
                        return;
                    }
                }
                Logger.warn("Shell", "No detached instance found in backgroundAppsContainer for: " + UIStore.currentAppId);
            }
            // launchApp restores running apps via its existing-task branch;
            // only block it when a live runner has no surface to restore
            // (spawning there duplicates into the void).
            if (AppLaunchService.pidForAppId(UIStore.currentAppId) > 0 && (!task || task.surfaceId < 0)) {
                Logger.warn("Shell", "Runner alive without surface for " + UIStore.currentAppId + " - skipping fallback relaunch");
                return;
            }
            AppLaunchService.launchApp(UIStore.currentAppId, shell.compositor, appWindow);
        }

        Connections {
            function onCurrentAppIdChanged() {
                // A permission dialog for the previous foreground app must
                // not leak on top of the next one (audit on r269 hit this).
                if (PermissionManager.promptActive && PermissionManager.currentAppId && PermissionManager.currentAppId !== UIStore.currentAppId) {
                    PermissionManager.dismissForApp(PermissionManager.currentAppId);
                }
                appWindowContainer.showForegroundApp("app-id-changed");
            }

            function onAppWindowOpenChanged() {
                appWindowContainer.showForegroundApp("window-opened");
            }

            target: UIStore
            enabled: UIStore !== null
        }

        // Back: home shows dimmed under the app the finger draws aside.
        Connections {
            target: navBar.backTracker
            function onValueChanged() {
                if (navBar.backTracker.active && navBar.backTracker.value > 0 && UIStore.appWindowOpen)
                    shell.revealHomeUnderApp();
            }
        }
        // Minimise: the switcher is already in place under the app, its
        // card settled, before the window takes its first step towards it.
        Connections {
            target: navBar.minimizeTracker
            function onValueChanged() {
                if (navBar.minimizeTracker.active && navBar.minimizeTracker.value > 0 && UIStore.appWindowOpen && pageView.currentIndex !== 1) {
                    pageView.jumpToIndex(1);
                    Router.goToFrames();
                    WindowOrigins.revealCard(UIStore.currentAppId);
                    appWindowContainer.dockCardEpoch++;
                }
            }
        }
        Rectangle {
            anchors.fill: parent
            color: "black"
            visible: navBar.backTracker.value > 0
            opacity: 0.5 * (1 - navBar.backProgress) * appWindow.opacity
        }

        // Crops the window to what the card shows as it lands; a scissor
        // clip, not a layer, so the gesture costs no offscreen pass.
        Item {
            id: cardBorder

            x: (parent.width - appWindowContainer.dockWidth) / 2 * appWindowContainer.dock
            width: parent.width - 2 * x
            y: Constants.safeAreaTop * appWindowContainer.dock
            height: parent.height + (Constants.safeAreaTop + appWindowContainer.dockHeight - parent.height) * appWindowContainer.dock - y
            clip: appWindowContainer.dock > 0
            // Back: the app follows the pill left and recedes to 0.9.
            readonly property real backShrink: Math.min(1, navBar.backTracker.value / (parent.width * 0.3))
            transform: [
                Scale {
                    origin.x: cardBorder.width / 2
                    origin.y: cardBorder.height / 2
                    xScale: 1 - 0.1 * cardBorder.backShrink
                    yScale: 1 - 0.1 * cardBorder.backShrink
                },
                Translate {
                    x: -navBar.backTracker.value
                }
            ]

            MarathonAppWindow {
                id: appWindow

                onRetryRequested: id => Qt.callLater(() => AppLaunchService.launchApp(id, shell.compositor, appWindow))

                x: -cardBorder.x
                y: Constants.safeAreaTop - cardBorder.y
                width: appWindowContainer.width
                height: appWindowContainer.height - Constants.safeAreaTop - Constants.safeAreaBottom - shell.appKeyboardInset
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

            // Rounds the landing window to its card: the app's backdrop and
            // surface are drawn through the crop with the cover's corners,
            // the originals hidden once these have their textures.
            Item {
                id: dockCorners

                readonly property var app: appWindow.appContainer ? appWindow.appContainer["appInstance"] : null
                readonly property Item surface: app && app.surfaceItemRef ? app.surfaceItemRef : null
                readonly property bool active: appWindowContainer.dock > 0 && surface !== null
                readonly property bool ready: surfaceCorners.ready && (backdropCorners.source === null || backdropCorners.ready)
                // The cover's radius in the shrinking container's pixels.
                readonly property real radius: WindowOrigins.cardRadius * appWindowContainer.dock / (1 + (appWindowContainer.dockScale - 1) * appWindowContainer.dock)

                // The part of item inside the crop, in the crop's pixels.
                function part(item) {
                    if (!item || item.width <= 0 || item.height <= 0)
                        return Qt.rect(0, 0, cardBorder.width, cardBorder.height);
                    void (appWindow.x + appWindow.y); // mapToItem tracks no geometry
                    var r = item.mapToItem(cardBorder, 0, 0, item.width, item.height);
                    var x = Math.max(0, r.x), y = Math.max(0, r.y);
                    return Qt.rect(x, y, Math.max(0, Math.min(cardBorder.width, r.x + r.width) - x), Math.max(0, Math.min(cardBorder.height, r.y + r.height) - y));
                }

                // That part, normalized to item.
                function crop(item, p) {
                    if (!item || item.width <= 0 || item.height <= 0)
                        return Qt.rect(0, 0, 1, 1);
                    var r = item.mapToItem(cardBorder, 0, 0, item.width, item.height);
                    return Qt.rect((p.x - r.x) / r.width, (p.y - r.y) / r.height, p.width / r.width, p.height / r.height);
                }

                anchors.fill: parent
                visible: active

                WindowTextureItem {
                    id: backdropCorners

                    readonly property rect part: dockCorners.part(source)

                    x: part.x
                    y: part.y
                    width: part.width
                    height: part.height
                    source: dockCorners.active && dockCorners.app.backdropItem ? dockCorners.app.backdropItem : null
                    radius: dockCorners.radius
                    sourceRect: dockCorners.crop(source, part)
                }

                WindowTextureItem {
                    id: surfaceCorners

                    readonly property rect part: dockCorners.part(source)

                    x: part.x
                    y: part.y
                    width: part.width
                    height: part.height
                    source: dockCorners.active ? dockCorners.surface : null
                    radius: dockCorners.radius
                    sourceRect: dockCorners.crop(source, part)
                }

                // A pill gesture takes the app's fingers (a second finger
                // on the pill while one is in the app): it gets a cancel.
                readonly property bool gestureStolen: navBar.gestureProgress > 0 || navBar.backTracker.value > 0
                onGestureStolenChanged: {
                    if (gestureStolen && surface && shell.compositor)
                        shell.compositor.cancelTouch(surface);
                }

                Binding {
                    target: dockCorners.app
                    property: "texturesRequested"
                    value: dockCorners.active
                    when: dockCorners.app !== null && dockCorners.app.drawnByTexture !== undefined
                    restoreMode: Binding.RestoreBindingOrValue
                }

                Binding {
                    target: dockCorners.app
                    property: "drawnByTexture"
                    value: dockCorners.active && dockCorners.ready
                    when: dockCorners.app !== null && dockCorners.app.drawnByTexture !== undefined
                    restoreMode: Binding.RestoreBindingOrValue
                }
            }
        }

        // The edge shadow the drawn-aside app casts on home.
        Rectangle {
            readonly property real s: 1 - 0.1 * cardBorder.backShrink

            x: parent.width * (1 + s) / 2 - navBar.backTracker.value
            y: parent.height * (1 - s) / 2
            width: Constants.spacingXLarge
            height: parent.height * s
            visible: navBar.backTracker.value > 0
            opacity: Math.min(1, navBar.backTracker.value / width) * appWindow.opacity
            gradient: Gradient {
                orientation: Gradient.Horizontal

                GradientStop {
                    position: 0
                    color: Qt.rgba(0, 0, 0, 0.45)
                }
                GradientStop {
                    position: 1
                    color: "transparent"
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

    KeelDialogLayer {
        id: keelDialogs

        anchors.fill: parent
        anchors.topMargin: Constants.safeAreaTop
        anchors.bottomMargin: Constants.safeAreaBottom + virtualKeyboard.reservedHeight
        z: Constants.zIndexKeelDialog
        visible: !SessionStore.isLocked
        backdropSource: UIStore.appWindowOpen ? appWindowContainer : null
        onShown: pilotGlow.overlayShown()
        onClosed: {
            if (count === 0 && UIStore.appWindowOpen)
                appWindow.focusApp();
        }

        Connections {
            function onDialogSurfaceCreated(appId, xdgSurface, surfaceId) {
                keelDialogs.add(appId, xdgSurface, surfaceId);
            }

            target: AppLaunchService
        }
    }

    // Finishes a minimise: the window lands on its card, the card's cover
    // appears under it, and the window fades off the cover.
    SequentialAnimation {
        id: snapIntoGridAnimation

        // velocity: px/s, negative upward.
        function startWithVelocity(velocity) {
            appWindowContainer.dockAnimated = appWindowContainer.gestureDock;
            appWindowContainer.landed = false;
            pageView.currentIndex = 1;
            Router.goToFrames();
            var remaining = (1 - appWindowContainer.dockAnimated) * shell.height * 0.6;
            dockStep.duration = MMotion.reduceMotion ? MMotion.micro : Math.max(MMotion.quick, Math.min(MMotion.slow, 1000 * remaining / Math.max(1, Math.abs(velocity))));
            restart();
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
            appWindowContainer.landed = false;
            appWindowContainer.dockAnimated = 0;
            appWindowContainer.opacity = 1;
        }

        NumberAnimation {
            id: dockStep

            target: appWindowContainer
            property: "dockAnimated"
            to: 1
            easing.type: Easing.Bezier
            easing.bezierCurve: MMotion.easingDecelerateCurve
        }

        ScriptAction {
            script: appWindowContainer.landed = true
        }

        NumberAnimation {
            target: appWindowContainer
            property: "opacity"
            to: 0
            duration: MMotion.dur(MMotion.fast)
            easing.type: Easing.InOutQuad
        }
    }

    // The card under a minimising window hides its cover until the window lands.
    Binding {
        target: WindowOrigins
        property: "dockingAppId"
        value: UIStore.currentAppId
        when: appWindowContainer.dock > 0 && !appWindowContainer.landed
        restoreMode: Binding.RestoreValue
    }

    MarathonQuickSettings {
        id: quickSettings

        anchors.left: parent.left
        anchors.right: parent.right
        y: Constants.statusBarHeight
        height: drawnHeight
        maxHeight: shell.maxQuickSettingsHeight
        visible: !SessionStore.isLocked && drawnHeight > 0
        z: Constants.zIndexQuickSettings
        clip: true
        homeBackdrop: wallpaperImage
        onClosed: {
            UIStore.closeQuickSettings();
        }
        onLaunchApp: app => {
            AppLaunchService.launchApp(app, shell.compositor, appWindow);
        }
        onPowerRequested: shell.showPowerMenu()
        // The screen changed size while open (rotation).
        onMaxHeightChanged: if (UIStore.quickSettingsOpen && !UIStore.quickSettingsDragging)
            UIStore.quickSettingsHeight = maxHeight
    }

    Connections {
        function onQuickSettingsOpenChanged() {
            if (UIStore.quickSettingsOpen)
                HapticManager.tick();
        }

        target: UIStore
    }

    MouseArea {
        id: statusBarDragArea

        property real startY: 0
        property bool isDraggingDown: false

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
            isDraggingDown = false;
        }
        onPositionChanged: mouse => {
            var dragDistance = mouse.y - startY;
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
                var open = quickSettings.tracker.decide(UIStore.quickSettingsHeight, quickSettings.tracker.velocity);
                Logger.gesture("StatusBar", "dragEnd", {
                    "height": UIStore.quickSettingsHeight,
                    "velocity": quickSettings.tracker.velocity,
                    "open": open
                });
                if (open)
                    UIStore.openQuickSettings();
                else
                    UIStore.closeQuickSettings();
            }
            startY = 0;
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

    // Dim area beneath the QS shade. iOS Control Center + Android 16
    // both treat this surface as TAP-ONLY: tap to dismiss, never
    // drag-to-resize. The old behaviour mutated quickSettingsHeight
    // 1:1 with the cursor, so dragging up in the dim area "scrolled"
    // the shade off the top of the screen pixel-by-pixel — read as a
    // Flickable, not a panel collapsing. Drag-to-close lives on the
    // shade itself (MarathonQuickSettings DragHandler) and on the nav
    // bar's swipe-up handler; the dim area's only job is the tap.
    MouseArea {
        id: quickSettingsOverlay

        anchors.fill: parent
        anchors.topMargin: Constants.statusBarHeight + quickSettings.drawnHeight
        z: Constants.zIndexQuickSettingsOverlay
        enabled: UIStore.quickSettingsHeight > 0 && !SessionStore.isLocked
        visible: quickSettings.drawnHeight > 0 && !SessionStore.isLocked
        onClicked: {
            Logger.gesture("QuickSettings", "dimAreaTapClose", {});
            UIStore.closeQuickSettings();
        }

        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: 0.3 * Math.min(1, quickSettings.drawnHeight / Math.max(1, shell.quickSettingsThreshold))
        }
    }

    MarathonLockScreen {
        id: lockScreen

        anchors.fill: parent
        z: Constants.zIndexLockScreen
        compositor: shell.compositor
        appBackdrop: UIStore.appWindowOpen ? appWindowContainer : null
        onUnlockRequested: {
            if (SessionStore.checkSession()) {
                Logger.state("Shell", "locked", "unlocked");
                SessionStore.unlock();
                if (shell.pendingLaunch) {
                    Logger.info("Shell", "Executing pending launch: " + shell.pendingLaunch.appName);
                    UIStore.openApp(shell.pendingLaunch.appId, shell.pendingLaunch.appName, "");
                    shell.pendingLaunch = null;
                }
            } else {
                Logger.state("Shell", "locked", "pinEntry");
                shell.showPinScreen = true;
                pinScreen.show();
            }
        }
        onNotificationTapped: function (notifId, appId, title) {
            Logger.info("Shell", "Lock screen notification tapped: " + title + " (id: " + notifId + ", app: " + appId + ")");
            if (SessionStore.checkSession()) {
                Logger.info("Shell", "Session valid, unlocking and navigating to notification");
                SessionStore.unlock();
                NotificationService.clickNotification(notifId);
            } else {
                Logger.info("Shell", "Session expired, requesting PIN");
                shell.pendingNotification = {
                    "id": notifId,
                    "appId": appId,
                    "title": title
                };
                shell.showPinScreen = true;
                pinScreen.show();
            }
        }
        onHubRequested: {
            if (SessionStore.checkSession()) {
                SessionStore.unlock();
                peekFlow.openPeek();
            } else {
                shell.pendingHub = true;
                shell.showPinScreen = true;
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
                shell.pendingLaunch = {
                    "appId": "camera",
                    "appName": "Camera"
                };
                shell.showPinScreen = true;
                pinScreen.show();
            }
            HapticManager.medium();
        }
        onPhoneLaunched: {
            Logger.info("LockScreen", "Phone quick action tapped");
            if (SessionStore.checkSession()) {
                SessionStore.unlock();
                UIStore.openApp("phone", "Phone", "");
            } else {
                Logger.info("LockScreen", "Session locked - requesting PIN for Phone");
                shell.pendingLaunch = {
                    "appId": "phone",
                    "appName": "Phone"
                };
                shell.showPinScreen = true;
                pinScreen.show();
            }
            HapticManager.medium();
        }
    }

    // Shell-level fallback for the marathon-dev DBus unlock path:
    // SecurityManager emits authenticationSuccess regardless of which
    // surface initiated auth (PinScreen tap OR DBus AuthenticateQuickPIN).
    // PinScreen.qml has its own Connections, but its handler chains
    // through a 350 ms unlockDelayTimer → pinCorrect → SessionStore.unlock
    // — fine when the user is actively entering a PIN, but for scripted
    // unlocks via the DBus we want the lock surface to dismiss
    // immediately. Belt-and-braces: clear showLockScreen here too. If
    // both handlers fire, setShowLockScreen(false) twice is a no-op.
    Connections {
        target: SecurityManagerCpp
        function onAuthenticationSuccess() {
            if (SessionStore.isLocked && !shell.showPinScreen)
                SessionStore.unlock();
        }
        // The PIN was just typed at startup; don't ask for it twice.
        function onBootUnlockedChanged() {
            if (SecurityManagerCpp.bootUnlocked && SessionStore.isLocked)
                SessionStore.unlock();
        }
    }

    MarathonPinScreen {
        id: pinScreen

        anchors.fill: parent
        z: Constants.zIndexPinScreen
        onPinCorrect: {
            Logger.state("Shell", "pinEntry", "unlocked");
            shell.showPinScreen = false;
            pinScreen.reset();
            SessionStore.unlock();
            if (shell.pendingLaunch) {
                Logger.info("Shell", "Executing pending launch: " + shell.pendingLaunch.appName);
                UIStore.openApp(shell.pendingLaunch.appId, shell.pendingLaunch.appName, "");
                shell.pendingLaunch = null;
            }
            if (shell.pendingHub) {
                shell.pendingHub = false;
                peekFlow.openPeek();
            }
            if (shell.pendingNotification) {
                Logger.info("Shell", "Executing pending notification action: " + shell.pendingNotification.title);
                NotificationService.clickNotification(shell.pendingNotification.id);

                shell.pendingNotification = null;
            }
        }
        onCancelled: {
            Logger.info("PinScreen", "Cancelled by user");
            shell.showPinScreen = false;
            lockScreen.swipeProgress = 0;
            pinScreen.reset();
            if (shell.pendingLaunch) {
                Logger.info("Shell", "Clearing pending launch");
                shell.pendingLaunch = null;
            }
            if (shell.pendingNotification) {
                Logger.info("Shell", "Clearing pending notification action");
                shell.pendingNotification = null;
            }
        }
    }

    NotificationToast {
        id: notificationToast

        backdropSource: UIStore.appWindowOpen ? appWindowContainer : null

        Connections {
            function onNotificationReceived(notification) {
                // Do Not Disturb suppresses the auto-popup banner (audio +
                // haptic are already muted at emit time in the C++ service).
                // Without this gate DND still flashed a toast for every
                // notification, so the toggle only half-worked.
                if (NotificationService.isDndEnabled)
                    return;
                // The Hub already lists it, under where the banner would cover its header.
                if (peekFlow.peekProgress > 0 || (!UIStore.appWindowOpen && pageView.currentIndex === 0))
                    return;
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
            function onLevelChanged() {
                systemHUD.showVolume(AudioManagerCpp.volume);
            }

            target: AudioManagerCpp
        }

        Connections {
            // Manual-only: fires on setBrightnessFromUser, not on ambient
            // auto-brightness or idle-dim (those use the silent setter).
            function onUserBrightnessChanged(value) {
                if (systemHUD.initialized)
                    systemHUD.showBrightness(value / 100);
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
            function onShowConfirmDialog(title, message, onConfirm, confirmText) {
                confirmDialog.show(title, message, onConfirm, confirmText);
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
            if (UIStore.appWindowOpen)
                appWindow.focusApp();
            else
                shell.forceActiveFocus();
        }
        onResultSelected: result => {
            UnifiedSearchService.executeSearchResult(result);
            UIStore.closeSearch();
        }
    }

    ScreenshotPreview {
        id: screenshotPreview
    }

    Connections {
        function onSettingRequested(settingId) {
            Router.navigateToSetting(settingId);
        }

        target: UnifiedSearchService
    }

    Connections {
        function onScreenshotCaptured(filePath, thumbnailPath) {
            Logger.info("Shell", "Screenshot captured: " + filePath);
            screenshotPreview.show(filePath, thumbnailPath);
            HapticManager.medium();
        }

        function onScreenshotFailed(error) {
            Logger.error("Shell", "Screenshot failed: " + error);
        }

        target: ScreenshotService
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

    AppToast {
        id: appToast
    }

    ShareSheet {
        id: shareSheet

        onChosen: id => ShareService.choose(id)
        onDismissed: ShareService.cancel()
    }

    FilePickerSheet {
        id: filePicker

        onAccepted: (paths, filterIndex, choices) => FileChooserPortal.accept(paths, filterIndex, choices)
        onCancelled: FileChooserPortal.cancel()
    }

    Connections {
        function onRequested(request) {
            filePicker.open(request);
        }

        function onClosed() {
            filePicker.close();
        }

        // Only with a session bus (main.cpp).
        target: typeof FileChooserPortal !== "undefined" ? FileChooserPortal : null
    }

    Connections {
        function onRequested(request) {
            shareSheet.open(request);
        }

        function onTargetsAdded(targets) {
            shareSheet.addTargets(targets);
        }

        // Only with a session bus (main.cpp).
        target: typeof ShareService !== "undefined" ? ShareService : null
    }

    Connections {
        function onToastRequested(notification) {
            appToast.show(notification);
        }

        // Only with a session bus (main.cpp).
        target: typeof FreedesktopNotifications !== "undefined" ? FreedesktopNotifications : null
    }

    Comp.PermissionDialog {
        id: permissionDialog

        z: Constants.zIndexModalOverlay + 50
    }

    // A permission prompt is a system modal and has to own input while it is
    // up. Browser focuses its URL bar as it loads, which raised the on-screen
    // keyboard straight over the dialog: the prompt was cut off mid-sentence
    // and Deny/Allow sat behind the keyboard with no way to reach them, and
    // no way to dismiss the prompt either. Retract the keyboard whenever a
    // prompt opens -- shell-side, so it holds for every app rather than
    // depending on each one not focusing a field at the wrong moment.
    Connections {
        target: PermissionManager
        function onPromptActiveChanged() {
            if (PermissionManager.promptActive && virtualKeyboard.active) {
                Logger.info("Shell", "Retracting keyboard for permission prompt");
                virtualKeyboard.active = false;
            }
        }
    }

    Connections {
        function onWifiConnectedChanged() {
            if (NetworkManagerCpp.wifiConnected)
                connectionToast.show(qsTr("Connected to %1").arg(NetworkManagerCpp.wifiSsid), "wifi");
            else if (NetworkManagerCpp.wifiEnabled)
                connectionToast.show(qsTr("Wi-Fi disconnected"), "wifi-slash");
        }

        // Emitted just after wifiConnectedChanged when the network is new.
        function onWifiSsidChanged() {
            if (NetworkManagerCpp.wifiConnected)
                connectionToast.show(qsTr("Connected to %1").arg(NetworkManagerCpp.wifiSsid), "wifi");
        }

        function onEthernetConnectedChanged() {
            if (NetworkManagerCpp.ethernetConnected)
                connectionToast.show("Connected to Ethernet", "plug-zap");
            else if (!NetworkManagerCpp.ethernetConnected && !NetworkManagerCpp.wifiConnected)
                connectionToast.show("No network connection", "wifi-slash");
        }

        target: NetworkManagerCpp
    }

    Connections {
        function onIsHotspotOnChanged() {
            if (SystemControlStore.isHotspotOn)
                connectionToast.show(SystemControlStore.hotspotSsid + " · " + SystemControlStore.hotspotPassword, "broadcast");
        }

        function onHotspotFailed(message) {
            errorToast.show("Hotspot didn't start", message, "broadcast");
        }

        target: SystemControlStore
    }

    Connections {
        function onBatteryWarning(title, body, iconName, hapticLevel) {
            if (errorToast)
                errorToast.show(title, body, iconName);

            if (hapticLevel >= 3)
                HapticManager.heavy();
            else if (hapticLevel === 2)
                HapticManager.medium();
            else if (hapticLevel === 1)
                HapticManager.light();
        }

        function onEmergencyShutdownArmed(secondsUntilShutdown) {
            criticalBatteryShutdownTimer.interval = Math.max(0, secondsUntilShutdown * 1000);
            criticalBatteryShutdownTimer.start();
        }

        function onEmergencyShutdownDisarmed() {
            criticalBatteryShutdownTimer.stop();
        }

        target: PowerPolicyControllerCpp
    }

    Timer {
        id: criticalBatteryShutdownTimer

        interval: 10000
        repeat: false
        onTriggered: {
            Logger.error("Battery", "Emergency critical power action due to battery");
            PowerPolicyControllerCpp.performCriticalPowerAction();
        }
    }

    Timer {
        id: bluetoothReconnectTimer

        interval: 5000
        repeat: false
        onTriggered: {
            if (BluetoothManagerCpp.enabled) {
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

    // WEA / ETWS / CMAS emergency cell broadcasts. Layered above lock
    // screen + PIN entry so an Amber Alert that fires while the device
    // is locked still displays — see component header for FCC §10.500
    // rules on non-dismissable categories. Visibility is bound to
    // CellBroadcastManagerCpp.activeBroadcasts; manager stays dormant
    // on devices without a 3GPP modem.
    MarathonCellBroadcastOverlay {
        id: cellBroadcastOverlay
    }

    // Lock-screen WiFi / captive-portal credential prompt. Currently
    // inert — only surfaces when something calls
    // lockScreenNetworkAgent.show(ssid, security). r201+ will wire it
    // to NetworkManagerCpp's secret-needed signal.
    //
    // The component self-gates on `agent.active` (visible: active).
    // Do NOT add an outer `visible:` binding here — it overrides the
    // internal one and surfaces the scrim + card permanently whenever
    // the lock screen is visible, which is the regression filed by the
    // user against r253 ("sign into wifi" dialog stuck on lock).
    MarathonLockScreenNetworkAgent {
        id: lockScreenNetworkAgent
    }

    // Never needed again once setup is done, so it isn't built.
    Loader {
        anchors.fill: parent
        z: Constants.zIndexModalOverlay
        active: !SettingsManagerCpp.firstRunComplete
        sourceComponent: MarathonOOBE {
            // The passcode was just entered twice; land on the home screen.
            onSetupComplete: {
                Logger.info("Shell", "OOBE setup completed");
                SessionStore.unlock();
            }
        }
    }

    Connections {
        function onAlarmTriggered(id, label) {
            var alarm = {
                "id": id,
                "label": label
            };
            Logger.info("Shell", "Alarm triggered: " + (label ? label : "(unknown)"));
            dimState.restore();
            alarmOverlay.show(alarm);
            HapticManager.heavy();
        }

        target: AlarmManagerCpp
    }

    VirtualKeyboard {
        id: virtualKeyboard

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        // The keyboard sits above the lock screen: put it away on locking.
        Connections {
            target: SessionStore
            function onIsLockedChanged() {
                if (SessionStore.isLocked)
                    virtualKeyboard.active = false;
            }
        }
        Component.onCompleted: {
            focusConnection.target = shell.shellWindow;
        }

        Connections {
            id: focusConnection

            function onActiveFocusItemChanged() {
                var item = shell.shellWindow ? shell.shellWindow["activeFocusItem"] : null;
                if (!item) {
                    if (!InputMethodEngine.active)
                        virtualKeyboard.active = false;

                    return;
                }
                // An app's surface item: the app's own text-input state
                // decides, via the compositor's nativeTextInputPanelRequested.
                // Treating it as "not a text field" hid the keyboard each time
                // an app surface took focus, including right after it asked
                // for the keyboard.
                if (item.surface !== undefined)
                    return;
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
                else if (!virtualKeyboard.active)
                    Qt.inputMethod.hide(); // qmllint disable missing-property
            }

            function onInputItemUnfocused() {
                var item = shell.shellWindow ? shell.shellWindow["activeFocusItem"] : null;
                var isInternalInput = item && (item.toString().indexOf("TextInput") !== -1 || item.toString().indexOf("TextEdit") !== -1);
                if (!isInternalInput) {
                    Logger.info("Shell", "InputMethodEngine: Input item unfocused");
                    virtualKeyboard.active = false;
                }
            }

            target: InputMethodEngine
        }
    }

    // Going home or closing the app never leaves the keyboard over the home
    // screen or the switcher.
    Connections {
        function onAppWindowOpenChanged() {
            if (!UIStore.appWindowOpen && virtualKeyboard.active)
                virtualKeyboard.active = false;
        }

        target: UIStore
        enabled: UIStore !== null
    }

    Connections {
        function onTextInputHintsChanged() {
            if (virtualKeyboard.active)
                virtualKeyboard.refreshFieldHints();
        }

        function onNativeTextInputPanelRequested(show) {
            if (!Platform.hasHardwareKeyboard) {
                Logger.info("Shell", "Native app text input panel requested: " + show);
                if (show && !virtualKeyboard.active)
                    virtualKeyboard.active = true;
                else if (!show && virtualKeyboard.active)
                    virtualKeyboard.active = false;
            }
        }

        target: shell.compositor
        enabled: shell.compositor !== null
    }

    // Windows of an input method service's apps (Deckard's Android apps) keep
    // their size: their IME gives the app the covered height instead.
    readonly property bool appKeyboardInsetByClient: RemoteTextInput.appIdPrefix !== "" && appWindow.appId.startsWith(RemoteTextInput.appIdPrefix)
    readonly property real appKeyboardInset: appKeyboardInsetByClient ? 0 : virtualKeyboard.reservedHeight

    function reportKeyboardCover() {
        if (!appKeyboardInsetByClient)
            return;
        var covered = virtualKeyboard.reservedHeight > 0 ? appWindow.height - virtualKeyboard.mapToItem(appWindow, 0, 0).y : 0;
        RemoteTextInput.setPanel(appWindow.appId, Math.round(covered), Math.round(appWindow.height));
    }

    onAppKeyboardInsetByClientChanged: reportKeyboardCover()

    Binding {
        target: RemoteTextInput
        property: "frontAppId"
        value: UIStore.appWindowOpen ? appWindow.appId : ""
    }

    // Focus that falls back to the shell root while an app is in front (an
    // overlay closing, the window it focused going) goes to the app, or keys
    // reach type-to-search and the keyboard addresses the shell.
    Connections {
        function onActiveFocusItemChanged() {
            if (shell.Window.activeFocusItem === shell && shell.state === "app" && !UIStore.searchOpen && !UIStore.quickSettingsOpen) {
                Logger.info("Shell", "Focus fell to the shell with " + appWindow.appId + " in front; giving it back");
                Qt.callLater(appWindow.focusApp);
            }
        }

        target: shell.Window.window
    }

    Connections {
        function onReservedHeightChanged() {
            shell.reportKeyboardCover();
        }

        target: virtualKeyboard
    }

    Connections {
        function onHeightChanged() {
            shell.reportKeyboardCover();
        }

        function onAppIdChanged() {
            shell.reportKeyboardCover();
        }

        target: appWindow
    }

    Connections {
        function onHintsChanged() {
            if (virtualKeyboard.active)
                virtualKeyboard.refreshFieldHints();
        }

        function onPanelRequested(show) {
            if (show && Platform.hasHardwareKeyboard)
                return;
            if (show && !virtualKeyboard.active)
                virtualKeyboard.active = true;
            else if (!show && virtualKeyboard.active)
                virtualKeyboard.active = false;
        }

        target: RemoteTextInput
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

    // ── Night Light warm-tint overlay ─────────────────────────────
    // Marathon's shell IS the compositor, so one top-most tint item warms
    // every app surface + chrome uniformly — the scene-graph equivalent of a
    // CRTC gamma ramp (which Qt's compositor exposes no protocol for). Bound
    // to the real DisplayManager night-light state via SystemControlStore.
    // No MouseArea → never intercepts input. This is what makes the Night
    // tile actually do something on screen.
    Binding {
        target: PilotClient
        property: "watching"
        value: !SessionStore.isLocked
    }

    PilotEdgeGlow {
        id: pilotGlow

        anchors.fill: parent
        z: Constants.zIndexPilotGlow
    }

    Rectangle {
        id: nightLightOverlay
        anchors.fill: parent
        z: 900000
        color: Qt.rgba(1.0, 0.52, 0.12, 1.0)
        opacity: SystemControlStore.isNightLightOn ? 0.22 : 0.0
        visible: opacity > 0.0
        Behavior on opacity {
            NumberAnimation {
                duration: 400
                easing.type: Easing.OutCubic
            }
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

    Binding {
        target: shell.compositor
        property: "appViewportSize"
        value: Qt.size(Math.round(appWindow.width), Math.round(appWindow.height + shell.appKeyboardInset))
        when: shell.compositor !== null && appWindow.width > 0
    }

    ParallelAnimation {
        id: backExit

        NumberAnimation {
            id: backExitSlide

            target: navBar.backTracker
            property: "value"
            duration: MMotion.reduceMotion ? 0 : 180
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: appWindow
            property: "opacity"
            to: 0
            duration: MMotion.reduceMotion ? 0 : 180
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: appWindow
            property: "scale"
            to: 0.9
            duration: MMotion.reduceMotion ? 0 : 180
            easing.type: Easing.OutCubic
        }
        onFinished: {
            AppLifecycleManager.minimizeForegroundApp();
            UIStore.closeApp();
            navBar.backTracker.value = 0;
            appWindow.opacity = 1;
            appWindow.scale = 1;
        }
    }

    PowerMenu {
        id: powerMenu

        onSleepRequested: {
            Logger.info("Shell", "Sleep requested from power menu");
            var locked = SessionStore.isLocked;
            var action = PowerPolicyControllerCpp.sleepAction(locked);
            if (action === PowerPolicyControllerCpp.LockThenSleep)
                SessionStore.lock();
            PowerPolicyControllerCpp.sleep("power menu sleep");
        }
        onRebootRequested: {
            Logger.info("Shell", "Reboot requested from power menu");
            PowerManagerService.restart();
        }
        onShutdownRequested: {
            Logger.info("Shell", "Shutdown requested from power menu");
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
        onLoaded: {
            item.pinShown = Qt.binding(() => shell.showPinScreen);
            shell.incomingCallOverlay = item;
            TelephonyIntegration.incomingCallOverlay = item;
        }
        onActiveChanged: {
            if (!active) {
                shell.incomingCallOverlay = null;
                TelephonyIntegration.incomingCallOverlay = null;
            }
        }
    }

    Connections {
        function onInCallChanged() {
            if (!shell.incomingCallOverlay.inCall && !shell.incomingCallOverlay.isRinging)
                shell.unloadCallOverlay();
        }

        function onUnlockRequested() {
            if (SessionStore.checkSession()) {
                SessionStore.unlock();
            } else {
                shell.showPinScreen = true;
                pinScreen.show();
            }
        }

        target: shell.incomingCallOverlay
        enabled: shell.incomingCallOverlay !== null
    }

    Connections {
        function onIncomingCallRequested(number) {
            incomingCallOverlayLoader.active = true;
        }

        function onCallOverlayDismissRequested() {
            if (shell.incomingCallOverlay) {
                shell.incomingCallOverlay.hide();
                if (shell.incomingCallOverlay.inCall)
                    return;
            }
            shell.unloadCallOverlay();
        }

        target: TelephonyIntegration
    }

    // The panel shows fewer than 8 bits per channel and nothing below us
    // dithers: break gradient bands over everything, apps included.
    Image {
        anchors.fill: parent
        // Ordered dither: an 8x8 Bayer threshold scaled to one step of the
        // panel's depth, so the panel's truncation rounds instead of bands.
        source: "file:///usr/share/marathon-shell/wallpapers/dither-bayer.png"
        fillMode: Image.Tile
        opacity: (1 << (8 - DeviceProfile.panelDepth)) / 255
        smooth: false
        cache: true
        visible: DeviceProfile.panelDepth < 8
        z: 999998
    }

    // Diagnostic live-FPS readout. Gated by MARATHON_FPS_OVERLAY env
    // (context property, default off). Green >=50, amber >=30, red below.
    // Reads ~2fps at idle (its own 500ms refresh); the real number shows
    // during scrolling/animation.
    Rectangle {
        id: fpsOverlay

        visible: typeof MARATHON_FPS_OVERLAY !== "undefined" && MARATHON_FPS_OVERLAY
        z: 999999
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Constants.statusBarHeight + 4
        anchors.rightMargin: 6
        width: fpsLabel.implicitWidth + 14
        height: fpsLabel.implicitHeight + 8
        radius: 5
        color: "#cc000000"

        Text {
            id: fpsLabel

            anchors.centerIn: parent
            text: (typeof fpsMonitor !== "undefined" ? fpsMonitor.fps.toFixed(0) : "0") + " fps"
            font.pixelSize: 15
            font.family: "monospace"
            color: {
                if (typeof fpsMonitor === "undefined")
                    return "#ffffff";
                if (fpsMonitor.fps >= 50)
                    return "#4ade80";
                if (fpsMonitor.fps >= 30)
                    return "#fbbf24";
                return "#f87171";
            }
        }
    }
}
