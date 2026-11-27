pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import "../core/Clock.js" as Clock
import "../core/Weather.js" as Weather

Item {
    id: lockScreen

    component LockWeather: Row {
        id: badge

        readonly property var current: WeatherClient.forecast.current || null
        required property color glyph
        required property color halo
        property real pixelSize: Silica.Theme.fontSizeMedium

        spacing: Silica.Theme.paddingSmall

        GlyphIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: badge.current ? Weather.glyph(badge.current.symbol, ((WeatherClient.forecast.hourly || [])[0] || {}).is_day) : ""
            size: Silica.Theme.iconSizeSmall
            color: badge.glyph
        }
        Silica.Label {
            anchors.verticalCenter: parent.verticalCenter
            text: badge.current ? Weather.temperature(badge.current.temperature, SettingsManagerCpp.fahrenheit) : ""
            font.pixelSize: badge.pixelSize
            color: badge.glyph
            style: Text.Outline
            styleColor: badge.halo
        }
    }

    // Strokes of a trackpad combination entered so far.
    property int comboLength: 0

    // The running app surface to blur behind the lock chrome, if any.
    // Set by MarathonShell.qml to appWindowContainer when an app is
    // open; null otherwise (the wallpaper renders through normally).

    property real swipeProgress: 0
    // The app whose notification stack is open; the others show their newest.
    property string expandedApp: ""
    // A finger on the sensor unlocks from here (MarathonShell listens).
    readonly property bool fingerprintReady: Security.fingerprintAvailable && Security.fingerprintBlocked === ""
    // A miss, or what the sensor asked for, in place of the hint for a moment.
    property string fingerprintNote: ""
    property bool fingerprintMissed: false
    // Finger travel that takes swipeProgress from 0 to 1.
    readonly property real swipeTravel: height * 0.15
    // Short/square screens (HackberryPi, Q25) place by height, not design px.
    readonly property bool compactLayout: Constants.isSquareScreen || Constants.screenHeight < 800
    // A tall phone: the same layout, spaced out and larger.
    readonly property bool tallLayout: !compactLayout && Constants.isTallScreen
    readonly property real dateSize: tallLayout ? Silica.Theme.fontSizeExtraLarge : Silica.Theme.fontSizeLarge
    readonly property real noteTitleSize: tallLayout ? Silica.Theme.fontSizeMedium : Silica.Theme.fontSizeSmall
    readonly property real noteTextSize: tallLayout ? Silica.Theme.fontSizeSmall : Silica.Theme.fontSizeExtraSmall
    readonly property real quickButtonSize: tallLayout ? Silica.Theme.itemSizeLarge : Silica.Theme.itemSizeSmall
    // Honour Settings → Display & Brightness → Screen Timeout for the
    // lock screen too. SettingsManager.screenTimeout==0 means "Never"
    // (handled below in idleTimer.running). Falls back to the previous
    // hard-coded 30 s when the singleton hasn't published yet.
    property int idleTimeoutMs: (typeof SettingsManagerCpp !== 'undefined' && SettingsManagerCpp.screenTimeout > 0) ? SettingsManagerCpp.screenTimeout : 30000
    readonly property int roleIsRead: roleId("isRead")
    readonly property int roleAppId: roleId("appId")
    readonly property int roleIcon: roleId("icon")
    readonly property int roleIdValue: roleId("id")
    readonly property int roleTitle: roleId("title")
    readonly property int roleBody: roleId("body")
    readonly property int roleTimestamp: roleId("timestamp")
    signal unlockRequested
    signal cameraLaunched
    signal phoneLaunched
    signal notificationTapped(int notifId, string appId, string title)
    // Idle for the screen timeout: the shell blanks the screen or shows Nightshade.
    signal idleExpired(string reason)

    function roleId(name) {
        if (!NotificationService || !name)
            return -1;

        return NotificationService.roleId(name);
    }

    function resetIdleTimer() {
        idleTimer.rearm();
    }

    // Relative-time formatter for notifications.
    // Returns 'now' / 'Nm' / 'Nh' / clock-time for older today.
    function relativeTime(ts) {
        if (!ts)
            return "";
        const now = Date.now();
        const diff = now - ts;
        if (diff < 60 * 1000)
            //: Age of a notification under a minute
            return qsTr("now");
        if (diff < 60 * 60 * 1000)
            //: Age of a notification in minutes, e.g. 5m
            return qsTr("%1m").arg(Math.floor(diff / 60000));
        if (diff < 24 * 60 * 60 * 1000)
            //: Age of a notification in hours, e.g. 3h
            return qsTr("%1h").arg(Math.floor(diff / 3600000));
        return Clock.format(new Date(ts), SettingsManagerCpp.timeFormat);
    }

    // Rebuilds the visible-notifications model from the global
    // NotificationService: every unread one, in a list that scrolls.
    function refreshNotifications() {
        unreadModel.clear();
        // Honour the "Show on Lock Screen" privacy setting. Previously this
        // toggle wrote SettingsManagerCpp.showNotificationsOnLockScreen but
        // nothing read it, so turning it off still leaked every notification
        // onto the lock surface. Gate the whole list here.
        if (typeof SettingsManagerCpp !== 'undefined' && !SettingsManagerCpp.showNotificationsOnLockScreen)
            return;
        // Stacked by app, as iOS does: the app with the newest one first,
        // each app's newest on top of its stack.
        const groups = new Map();
        for (let i = 0; i < NotificationService.rowCount(); i++) {
            const idx = NotificationService.index(i, 0);
            if (NotificationService.data(idx, roleIsRead))
                continue;
            const appId = NotificationService.data(idx, roleAppId) || "other";
            if (!groups.has(appId))
                groups.set(appId, []);
            groups.get(appId).push({
                "notifId": NotificationService.data(idx, roleIdValue) || 0,
                "appId": appId,
                "icon": NotificationService.data(idx, roleIcon) || "bell",
                "title": NotificationService.data(idx, roleTitle) || "",
                "body": NotificationService.data(idx, roleBody) || "",
                "timestamp": NotificationService.data(idx, roleTimestamp) || 0
            });
        }
        for (const stack of groups.values()) {
            stack.sort((a, b) => b.timestamp - a.timestamp);
            stack.forEach((n, i) => {
                n.stackIndex = i;
                n.stackSize = stack.length;
            });
        }
        [...groups.values()].sort((a, b) => b[0].timestamp - a[0].timestamp).forEach(stack => stack.forEach(n => unreadModel.append(n)));
        if (!groups.has(expandedApp))
            expandedApp = "";
    }

    // Each dismissal rebuilds the list, so the ids are taken first.
    function dismissNotifications(ids) {
        for (const id of ids)
            NotificationService.dismissNotification(id);
    }

    // The ids of an app's notifications on the lock screen.
    function stackIds(appId) {
        const ids = [];
        for (let i = 0; i < unreadModel.count; i++) {
            if (unreadModel.get(i).appId === appId)
                ids.push(unreadModel.get(i).notifId);
        }
        return ids;
    }

    anchors.fill: parent
    visible: opacity > 0.01
    onVisibleChanged: {
        if (visible) {
            lockScreen.expandedApp = "";
            lockScreen.refreshNotifications();
            SessionStore.isOnLockScreen = true;
        } else {
            SessionStore.isOnLockScreen = false;
        }
    }
    Component.onCompleted: {
        if (visible) {
            console.log("[LockScreen] SessionStore.isLocked =", SessionStore.isLocked);
            SessionStore.isOnLockScreen = true;
            lockScreen.refreshNotifications();
        }
    }
    // layer.enabled was true with layer.smooth — that turned the whole
    // lock screen into an offscreen FBO. Combined with the "Swipe up
    // to unlock" bobbing animation (loops: Infinite) any frame the
    // animation produced re-rasterized the FULL lock-screen texture
    // every refresh, pinning QSGRenderThread at ~37% CPU at idle (5m
    // CPU per 15m wall-clock, measured 2026-06-25). The original
    // motivation for layer.enabled was lost in the comment history;
    // disabling it drops to dirty-region rendering and the lock
    // screen sits at near-zero idle CPU.
    layer.enabled: false

    Timer {
        id: idleTimer

        interval: lockScreen.idleTimeoutMs
        // "Never" (SettingsManager.screenTimeout == 0) gates the timer off
        // — same logic as MarathonShell.idleScreenTimer. Otherwise a 0
        // interval fires every tick and blanks the lock screen immediately.
        // Locked covers the PIN pad, which hides the lock screen.
        readonly property bool armed: (lockScreen.visible || SessionStore.isLocked) && Display.screenOn && !Display.nightshade && !AlarmManagerCpp.hasActiveAlarm && (typeof SettingsManagerCpp === 'undefined' || SettingsManagerCpp.screenTimeout > 0)

        function rearm() {
            if (armed)
                restart();
            else
                stop();
        }

        repeat: false
        onArmedChanged: rearm()
        Component.onCompleted: rearm()
        // No app inhibitor holds it: nothing an app shows is visible here.
        onTriggered: {
            if (Power.hasActiveCalls) {
                Logger.warn("LockScreen", "Idle blank postponed: a call is ringing or active");
                idleTimer.rearm();
                return;
            }
            lockScreen.idleExpired("lock-screen idle timer (" + idleTimer.interval + "ms)");
        }
    }

    Connections {
        function onNotificationReceived(notification) {
            if (lockScreen.visible) {
                // Only one that sounds lights the screen: not under Do Not
                // Disturb, nor a silent, low-urgency or transient one.
                if (notification.alerts) {
                    if (!Display.screenOn)
                        Display.turnScreenOn("notification from " + notification.appId);
                    lockScreen.resetIdleTimer();
                }
                lockScreen.refreshNotifications();
            }
        }

        target: NotificationService
    }

    Connections {
        function onScreenStateChanged(isOn) {
            if (isOn && lockScreen.visible) {
                Logger.info("LockScreen", "Screen turned on - starting idle timer");
                lockScreen.resetIdleTimer();
            }
        }

        target: Display
    }

    // Only a wake brings the lock screen up; a call or notification
    // re-asserting a screen that is already on leaves the session alone.
    Connections {
        function onScreenOnChanged() {
            if (Display.screenOn)
                SessionStore.showLock();
        }

        target: Display
    }

    // Visible-cards model — populated by refreshNotifications().
    ListModel {
        id: unreadModel
    }

    Connections {
        function onCountChanged() {
            lockScreen.refreshNotifications();
        }
        function onModelReset() {
            lockScreen.refreshNotifications();
        }
        function onDataChanged() {
            lockScreen.refreshNotifications();
        }

        target: NotificationService
    }

    // The ambience's wallpaper at full strength, as on the lock
    // screen. It stays put while the content lifts, and dissolves into the
    // shell's own copy of it.
    Item {
        anchors.fill: parent
        z: 1
        opacity: 1 - lockScreen.swipeProgress

        Rectangle {
            anchors.fill: parent
            color: MColors.eink ? MColors.background : "black"
            visible: MColors.eink || lockWallpaper.status !== Image.Ready
        }
        // E-paper shows paper, not the wallpaper.
        Image {
            id: lockWallpaper

            anchors.fill: parent
            visible: !MColors.eink
            source: MColors.wallpaper(SettingsManagerCpp.wallpaperPath)
            // The home screen's size too, so both share one decoded image.
            sourceSize: Qt.size(width, height)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
    }

    Item {
        id: lockContent

        anchors.fill: parent
        z: 1
        opacity: 1 - Math.pow(lockScreen.swipeProgress, 0.7)
        transform: Translate {
            y: -lockScreen.swipeProgress * lockScreen.swipeTravel
        }

        MarathonStatusBar {
            id: statusBar

            width: parent.width
            z: 5
        }

        // Call strip under the status bar while a call is active or ringing.
        // Caller name resolves through ContactsManager, falling back to the raw number.
        Item {
            id: lockNowBar

            readonly property bool callActive: Modem.callState === "active" || Modem.callState === "ringing"
            // Wall-clock timestamp of the most recent "active" transition.
            // Reset to 0 whenever the call leaves the active state so the
            // duration flips back to "00:00".
            property double callStartedAt: 0
            property int callElapsed: 0

            function fmtElapsed() {
                const total = Math.max(0, callElapsed);
                const m = Math.floor(total / 60);
                const s = total % 60;
                return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
            }

            function callerLabel() {
                const num = Modem.activeNumber || "";
                if (!num)
                    return qsTr("Unknown");
                const svc = (typeof ContactsManager !== "undefined" && ContactsManager) ? ContactsManager : null;
                if (svc && svc.getContactByNumber) {
                    const c = svc.getContactByNumber(num);
                    if (c && c.name)
                        return c.name;
                }
                return num;
            }

            visible: callActive
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: statusBar.bottom
            anchors.leftMargin: Silica.Theme.horizontalPageMargin
            anchors.rightMargin: Silica.Theme.horizontalPageMargin
            anchors.topMargin: Silica.Theme.paddingLarge
            height: Math.max(Silica.Theme.itemSizeMedium, callText.implicitHeight + Silica.Theme.paddingMedium * 2)
            z: 6

            Connections {
                target: Modem
                function onCallStateChanged() {
                    if (Modem.callState === "active") {
                        lockNowBar.callStartedAt = Date.now();
                        lockNowBar.callElapsed = 0;
                    } else {
                        lockNowBar.callStartedAt = 0;
                        lockNowBar.callElapsed = 0;
                    }
                }
            }

            Timer {
                interval: 1000
                running: lockNowBar.visible && lockNowBar.callStartedAt > 0
                repeat: true
                onTriggered: {
                    lockNowBar.callElapsed = Math.floor((Date.now() - lockNowBar.callStartedAt) / 1000);
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: Silica.Theme.paddingMedium
                color: MColors.badge
                border.width: 1
                border.color: Silica.Theme.rgba(Silica.Theme.primaryColor, MColors.badgeEdgeOpacity)

                Rectangle {
                    id: callAvatar

                    width: Silica.Theme.iconSizeMedium
                    height: width
                    radius: width / 2
                    anchors.left: parent.left
                    anchors.leftMargin: Silica.Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    color: "transparent"
                    border.width: Math.max(1, Math.round(Silica.Theme.paddingSmall / 4))
                    border.color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.35)

                    GlyphIcon {
                        anchors.centerIn: parent
                        name: "phone"
                        size: Silica.Theme.iconSizeExtraSmall
                        color: Silica.Theme.highlightColor
                    }
                }

                Column {
                    id: callText

                    anchors.left: callAvatar.right
                    anchors.leftMargin: Silica.Theme.paddingMedium
                    anchors.right: endCallButton.left
                    anchors.rightMargin: Silica.Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter

                    Silica.Label {
                        width: parent.width
                        text: lockNowBar.callerLabel()
                        color: Silica.Theme.primaryColor
                        truncationMode: Silica.TruncationMode.Fade
                    }
                    Silica.Label {
                        //: %1 is the elapsed call time, e.g. 02:15
                        text: qsTr("Call · %1").arg(lockNowBar.fmtElapsed())
                        color: Silica.Theme.secondaryColor
                        font.pixelSize: Silica.Theme.fontSizeExtraSmall
                        font.features: ({
                                "tnum": 1
                            })
                    }
                }

                MCircularIconButton {
                    id: endCallButton

                    width: Silica.Theme.itemSizeExtraSmall
                    height: width
                    anchors.right: parent.right
                    anchors.rightMargin: Silica.Theme.paddingMedium
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "phone"
                    iconSize: Silica.Theme.iconSizeSmall
                    iconColor: Silica.Theme.errorColor
                    variant: "secondary"
                    a11yName: qsTr("End call")
                    rotation: 135
                    onClicked: {
                        Modem.hangup();
                    }
                }
            }
        }

        // The time and the date below it each take the tone of their own
        // backdrop: a clock over sky can sit above a date over land.
        WallpaperTone {
            id: clockTone

            objectName: "lockClockTone"
            x: clockColumn.x
            y: lockScroller.y + clockColumn.y - lockScroller.contentY - clockColumn.spacing
            width: clockColumn.width
            height: lockClock.height + Math.round(1.5 * clockColumn.spacing)
        }

        WallpaperTone {
            id: dateTone

            objectName: "lockDateTone"
            x: clockColumn.x
            y: lockScroller.y + clockColumn.y - lockScroller.contentY + lockClock.height + Math.round(clockColumn.spacing / 2)
            width: clockColumn.width
            height: clockColumn.height - lockClock.height + Math.round(clockColumn.spacing / 2)
        }

        // ── Clock, player and notifications ─────────────────
        // One column between the status bar and the unlock controls: the
        // clock, the player under it and the notifications. It scrolls as a
        // whole when they do not fit, the clock going up out of the way;
        // when they fit it takes no touches, and a swipe anywhere unlocks.
        Flickable {
            id: lockScroller

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: statusBar.bottom
            anchors.bottom: lockScreenBottomBar.top
            anchors.bottomMargin: Silica.Theme.paddingLarge
            contentHeight: lockStack.height
            clip: true
            interactive: contentHeight > height && !MMotion.instant
            boundsBehavior: Flickable.StopAtBounds

            MEinkScroll {
                flickable: lockScroller
            }
            z: 10

            Column {
                id: lockStack

                width: lockScroller.width
                spacing: Silica.Theme.paddingLarge * 2

                // Where the clock sits: lower with nothing below it.
                Item {
                    width: 1
                    height: Math.max(0, (lockScreen.compactLayout ? Math.round(lockScreen.height * (clockColumn.mediaActive || unreadModel.count > 0 ? 0.04 : 0.14)) : lockScreen.tallLayout ? Math.round(lockScreen.height * (clockColumn.mediaActive || unreadModel.count > 0 ? 0.06 : 0.1)) : Math.round((clockColumn.mediaActive ? 170 : 190) * Constants.scaleFactor)) - statusBar.height - lockStack.spacing)

                    Behavior on height {
                        NumberAnimation {
                            duration: MMotion.ms(MMotion.moderate)
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                // ── Clock cluster ───────────────────────────────────
                // Two layouts per the JSX: LockScreen() puts the clock at
                // top:190 / 84 px / -2 tracking; LockMedia() shifts it up
                // to top:170 / 76 px / -1.5 tracking so the media card at
                // top:360 has breathing room. Switches automatically when
                // MPRIS2Controller.hasActivePlayer flips.
                Column {
                    id: clockColumn

                    readonly property bool mediaActive: lockScreenMediaPlayer.hasMedia
                    // Re-read when the date string turns over at midnight.
                    readonly property date today: SystemStatusStore.dateString ? new Date() : new Date()

                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Constants.spacingSmall
                    width: parent.width * 0.9
                    // layer.enabled was: true (with layer.smooth) to keep the
                    // pixelSize Behavior from chattering, but on Qt 6.10 + SDF
                    // QtRendering the extra FBO + bilinear pass renders the
                    // glyphs with a ghosted secondary stroke ~3 px inside each
                    // digit. Static composition is sharp; the size animation
                    // doesn't need an extra texture pass at this scale.

                    // The lock clock: large and extra-light, the weekday and
                    // the date beneath on their own lines, all in the primary colour.
                    Silica.Label {
                        id: lockClock

                        readonly property int clockSize: Math.round(Silica.Theme.fontSizeHuge * (lockScreen.tallLayout ? (clockColumn.mediaActive ? 2.6 : 3.2) : (clockColumn.mediaActive ? 1.6 : 1.9)))

                        objectName: "lockClock"
                        text: SystemStatusStore.timeString
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        fontSizeMode: Text.HorizontalFit
                        font.pixelSize: clockSize
                        font.weight: Font.ExtraLight
                        // Display sizes set tighter; figures of one width, so the clock never shifts.
                        font.letterSpacing: -0.02 * clockSize
                        font.features: ({
                                "tnum": 1
                            })
                        color: clockTone.glyph
                        style: Text.Outline
                        styleColor: clockTone.halo
                    }

                    // The weekday shares its row with the weather; with media below,
                    // the date joins them, so the clock never takes more than two lines.
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: Silica.Theme.paddingLarge

                        Silica.Label {
                            objectName: "lockDay"
                            //: Qt date format pattern: keep the letters d, M, y; reorder or add separators only. Day and month for the lock screen date, e.g. 26 October
                            readonly property string date: Qt.formatDate(clockColumn.today, qsTr("d MMMM"))
                            //: Weekday and date on one line on the lock screen, e.g. Monday, 26 October
                            text: clockColumn.mediaActive ? qsTr("%1, %2").arg(Qt.formatDate(clockColumn.today, "dddd")).arg(date) : Qt.formatDate(clockColumn.today, "dddd")
                            anchors.verticalCenter: parent.verticalCenter
                            font.pixelSize: clockColumn.mediaActive ? Silica.Theme.fontSizeMedium : lockScreen.dateSize
                            color: dateTone.glyph
                            style: Text.Outline
                            styleColor: dateTone.halo
                        }
                        LockWeather {
                            objectName: "lockWeather"
                            glyph: dateTone.glyph
                            halo: dateTone.halo
                            pixelSize: clockColumn.mediaActive ? Silica.Theme.fontSizeMedium : lockScreen.dateSize
                            visible: current !== null
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    Silica.Label {
                        objectName: "lockDate"
                        visible: !clockColumn.mediaActive
                        text: Qt.formatDate(clockColumn.today, qsTr("d MMMM"))
                        anchors.horizontalCenter: parent.horizontalCenter
                        font.pixelSize: lockScreen.dateSize
                        color: dateTone.glyph
                        style: Text.Outline
                        styleColor: dateTone.halo
                    }
                }

                // ── Media card (LockMedia variant) ──────────────────
                // Per screens-shell.jsx:188-240 LockMedia(): absolute
                // positioned at top:360, left/right:18. Visible only when
                // MPRIS reports an active player — no card when nothing is
                // playing (the LockScreen variant takes over).
                MediaPlaybackManager {
                    id: lockScreenMediaPlayer

                    x: Silica.Theme.horizontalPageMargin - Silica.Theme.paddingMedium
                    width: parent.width - 2 * x
                    visible: hasMedia
                }

                // ── Notifications ───────────────────────────────────
                // Every unread one, stacked by app: tap a stack to open it.
                Column {
                    id: notificationColumn

                    x: Silica.Theme.horizontalPageMargin
                    width: parent.width - 2 * x
                    spacing: lockScreen.tallLayout ? Silica.Theme.paddingLarge : Silica.Theme.paddingMedium
                    visible: unreadModel.count > 0

                    Repeater {
                        model: unreadModel

                        delegate: Item {
                            id: notifCard

                            required property int index
                            required property int notifId
                            required property string appId
                            required property string icon
                            required property string title
                            required property string body
                            required property var timestamp
                            required property int stackIndex
                            required property int stackSize

                            readonly property bool expanded: lockScreen.expandedApp === appId
                            // The top of a closed stack stands for all of it.
                            readonly property bool stacked: stackSize > 1 && !expanded
                            readonly property real headerHeight: expanded && stackIndex === 0 && stackSize > 1 ? lessLabel.implicitHeight + Silica.Theme.paddingMedium : 0
                            // Swiped right it goes, as in the Hub.
                            property real collapse: 1

                            width: notificationColumn.width
                            height: (headerHeight + cardBody.height) * collapse
                            visible: stackIndex === 0 || expanded
                            clip: collapse < 1

                            SequentialAnimation {
                                id: dismissAnimation

                                NumberAnimation {
                                    target: cardBody
                                    property: "x"
                                    to: notifCard.width
                                    duration: MMotion.ms(MMotion.quick)
                                    easing.type: Easing.OutCubic
                                }
                                NumberAnimation {
                                    target: notifCard
                                    property: "collapse"
                                    to: 0
                                    duration: MMotion.ms(MMotion.quick)
                                    easing.type: Easing.InOutQuad
                                }
                                ScriptAction {
                                    script: lockScreen.dismissNotifications(notifCard.stacked ? lockScreen.stackIds(notifCard.appId) : [notifCard.notifId])
                                }
                            }

                            NumberAnimation {
                                id: snapBack

                                target: cardBody
                                property: "x"
                                to: 0
                                duration: MMotion.ms(MMotion.quick)
                                easing.type: Easing.OutCubic
                            }

                            Item {
                                width: parent.width
                                height: notifCard.headerHeight
                                visible: height > 0
                                z: 2

                                Silica.Label {
                                    id: lessLabel
                                    anchors.right: parent.right
                                    text: qsTr("Show less")
                                    color: Silica.Theme.highlightColor
                                    font.pixelSize: Silica.Theme.fontSizeExtraSmall
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        HapticManager.light();
                                        lockScreen.expandedApp = "";
                                    }
                                }
                            }

                            Item {
                                id: cardBody

                                y: notifCard.headerHeight
                                width: parent.width
                                height: cardContent.implicitHeight + Silica.Theme.paddingMedium * 2

                                // On the ambience, as in the Hub: pressed, a rounded inset highlight.
                                MPressHighlight {
                                    anchors.fill: parent
                                    anchors.leftMargin: -Silica.Theme.paddingSmall
                                    anchors.rightMargin: -Silica.Theme.paddingSmall
                                    down: notifArea.pressed && !notifArea.swiping
                                }

                                Row {
                                    id: cardContent
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Silica.Theme.paddingLarge

                                    Rectangle {
                                        id: notifIcon
                                        width: lockScreen.tallLayout ? Silica.Theme.iconSizeLarge : Silica.Theme.iconSizeMedium
                                        height: width
                                        radius: width / 2
                                        color: Silica.Theme.rgba(Silica.Theme.highlightColor, 0.16)

                                        NotificationIcon {
                                            anchors.centerIn: parent
                                            source: notifCard.icon
                                            size: hasImage ? notifIcon.width : lockScreen.tallLayout ? Silica.Theme.iconSizeSmall : Silica.Theme.iconSizeExtraSmall
                                            color: Silica.Theme.highlightColor
                                        }
                                    }

                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - notifIcon.width - parent.spacing

                                        Item {
                                            width: parent.width
                                            height: nameText.implicitHeight

                                            Silica.Label {
                                                id: nameText
                                                anchors.left: parent.left
                                                anchors.right: timeText.left
                                                anchors.rightMargin: Silica.Theme.paddingMedium
                                                text: notifCard.title
                                                color: Silica.Theme.primaryColor
                                                font.pixelSize: lockScreen.noteTitleSize
                                                font.weight: Font.DemiBold
                                                truncationMode: Silica.TruncationMode.Fade
                                            }
                                            Silica.Label {
                                                id: timeText
                                                anchors.right: parent.right
                                                anchors.verticalCenter: nameText.verticalCenter
                                                text: lockScreen.relativeTime(notifCard.timestamp)
                                                color: Silica.Theme.secondaryColor
                                                font.pixelSize: lockScreen.noteTextSize
                                                font.features: ({
                                                        "tnum": 1
                                                    })
                                            }
                                        }

                                        Silica.Label {
                                            width: parent.width
                                            text: notifCard.body
                                            color: Silica.Theme.secondaryColor
                                            font.pixelSize: lockScreen.noteTextSize
                                            elide: Text.ElideRight
                                            maximumLineCount: 2
                                            wrapMode: Text.WordWrap
                                            visible: text.length > 0
                                        }

                                        Silica.Label {
                                            //: Notifications beneath the top one in an app's stack
                                            text: qsTr("%n more", "", notifCard.stackSize - 1)
                                            color: Silica.Theme.highlightColor
                                            font.pixelSize: lockScreen.noteTextSize
                                            visible: notifCard.stacked
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: notifArea

                                property real pressX: 0
                                property real pressY: 0
                                property bool swiping: false
                                property bool swiped: false

                                anchors.fill: parent
                                enabled: !dismissAnimation.running
                                onPressed: mouse => {
                                    const moving = snapBack.running || cardBody.x > 0;
                                    snapBack.stop();
                                    pressX = mouse.x - cardBody.x;
                                    pressY = mouse.y;
                                    swiping = moving;
                                    preventStealing = moving;
                                    swiped = false;
                                }
                                onPositionChanged: mouse => {
                                    const dx = mouse.x - pressX;
                                    // Claimed before the scroller or the unlock swipe can take it.
                                    if (!swiping && dx > Application.styleHints.startDragDistance / 2 && dx > 2 * Math.abs(mouse.y - pressY)) {
                                        swiping = true;
                                        preventStealing = true;
                                    }
                                    if (swiping)
                                        cardBody.x = Math.max(0, dx);
                                }
                                onReleased: {
                                    if (!swiping)
                                        return;
                                    swiped = true;
                                    swiping = false;
                                    preventStealing = false;
                                    if (cardBody.x > notifCard.width / 3)
                                        dismissAnimation.start();
                                    else
                                        snapBack.start();
                                }
                                onCanceled: {
                                    swiping = false;
                                    preventStealing = false;
                                    snapBack.start();
                                }
                                onClicked: {
                                    if (swiped)
                                        return;
                                    HapticManager.light();
                                    if (notifCard.stacked)
                                        lockScreen.expandedApp = notifCard.appId;
                                    else
                                        lockScreen.notificationTapped(notifCard.notifId, notifCard.appId, notifCard.title);
                                }
                            }
                        }
                    }
                }
            }

            Silica.VerticalScrollDecorator {}
        }

        // A dot for each stroke of a trackpad combination, where the hint was.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Silica.Theme.paddingLarge * 2
            spacing: Silica.Theme.paddingMedium
            visible: lockScreen.comboLength > 0
            z: 11

            Repeater {
                model: lockScreen.comboLength

                Rectangle {
                    width: Silica.Theme.paddingMedium
                    height: width
                    radius: width / 2
                    color: Silica.Theme.primaryColor
                }
            }
        }

        // Phone and camera shortcuts in the bottom corners, with the
        // unlock hint between them.
        Item {
            id: lockScreenBottomBar

            // Quick settings open over the lock screen: its controls wait.
            visible: UIStore.quickSettingsHeight === 0

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: Silica.Theme.horizontalPageMargin
            anchors.rightMargin: Silica.Theme.horizontalPageMargin
            anchors.bottomMargin: lockScreen.tallLayout ? Silica.Theme.paddingLarge * 2 : Silica.Theme.paddingLarge
            height: lockScreen.quickButtonSize
            z: 10

            MCircularIconButton {
                width: lockScreen.quickButtonSize
                height: width
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                iconName: "phone"
                iconSize: lockScreen.tallLayout ? Silica.Theme.iconSizeMedium : Silica.Theme.iconSizeSmall
                variant: "secondary"
                a11yName: qsTr("Phone")
                onClicked: {
                    Logger.info("LockScreen", "Phone quick action tapped");
                    lockScreen.phoneLaunched();
                }
            }

            MCircularIconButton {
                width: lockScreen.quickButtonSize
                height: width
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconName: "camera"
                iconSize: lockScreen.tallLayout ? Silica.Theme.iconSizeMedium : Silica.Theme.iconSizeSmall
                variant: "secondary"
                a11yName: qsTr("Camera")
                onClicked: {
                    Logger.info("LockScreen", "Camera quick action tapped");
                    lockScreen.cameraLaunched();
                }
            }
        }

        WallpaperTone {
            id: hintTone

            // Clear of the chevron's bob.
            x: unlockHint.x
            y: unlockHint.y - 2 * unlockHint.spacing
            width: unlockHint.width
            height: unlockHint.height + 3 * unlockHint.spacing
        }

        Column {
            id: unlockHint

            objectName: "unlockHint"
            visible: UIStore.quickSettingsHeight === 0 && lockScreen.comboLength === 0

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: lockScreen.tallLayout ? Silica.Theme.paddingLarge * 2 + (lockScreen.quickButtonSize - height) / 2 : Silica.Theme.paddingLarge
            spacing: Silica.Theme.paddingSmall
            z: 11
            transform: Translate {
                id: missShake
            }

            GlyphIcon {
                objectName: "unlockGlyph"
                name: lockScreen.fingerprintReady ? "fingerprint" : "chevron-up"
                size: lockScreen.tallLayout ? Silica.Theme.iconSizeMedium : Silica.Theme.iconSizeSmall
                color: lockScreen.fingerprintMissed ? Silica.Theme.errorColor : hintTone.glyph
                anchors.horizontalCenter: parent.horizontalCenter

                SequentialAnimation on y {
                    // One bob each time the lock screen appears, then rest: it
                    // is seen on every wake, and any running animation makes
                    // the scene graph redraw the whole screen every frame.
                    // The fingerprint glyph is a place to touch: it stays still.
                    running: MMotion.gate(lockScreen.visible) && !lockScreen.fingerprintReady
                    loops: 1

                    NumberAnimation {
                        to: -Silica.Theme.paddingSmall
                        duration: MMotion.ms(800)
                        easing.type: Easing.InOutQuad
                    }

                    NumberAnimation {
                        to: 0
                        duration: MMotion.ms(800)
                        easing.type: Easing.InOutQuad
                    }
                }
            }

            Silica.Label {
                objectName: "unlockLabel"
                text: lockScreen.fingerprintNote || (lockScreen.fingerprintReady ? qsTr("Touch the sensor or swipe up") : qsTr("Swipe up to unlock"))
                color: hintTone.glyph
                style: Text.Outline
                styleColor: hintTone.halo
                font.pixelSize: lockScreen.tallLayout ? Silica.Theme.fontSizeMedium : Silica.Theme.fontSizeExtraSmall
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    Connections {
        function onFingerprintMismatch(message) {
            HapticManager.heavy();
            lockScreen.fingerprintMissed = true;
            lockScreen.fingerprintNote = message;
            noteTimer.restart();
            if (!MMotion.reduceMotion)
                missShakeAnimation.restart();
        }

        function onBiometricPrompt(message) {
            lockScreen.fingerprintMissed = false;
            lockScreen.fingerprintNote = message;
            noteTimer.restart();
        }

        // Too many misses: the PIN is next.
        function onAuthenticationFailed(reason) {
            if (!lockScreen.visible)
                return;
            lockScreen.fingerprintMissed = true;
            lockScreen.fingerprintNote = reason;
            noteTimer.restart();
        }

        target: Security
    }

    Timer {
        id: noteTimer

        interval: 2500
        onTriggered: {
            lockScreen.fingerprintNote = "";
            lockScreen.fingerprintMissed = false;
        }
    }

    SequentialAnimation {
        id: missShakeAnimation

        NumberAnimation {
            target: missShake
            property: "x"
            to: Silica.Theme.paddingSmall
            duration: 40
        }

        NumberAnimation {
            target: missShake
            property: "x"
            to: -Silica.Theme.paddingSmall
            duration: 80
        }

        NumberAnimation {
            target: missShake
            property: "x"
            to: 0
            duration: 40
        }
    }

    MouseArea {
        property real startY: 0
        property real base: 0
        property bool isDragging: false

        anchors.fill: parent
        z: 0
        propagateComposedEvents: true
        onPressed: mouse => {
            startY = mouse.y;
            isDragging = false;
            if (unlockDrag.unlocking)
                return;
            unlockDrag.value = lockScreen.swipeProgress * lockScreen.swipeTravel;
            unlockDrag.press();
            base = unlockDrag.value;
            lockScreen.resetIdleTimer();
        }
        onPositionChanged: mouse => {
            const totalDelta = startY - mouse.y;
            if (totalDelta > Qt.styleHints.startDragDistance) {
                isDragging = true;
                mouse.accepted = true;
            }
            if (isDragging && !unlockDrag.unlocking)
                unlockDrag.move(Math.max(0, Math.min(lockScreen.swipeTravel, base + totalDelta)));
        }
        // The swipe can unlock (or bring up the PIN pad) inside onReleased;
        // its composed click must not then land on whatever is now under the finger.
        onClicked: mouse => mouse.accepted = isDragging
        onReleased: mouse => {
            if (unlockDrag.unlocking)
                return;
            if (isDragging) {
                if (unlockDrag.release()) {
                    HapticManager.medium();
                    unlockDrag.unlocking = true;
                    unlockDrag.settleTo(lockScreen.swipeTravel);
                } else {
                    unlockDrag.settleTo(0);
                }
            } else {
                unlockDrag.release();
                Logger.info("LockScreen", "Tap detected (no drag), x=" + mouse.x + ", y=" + mouse.y);
            }
        }
    }

    GestureTracker {
        id: unlockDrag

        property bool unlocking: false

        to: lockScreen.swipeTravel
        commitDistance: 0.15 * Math.min(lockScreen.width, lockScreen.height)
        settleDuration: MMotion.reduceMotion ? MMotion.micro : MMotion.moderate
        onValueChanged: if (unlockDrag.active || unlockDrag.settling)
            lockScreen.swipeProgress = unlockDrag.progress
        onWillCommitChanged: if (unlockDrag.active)
            HapticManager.tick()
        onSettled: {
            if (!unlockDrag.unlocking)
                return;
            unlockDrag.unlocking = false;
            Logger.state("LockScreen", "unlocked", "dissolve complete");
            lockScreen.unlockRequested();
        }
    }
}
