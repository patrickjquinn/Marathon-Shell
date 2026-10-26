pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica
import "../core/Clock.js" as Clock

Item {
    id: lockScreen

    // The running app surface to blur behind the lock chrome, if any.
    // Set by MarathonShell.qml to appWindowContainer when an app is
    // open; null otherwise (the wallpaper renders through normally).
    property Item appBackdrop: null
    property var compositor: null

    property real swipeProgress: 0
    // Finger travel that takes swipeProgress from 0 to 1.
    readonly property real swipeTravel: height * 0.15
    // Short/square screens (HackberryPi, Q25) place by height, not design px.
    readonly property bool compactLayout: Constants.isSquareScreen || Constants.screenHeight < 800
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
    // Max notification cards shown directly; remainder collapse
    // into the 'N more notifications' row.
    readonly property int maxNotificationsShown: 2
    // Fewer when the cards would run into the unlock controls.
    property int shownLimit: maxNotificationsShown

    signal unlockRequested
    signal cameraLaunched
    signal phoneLaunched
    signal notificationTapped(int notifId, string appId, string title)
    signal hubRequested

    function roleId(name) {
        if (!NotificationService || !name)
            return -1;

        return NotificationService.roleId(name);
    }

    function resetIdleTimer() {
        idleTimer.rearm();
    }

    // Relative-time formatter for notification cards.
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
    // NotificationService — keeps only the first `maxNotificationsShown`
    // unread items so the lock surface stays calm. The remainder are
    // surfaced via the 'N more' card, which opens the Hub.
    function refreshNotifications(keepLimit) {
        if (!keepLimit)
            shownLimit = maxNotificationsShown;
        unreadModel.clear();
        // Honour the "Show on Lock Screen" privacy setting. Previously this
        // toggle wrote SettingsManagerCpp.showNotificationsOnLockScreen but
        // nothing read it, so turning it off still leaked every notification
        // onto the lock surface. Gate the whole list here.
        if (typeof SettingsManagerCpp !== 'undefined' && !SettingsManagerCpp.showNotificationsOnLockScreen) {
            moreCount = 0;
            return;
        }
        let unread = 0;
        for (let i = 0; i < NotificationService.rowCount(); i++) {
            const idx = NotificationService.index(i, 0);
            if (NotificationService.data(idx, roleIsRead))
                continue;
            if (unread < shownLimit) {
                unreadModel.append({
                    "notifId": NotificationService.data(idx, roleIdValue) || 0,
                    "appId": NotificationService.data(idx, roleAppId) || "other",
                    "icon": NotificationService.data(idx, roleIcon) || "bell",
                    "title": NotificationService.data(idx, roleTitle) || "",
                    "body": NotificationService.data(idx, roleBody) || "",
                    "timestamp": NotificationService.data(idx, roleTimestamp) || 0
                });
            }
            unread++;
        }
        moreCount = Math.max(0, unread - shownLimit);
    }

    function fitNotifications() {
        const limit = lockScreenBottomBar.mapToItem(notificationStack.parent, 0, 0).y - Silica.Theme.paddingLarge;
        if (notificationStack.y + notificationStack.height > limit && shownLimit > 1) {
            shownLimit--;
            refreshNotifications(true);
        }
    }

    property int moreCount: 0

    anchors.fill: parent
    visible: opacity > 0.01
    onVisibleChanged: {
        if (visible) {
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
        readonly property bool armed: lockScreen.visible && Display.screenOn && !AlarmManagerCpp.hasActiveAlarm && (typeof SettingsManagerCpp === 'undefined' || SettingsManagerCpp.screenTimeout > 0)

        function rearm() {
            if (armed)
                restart();
            else
                stop();
        }

        repeat: false
        onArmedChanged: rearm()
        Component.onCompleted: rearm()
        onTriggered: {
            if (lockScreen.compositor && lockScreen.compositor.hasIdleInhibitingSurface) {
                Logger.info("LockScreen", "Idle inhibitor active (video playback?) - postponing screen blank");
                idleTimer.rearm();
                return;
            }
            if (Power.hasActiveCalls) {
                Logger.info("LockScreen", "Call ringing or active - postponing screen blank");
                idleTimer.rearm();
                return;
            }
            Logger.info("LockScreen", "Idle timeout - blanking screen");
            Display.turnScreenOff("lock-screen idle timer (" + idleTimer.interval + "ms)");
        }
    }

    Connections {
        function onNotificationReceived(notification) {
            if (lockScreen.visible) {
                Logger.info("LockScreen", "New notification: " + notification.title);
                // Under Do Not Disturb, never light the screen for a
                // notification — waking the display is the single most
                // disruptive thing DND is supposed to prevent. Still refresh
                // the list quietly so it's there when the user wakes it.
                if (!NotificationService.isDndEnabled) {
                    if (!Display.screenOn)
                        Display.turnScreenOn();
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
            color: "black"
            visible: lockWallpaper.status !== Image.Ready
        }
        Image {
            id: lockWallpaper

            anchors.fill: parent
            source: SettingsManagerCpp.wallpaperPath
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }

        MGlassBackdrop {
            id: glassBackdrop

            anchors.fill: parent
        }

        AppBackdropBlur {
            anchors.fill: parent
            source: lockScreen.appBackdrop
            blurAmount: 1.0
            // 24 instead of 64 — see AppBackdropBlur.qml. A wider kernel
            // is invisible past ~24 on a 540×1140 screen but quadruples
            // fillrate on etnaviv.
            blurMax: MBlur.lg
            blurMultiplier: 1.4
            saturation: 0.4
            brightness: -0.15
            tint: Qt.rgba(0, 0, 0, 0.25)
            // The lock screen sits over an app that has been frozen by
            // AppLifecycleManager — its surface texture does not change.
            // Sample once, then stop.
            live: false
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
                color: Silica.Theme.rgba("black", 0.85)
                border.width: 1
                border.color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.1)

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

        WallpaperTone {
            id: clockTone

            objectName: "lockClockTone"
            x: clockColumn.x
            y: clockColumn.y - clockColumn.spacing
            width: clockColumn.width
            height: clockColumn.height + 2 * clockColumn.spacing
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
            anchors.top: parent.top
            anchors.topMargin: lockScreen.compactLayout ? Math.round(lockScreen.height * (mediaActive ? 0.06 : 0.14)) : Math.round((mediaActive ? 170 : 190) * Constants.scaleFactor)
            // layer.enabled was: true (with layer.smooth) to keep the
            // pixelSize Behavior from chattering, but on Qt 6.10 + SDF
            // QtRendering the extra FBO + bilinear pass renders the
            // glyphs with a ghosted secondary stroke ~3 px inside each
            // digit. Static composition is sharp; the size animation
            // doesn't need an extra texture pass at this scale.

            Behavior on anchors.topMargin {
                NumberAnimation {
                    duration: MMotion.moderate
                    easing.type: Easing.OutCubic
                }
            }

            // The lock clock: large and extra-light, the weekday and
            // the date beneath on their own lines, all in the primary colour.
            Silica.Label {
                objectName: "lockClock"
                text: SystemStatusStore.timeString
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                fontSizeMode: Text.HorizontalFit
                font.pixelSize: Math.round(Silica.Theme.fontSizeHuge * (clockColumn.mediaActive ? 1.6 : 1.9))
                font.weight: Font.ExtraLight
                color: clockTone.glyph
                style: Text.Outline
                styleColor: clockTone.halo
            }

            Silica.Label {
                text: Qt.formatDate(clockColumn.today, "dddd")
                anchors.horizontalCenter: parent.horizontalCenter
                font.pixelSize: clockColumn.mediaActive ? Silica.Theme.fontSizeMedium : Silica.Theme.fontSizeLarge
                color: clockTone.glyph
                style: Text.Outline
                styleColor: clockTone.halo
            }
            Silica.Label {
                //: Qt date format pattern: keep the letters d, M, y; reorder or add separators only. Day and month for the lock screen date, e.g. 26 October
                text: Qt.formatDate(clockColumn.today, qsTr("d MMMM"))
                anchors.horizontalCenter: parent.horizontalCenter
                font.pixelSize: clockColumn.mediaActive ? Silica.Theme.fontSizeMedium : Silica.Theme.fontSizeLarge
                color: clockTone.glyph
                style: Text.Outline
                styleColor: clockTone.halo
            }
        }

        // ── Media card (LockMedia variant) ──────────────────
        // Per screens-shell.jsx:188-240 LockMedia(): absolute
        // positioned at top:360, left/right:18. Visible only when
        // MPRIS reports an active player — no card when nothing is
        // playing (the LockScreen variant takes over).
        MediaPlaybackManager {
            id: lockScreenMediaPlayer

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Math.round(18 * Constants.scaleFactor)
            anchors.rightMargin: Math.round(18 * Constants.scaleFactor)
            anchors.top: parent.top
            anchors.topMargin: lockScreen.compactLayout ? Math.round(lockScreen.height * 0.44) : Math.round(360 * Constants.scaleFactor)
            visible: hasMedia
            z: 8
        }

        // ── Notification stack ──────────────────────────────
        // The most recent unread notifications; the rest collapse into a
        // 'N more' row beneath.
        Column {
            id: notificationStack

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Silica.Theme.horizontalPageMargin
            anchors.rightMargin: Silica.Theme.horizontalPageMargin
            anchors.top: lockScreenMediaPlayer.visible ? lockScreenMediaPlayer.bottom : clockColumn.bottom
            anchors.topMargin: Silica.Theme.paddingLarge * 2
            spacing: Silica.Theme.paddingMedium
            visible: unreadModel.count > 0 || lockScreen.moreCount > 0
            z: 10
            onHeightChanged: Qt.callLater(lockScreen.fitNotifications)

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

                    width: notificationStack.width
                    height: cardContent.implicitHeight + Silica.Theme.paddingLarge * 2

                    MGlassPlatter {
                        anchors.fill: parent
                        backdrop: glassBackdrop.texture
                        pressed: notifArea.pressed
                    }

                    Row {
                        id: cardContent
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Silica.Theme.paddingLarge
                        anchors.rightMargin: Silica.Theme.paddingLarge
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Silica.Theme.paddingLarge

                        GlyphIcon {
                            id: notifIcon
                            anchors.verticalCenter: parent.verticalCenter
                            name: notifCard.icon
                            size: Silica.Theme.iconSizeSmall
                            color: Silica.Theme.highlightColor
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
                                    font.pixelSize: Silica.Theme.fontSizeSmall
                                    font.weight: Font.DemiBold
                                    truncationMode: Silica.TruncationMode.Fade
                                }
                                Silica.Label {
                                    id: timeText
                                    anchors.right: parent.right
                                    anchors.verticalCenter: nameText.verticalCenter
                                    text: lockScreen.relativeTime(notifCard.timestamp)
                                    color: Silica.Theme.secondaryColor
                                    font.pixelSize: Silica.Theme.fontSizeExtraSmall
                                    font.features: ({
                                            "tnum": 1
                                        })
                                }
                            }

                            Silica.Label {
                                width: parent.width
                                text: notifCard.body
                                color: Silica.Theme.secondaryColor
                                font.pixelSize: Silica.Theme.fontSizeExtraSmall
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                wrapMode: Text.WordWrap
                                visible: text.length > 0
                            }
                        }
                    }

                    MouseArea {
                        id: notifArea
                        anchors.fill: parent
                        onClicked: {
                            HapticManager.light();
                            lockScreen.notificationTapped(notifCard.notifId, notifCard.appId, notifCard.title);
                        }
                    }
                }
            }

            Item {
                width: notificationStack.width
                height: Silica.Theme.itemSizeSmall
                visible: lockScreen.moreCount > 0

                MGlassPlatter {
                    anchors.fill: parent
                    backdrop: glassBackdrop.texture
                    pressed: moreArea.pressed
                }
                Accessible.role: Accessible.Button
                Accessible.name: moreLabel.text
                Accessible.onPressAction: lockScreen.hubRequested()

                Row {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Silica.Theme.paddingLarge
                    anchors.rightMargin: Silica.Theme.paddingLarge
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Silica.Theme.paddingLarge

                    GlyphIcon {
                        id: moreIcon
                        anchors.verticalCenter: parent.verticalCenter
                        name: "bell"
                        size: Silica.Theme.iconSizeSmall
                        color: Silica.Theme.highlightColor
                    }

                    Silica.Label {
                        id: moreLabel

                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - moreIcon.width - parent.spacing
                        //: Shown under the lock screen notifications; %n is how many more there are
                        text: qsTr("%n more notification(s)", "", lockScreen.moreCount)
                        color: Silica.Theme.secondaryColor
                        font.pixelSize: Silica.Theme.fontSizeSmall
                        truncationMode: Silica.TruncationMode.Fade
                    }
                }

                MouseArea {
                    id: moreArea

                    anchors.fill: parent
                    onClicked: {
                        HapticManager.light();
                        lockScreen.hubRequested();
                    }
                }
            }
        }

        // Phone and camera shortcuts in the bottom corners, with the
        // unlock hint between them.
        Item {
            id: lockScreenBottomBar

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: Silica.Theme.horizontalPageMargin
            anchors.rightMargin: Silica.Theme.horizontalPageMargin
            anchors.bottomMargin: Silica.Theme.paddingLarge
            height: Silica.Theme.itemSizeSmall
            z: 10

            MCircularIconButton {
                width: Silica.Theme.itemSizeSmall
                height: width
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                iconName: "phone"
                iconSize: Silica.Theme.iconSizeSmall
                variant: "secondary"
                a11yName: qsTr("Phone")
                onClicked: {
                    Logger.info("LockScreen", "Phone quick action tapped");
                    lockScreen.phoneLaunched();
                }
            }

            MCircularIconButton {
                width: Silica.Theme.itemSizeSmall
                height: width
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconName: "camera"
                iconSize: Silica.Theme.iconSizeSmall
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

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Silica.Theme.paddingLarge
            spacing: Silica.Theme.paddingSmall
            z: 11

            GlyphIcon {
                name: "chevron-up"
                size: Silica.Theme.iconSizeSmall
                color: hintTone.glyph
                anchors.horizontalCenter: parent.horizontalCenter

                SequentialAnimation on y {
                    // A few bobs each time the lock screen appears, then
                    // rest: any running animation makes the scene graph
                    // redraw the whole screen every frame, which cost a
                    // quarter of a core on the PinePhone's lock screen.
                    running: MMotion.gate(lockScreen.visible)
                    loops: 3

                    NumberAnimation {
                        to: -Silica.Theme.paddingSmall
                        duration: 800
                        easing.type: Easing.InOutQuad
                    }

                    NumberAnimation {
                        to: 0
                        duration: 800
                        easing.type: Easing.InOutQuad
                    }
                }
            }

            Silica.Label {
                text: qsTr("Swipe up to unlock")
                color: hintTone.glyph
                style: Text.Outline
                styleColor: hintTone.halo
                font.pixelSize: Silica.Theme.fontSizeExtraSmall
                anchors.horizontalCenter: parent.horizontalCenter
            }
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
            if (totalDelta > 10) {
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
