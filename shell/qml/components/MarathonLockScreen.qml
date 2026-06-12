import "./ui"
import MarathonOS.Shell 1.0
import MarathonOS.Shell 1.0 as Shell
import MarathonUI.Core
import MarathonUI.Effects
import MarathonUI.Theme
import QtQuick

Item {
    id: lockScreen

    // The running app surface to blur behind the lock chrome, if any.
    // Set by MarathonShell.qml to appWindowContainer when an app is
    // open; null otherwise (the wallpaper renders through normally).
    property Item appBackdrop: null

    property real swipeProgress: 0
    property int idleTimeoutMs: 30000
    readonly property int roleIsRead: roleId("isRead")
    readonly property int roleAppId: roleId("appId")
    readonly property int roleIcon: roleId("icon")
    readonly property int roleIdValue: roleId("id")
    readonly property int roleTitle: roleId("title")
    readonly property int roleBody: roleId("body")
    readonly property int roleTimestamp: roleId("timestamp")
    // Max notification cards shown directly; remainder collapse
    // into the 'N more notifications · earlier today' card per
    // the JSX LockScreen design.
    readonly property int maxNotificationsShown: 2

    signal unlockRequested
    signal cameraLaunched
    signal phoneLaunched
    signal notificationTapped(int notifId, string appId, string title)

    function roleId(name) {
        if (!NotificationModel || !name)
            return -1;

        return NotificationModel.roleId(name);
    }

    function resetIdleTimer() {
        if (lockScreen.visible && DisplayPolicyControllerCpp.screenOn)
            idleTimer.restart();
    }

    // Relative-time formatter for notification cards.
    // Returns 'now' / 'Nm' / 'Nh' / clock-time for older today.
    function relativeTime(ts) {
        if (!ts)
            return "";
        const now = Date.now();
        const diff = now - ts;
        if (diff < 60 * 1000)
            return "now";
        if (diff < 60 * 60 * 1000)
            return Math.floor(diff / 60000) + "m";
        if (diff < 24 * 60 * 60 * 1000)
            return Math.floor(diff / 3600000) + "h";
        return Qt.formatTime(new Date(ts), "h:mm AP");
    }

    // Rebuilds the visible-notifications model from the global
    // NotificationModel — keeps only the first `maxNotificationsShown`
    // unread items so the lock surface stays calm. The remainder are
    // surfaced via the 'N more · earlier today' card.
    function refreshNotifications() {
        unreadModel.clear();
        let unread = 0;
        for (let i = 0; i < NotificationModel.rowCount(); i++) {
            const idx = NotificationModel.index(i, 0);
            if (NotificationModel.data(idx, roleIsRead))
                continue;
            if (unread < maxNotificationsShown) {
                unreadModel.append({
                    "notifId": NotificationModel.data(idx, roleIdValue) || 0,
                    "appId": NotificationModel.data(idx, roleAppId) || "other",
                    "icon": NotificationModel.data(idx, roleIcon) || "bell",
                    "title": NotificationModel.data(idx, roleTitle) || "",
                    "body": NotificationModel.data(idx, roleBody) || "",
                    "timestamp": NotificationModel.data(idx, roleTimestamp) || 0
                });
            }
            unread++;
        }
        moreCount = Math.max(0, unread - maxNotificationsShown);
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
    layer.enabled: true
    layer.smooth: true

    Timer {
        id: idleTimer

        interval: idleTimeoutMs
        running: lockScreen.visible && DisplayPolicyControllerCpp.screenOn
        repeat: false
        onTriggered: {
            if (typeof compositor !== 'undefined' && compositor.hasIdleInhibitingSurface) {
                Logger.info("LockScreen", "Idle inhibitor active (video playback?) - postponing screen blank");
                idleTimer.restart();
                return;
            }
            Logger.info("LockScreen", "Idle timeout - blanking screen");
            DisplayPolicyControllerCpp.turnScreenOff();
        }
    }

    Connections {
        function onNotificationReceived(notification) {
            if (lockScreen.visible) {
                Logger.info("LockScreen", "New notification: " + notification.title);
                if (!DisplayPolicyControllerCpp.screenOn)
                    DisplayPolicyControllerCpp.turnScreenOn();
                resetIdleTimer();
                lockScreen.refreshNotifications();
            }
        }

        target: NotificationService
    }

    Connections {
        function onScreenStateChanged(isOn) {
            if (isOn) {
                SessionStore.showLock();
                if (lockScreen.visible) {
                    Logger.info("LockScreen", "Screen turned on - starting idle timer");
                    resetIdleTimer();
                }
            }
        }

        target: DisplayManagerCpp
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

        target: NotificationModel
    }

    Item {
        id: lockContent

        anchors.fill: parent
        z: 1
        opacity: 1 - Math.pow(swipeProgress, 0.7)

        WallpaperSlateAurora {
            anchors.fill: parent
            visible: lockScreen.appBackdrop === null
        }

        AppBackdropBlur {
            anchors.fill: parent
            source: lockScreen.appBackdrop
            blurAmount: 1.0
            blurMax: 64
            saturation: 0.4
            brightness: -0.15
            tint: Qt.rgba(0, 0, 0, 0.25)
        }

        MarathonStatusBar {
            id: statusBar

            width: parent.width
            z: 5
        }

        // ── Call NowBar (screens-modern.jsx:LockNowBar) ─────
        // Live activity strip pinned 70 px from the top whenever
        // TelephonyService has an active or ringing call. The card
        // shows a teal-bright phone avatar, an eyebrow with caller
        // name + call duration, and a red end-call button.
        //
        // Caller name resolves through ContactsService when granted,
        // falling back to the raw activeNumber otherwise.
        Item {
            id: lockNowBar

            readonly property bool callActive: TelephonyService.callState === "active" || TelephonyService.callState === "ringing"
            // Wall-clock timestamp of the most recent "active" transition.
            // Reset to 0 whenever the call leaves the active state so the
            // duration eyebrow flips back to "00:00".
            property double callStartedAt: 0
            property int callElapsed: 0

            function fmtElapsed() {
                const total = Math.max(0, callElapsed);
                const m = Math.floor(total / 60);
                const s = total % 60;
                return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
            }

            function callerLabel() {
                const num = TelephonyService.activeNumber || "";
                if (!num)
                    return "Unknown";
                // Shell-process callers use ContactsManager directly;
                // app-runner clients see the same data via ContactsService
                // (the IPC wrapper). Try both — whichever is defined wins.
                const svc = (typeof ContactsService !== "undefined" && ContactsService) ? ContactsService : (typeof ContactsManager !== "undefined" && ContactsManager) ? ContactsManager : null;
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
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.topMargin: 42
            height: 72
            z: 6

            Connections {
                target: TelephonyService
                function onCallStateChanged() {
                    if (TelephonyService.callState === "active") {
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
                radius: MRadius.md
                color: MColors.glassTitlebar
                border.width: 1
                border.color: MColors.borderGlassStrong

                MTopHairline {
                    radius: parent.radius
                    color: MColors.whiteOverlay06
                    lineWidth: 1
                }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    anchors.topMargin: 14
                    anchors.bottomMargin: 14
                    spacing: 14

                    // 44 × 44 teal-outlined phone avatar.
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 44
                        height: 44
                        radius: width / 2
                        border.width: 1
                        border.color: MColors.marathonTealBright
                        gradient: Gradient {
                            GradientStop {
                                position: 0
                                color: "#1a4a3e"
                            }
                            GradientStop {
                                position: 1
                                color: "#0d2620"
                            }
                        }
                        Icon {
                            anchors.centerIn: parent
                            name: "phone"
                            size: 20
                            color: MColors.marathonTealBright
                        }
                        // Outer teal halo ring at low alpha.
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -4
                            radius: width / 2
                            color: "transparent"
                            border.width: 1
                            border.color: MColors.marathonTealBright
                            opacity: 0.4
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 44 - 36 - parent.spacing * 2
                        spacing: 2

                        Text {
                            text: "CALL · " + lockNowBar.fmtElapsed()
                            color: MColors.marathonTealBright
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeEyebrow
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.8
                            font.features: ({
                                    "tnum": 1
                                })
                        }
                        Text {
                            width: parent.width
                            text: lockNowBar.callerLabel()
                            color: MColors.textPrimary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeSubhead
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                    }

                    // 36 × 36 red end-call button.
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 36
                        height: 36
                        radius: width / 2
                        color: MColors.error
                        Icon {
                            anchors.centerIn: parent
                            name: "phone"
                            size: 14
                            color: "#FFFFFF"
                            rotation: 135
                        }
                        scale: endCallArea.pressed ? 0.94 : 1.0
                        Behavior on scale {
                            NumberAnimation {
                                duration: 100
                                easing.type: Easing.OutBack
                            }
                        }
                        MouseArea {
                            id: endCallArea
                            anchors.fill: parent
                            anchors.margins: -6
                            onClicked: {
                                HapticManager.medium();
                                TelephonyService.hangup();
                            }
                        }
                    }
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

            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Constants.spacingSmall
            width: parent.width * 0.9
            anchors.top: parent.top
            anchors.topMargin: Math.round((mediaActive ? 170 : 190) * Constants.scaleFactor)
            layer.enabled: true
            layer.smooth: true

            Behavior on anchors.topMargin {
                NumberAnimation {
                    duration: MMotion.moderate
                    easing.type: Easing.OutCubic
                }
            }

            MHaloedDisplay {
                text: SystemStatusStore.timeString
                font.family: MTypography.fontFamily
                font.pixelSize: Math.round((clockColumn.mediaActive ? 76 : 84) * Constants.scaleFactor)
                font.weight: MTypography.weightThin
                font.letterSpacing: clockColumn.mediaActive ? -1.5 : -2
                color: MColors.textPrimary
                anchors.horizontalCenter: parent.horizontalCenter

                Behavior on font.pixelSize {
                    NumberAnimation {
                        duration: MMotion.moderate
                        easing.type: Easing.OutCubic
                    }
                }
            }

            Text {
                text: SystemStatusStore.dateString
                color: MColors.textSecondary
                font.family: MTypography.fontFamily
                font.pixelSize: clockColumn.mediaActive ? Math.round(14 * Constants.scaleFactor) : MTypography.sizeSubhead
                font.weight: MTypography.weightMedium
                font.letterSpacing: 0.3
                anchors.horizontalCenter: parent.horizontalCenter
                renderType: Text.QtRendering
            }
        }

        // ── Activity NowBar ─────────────────────────────────
        // Per screens-modern.jsx:LockNowBar — a second activity strip
        // beneath the time, showing Move / Stand ring progress. Bound
        // to ActivityService (MotionDaemon → Oxford C-Step-Counter).
        // Hidden when no media card is up and no rings are closed yet,
        // so a brand-new device doesn't crowd the lock with zero-state
        // chrome.
        Item {
            id: activityBar

            readonly property bool serviceUp: typeof ActivityService !== "undefined" && ActivityService !== null && ActivityService.available
            readonly property int moveP: serviceUp ? Math.round(ActivityService.movePercent * 100) : 0
            readonly property int exerciseP: serviceUp ? Math.round(ActivityService.exercisePercent * 100) : 0
            readonly property int standP: serviceUp ? Math.round(ActivityService.standPercent * 100) : 0
            readonly property int ringsLeft: {
                let n = 0;
                if (moveP < 100)
                    n++;
                if (exerciseP < 100)
                    n++;
                if (standP < 100)
                    n++;
                return n;
            }
            readonly property int rawSteps: serviceUp ? ActivityService.stepsToday : 0
            readonly property bool anyProgress: rawSteps > 0 || moveP > 0 || exerciseP > 0 || standP > 0

            visible: serviceUp && anyProgress && !lockScreenMediaPlayer.hasMedia
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.top: clockColumn.bottom
            anchors.topMargin: Math.round(28 * Constants.scaleFactor)
            height: 68

            Rectangle {
                anchors.fill: parent
                radius: MRadius.md
                color: MColors.elev2
                border.width: 1
                border.color: MColors.whiteOverlay04
            }
            // Top inset highlight per DS "lit from above".
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 1
                anchors.rightMargin: 1
                anchors.topMargin: 1
                height: 1
                color: Qt.rgba(1, 1, 1, 0.06)
            }

            Row {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 12

                // 44 × 44 squircle with three concentric activity rings.
                // The arc widths are constants; ring fill is communicated
                // by the percentages above instead of redrawing arcs each
                // frame.
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    height: 44
                    radius: width / 2
                    color: "transparent"
                    border.width: 3
                    border.color: Qt.rgba(255 / 255, 59 / 255, 71 / 255, activityBar.moveP > 0 ? 0.9 : 0.25)

                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width - 9
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: 3
                        border.color: Qt.rgba(165 / 255, 255 / 255, 132 / 255, activityBar.exerciseP > 0 ? 0.9 : 0.25)
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width - 18
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: 3
                        border.color: Qt.rgba(0 / 255, 191 / 255, 255 / 255, activityBar.standP > 0 ? 0.9 : 0.25)
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 44 - parent.spacing
                    spacing: 2

                    Text {
                        text: "ACTIVITY"
                        color: MColors.textSecondary
                        font.family: MTypography.fontFamily
                        font.pixelSize: MTypography.sizeEyebrow
                        font.weight: Font.Bold
                        font.letterSpacing: MTypography.trackingEyebrow
                    }
                    Text {
                        width: parent.width
                        text: "Move " + activityBar.moveP + "% · Stand " + activityBar.standP + "%"
                        color: MColors.textPrimary
                        font.family: MTypography.fontFamily
                        font.pixelSize: MTypography.sizeSubhead
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: activityBar.ringsLeft === 0 ? "All rings closed today" : activityBar.ringsLeft + " ring" + (activityBar.ringsLeft === 1 ? "" : "s") + " left to close before bed"
                        color: MColors.textTertiary
                        font.family: MTypography.fontFamily
                        font.pixelSize: MTypography.sizeFootnote
                        elide: Text.ElideRight
                    }
                }
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
            anchors.topMargin: Math.round(360 * Constants.scaleFactor)
            visible: hasMedia
            z: 8
        }

        // ── Notification stack ──────────────────────────────
        // Per screens-shell.jsx:84-147 LockScreen() — at top:420 in the
        // 844-tall canvas, anchored 18 left/right. 2-3 most-recent
        // unread cards stacked at 8 px gap. If unread > maxShown, an
        // 'N more · earlier today' collapse card sits at the bottom.
        Column {
            id: notificationStack

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Math.round(18 * Constants.scaleFactor)
            anchors.rightMargin: Math.round(18 * Constants.scaleFactor)
            anchors.top: parent.top
            anchors.topMargin: Math.round(420 * Constants.scaleFactor)
            spacing: 8
            visible: unreadModel.count > 0 || lockScreen.moreCount > 0
            z: 10

            Repeater {
                model: unreadModel

                delegate: Rectangle {
                    required property int index
                    required property int notifId
                    required property string appId
                    required property string icon
                    required property string title
                    required property string body
                    required property var timestamp

                    width: notificationStack.width
                    // Natural content height — no 60 px floor. DS lock-screen
                    // cards are tight glanceable snippets, not list rows; the
                    // floor was making them feel like full Settings rows.
                    height: cardContent.implicitHeight + 24
                    radius: MRadius.md   // 4 — DS default
                    color: MColors.bb10Elevated   // elev-2 = #161718
                    // .m-card outer ring is `0 0 0 1px var(--border-dark)`
                    // (rgba(0,0,0,0.7)) — a DARK border that makes the card
                    // recede into the wallpaper. Was whiteOverlay08, which
                    // made the cards pop forward and read as opaque chrome.
                    border.width: 1
                    border.color: MColors.borderDark

                    // .m-card inset top hairline `inset 0 1px 0 var(--w-06)`.
                    // Lit edge sits inside the dark outer ring — the
                    // signature double-edge of every Marathon card.
                    MTopHairline {
                        radius: MRadius.md
                        color: MColors.whiteOverlay06
                    }

                    Row {
                        id: cardContent
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        anchors.topMargin: 12
                        anchors.bottomMargin: 12
                        spacing: 12

                        // Icon container — 32 × 32, radius 4. Calendar uses
                        // a tealBorder variant per the JSX; default is a
                        // quiet two-stop neutral gradient.
                        Rectangle {
                            id: iconBay
                            width: 32
                            height: 32
                            radius: MRadius.md
                            border.width: 1
                            border.color: appId === "calendar" ? MColors.tealBorder : MColors.whiteOverlay08
                            anchors.verticalCenter: parent.verticalCenter

                            gradient: Gradient {
                                GradientStop {
                                    position: 0
                                    color: appId === "calendar" ? MColors.bb10Surface : MColors.bb10Elevated
                                }
                                GradientStop {
                                    position: 1
                                    color: MColors.bb10Card
                                }
                            }

                            Icon {
                                anchors.centerIn: parent
                                name: icon
                                size: 16
                                color: appId === "calendar" ? MColors.marathonTealBright : MColors.textPrimary
                            }
                        }

                        // Content column — title row + body text. Layout
                        // mirrors the JSX exactly (name 13/600 + time 11
                        // /secondary on the same row, body 13/primary
                        // below).
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - iconBay.width - parent.spacing
                            spacing: 2

                            Item {
                                width: parent.width
                                height: nameText.implicitHeight

                                Text {
                                    id: nameText
                                    anchors.left: parent.left
                                    anchors.right: timeText.left
                                    anchors.rightMargin: 8
                                    text: title
                                    color: MColors.textPrimary
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: MTypography.sizeFootnote
                                    font.weight: MTypography.weightDemiBold
                                    elide: Text.ElideRight
                                }
                                Text {
                                    id: timeText
                                    anchors.right: parent.right
                                    anchors.verticalCenter: nameText.verticalCenter
                                    text: lockScreen.relativeTime(timestamp)
                                    color: MColors.textSecondary
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: MTypography.sizeEyebrow
                                    font.weight: MTypography.weightMedium
                                    font.features: ({
                                            "tnum": 1
                                        })
                                }
                            }

                            Text {
                                width: parent.width
                                text: body
                                color: MColors.textPrimary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeFootnote
                                font.weight: MTypography.weightRegular
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                wrapMode: Text.WordWrap
                                visible: text.length > 0
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            HapticManager.light();
                            lockScreen.notificationTapped(notifId, appId, title);
                        }
                    }
                }
            }

            // 'N more notifications · earlier today' collapse card —
            // shown when more unread exist than the stack displays.
            Rectangle {
                width: notificationStack.width
                // DS .m-card padding "10px 14px" + 28 px icon row =
                // 48 px tall. Was 44 px (too cramped) and bordered in
                // white-08 instead of the DS dark outer ring.
                height: 48
                radius: MRadius.md
                color: MColors.bb10Elevated
                border.width: 1
                border.color: MColors.borderDark
                visible: lockScreen.moreCount > 0

                MTopHairline {
                    radius: MRadius.md
                    color: MColors.whiteOverlay06
                }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 12

                    Rectangle {
                        width: 28
                        height: 28
                        radius: MRadius.md
                        color: MColors.bb10Card
                        anchors.verticalCenter: parent.verticalCenter

                        Icon {
                            anchors.centerIn: parent
                            name: "bell"
                            size: 14
                            color: MColors.textPrimary
                        }
                    }

                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 28 - parent.spacing - 18
                        height: collapseLabel.implicitHeight

                        Text {
                            id: collapseLabel
                            anchors.verticalCenter: parent.verticalCenter
                            color: MColors.textSecondary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeCaption
                            textFormat: Text.RichText
                            text: '<span style="color: ' + MColors.textPrimary + '">' + lockScreen.moreCount + ' more notification' + (lockScreen.moreCount === 1 ? '' : 's') + '</span>' + ' · earlier today'
                        }
                    }

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "chevron-down"
                        size: 14
                        color: MColors.textTertiary
                    }
                }
            }
        }

        // Lock-screen bottom row — phone (teal) + camera (dim) +
        // center unlock affordance. Matches the JSX LockScreen
        // chevron + 'Swipe up to unlock' pattern, but keeps the
        // legacy phone/camera shortcuts (per usability — phone
        // access from lock is a near-universal pattern). The
        // shortcuts live in MarathonLockShortcuts (squircle bay
        // + teal accent on Phone, dim on Camera) instead of the
        // full MarathonBottomBar chrome (no page-indicator on
        // lock per the design).
        MarathonLockShortcuts {
            id: lockScreenBottomBar

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.round(8 * Constants.scaleFactor)
            z: 10
            onPhoneActivated: {
                HapticManager.medium();
                Logger.info("LockScreen", "Phone quick action tapped");
                phoneLaunched();
            }
            onCameraActivated: {
                HapticManager.medium();
                Logger.info("LockScreen", "Camera quick action tapped");
                cameraLaunched();
            }
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.round(24 * Constants.scaleFactor)
            spacing: Math.round(4 * Constants.scaleFactor)
            opacity: 0.7
            z: 11

            Icon {
                name: "chevron-up"
                size: Math.round(24 * Constants.scaleFactor)
                color: "white"
                anchors.horizontalCenter: parent.horizontalCenter

                SequentialAnimation on y {
                    // Only animate while the lock screen is actually visible.
                    // Leaving this unconditionally running re-renders the scene
                    // graph at the animation rate even when the lock screen is
                    // hidden, which under software rasterization keeps all four
                    // LLVMpipe threads + QSGRenderThread busy at idle.
                    running: lockScreen.visible
                    loops: Animation.Infinite

                    NumberAnimation {
                        to: -6
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

            Text {
                text: "Swipe up to unlock"
                color: "white"
                font.pixelSize: MTypography.sizeSmall
                anchors.horizontalCenter: parent.horizontalCenter
                renderType: Text.QtRendering
            }
        }

        Behavior on opacity {
            enabled: swipeProgress > 0.5

            NumberAnimation {
                duration: 200
                easing.type: Easing.OutCubic
            }
        }
    }

    MouseArea {
        property real startY: 0
        property real lastY: 0
        property real velocity: 0
        property bool isDragging: false
        property real lastTime: 0

        anchors.fill: parent
        z: 0
        propagateComposedEvents: true
        onPressed: mouse => {
            startY = mouse.y;
            lastY = mouse.y;
            velocity = 0;
            isDragging = false;
            lastTime = Date.now();
            resetIdleTimer();
        }
        onPositionChanged: mouse => {
            const deltaY = lastY - mouse.y;
            const now = Date.now();
            const deltaTime = now - lastTime;
            if (deltaTime > 0)
                velocity = deltaY / deltaTime;

            lastY = mouse.y;
            lastTime = now;
            const totalDelta = startY - mouse.y;
            if (totalDelta > 10) {
                isDragging = true;
                mouse.accepted = true;
            }
            if (isDragging) {
                const threshold = height * 0.15;
                swipeProgress = Math.max(0, Math.min(1, totalDelta / threshold));
                if (swipeProgress > 0.5 && swipeProgress < 0.55)
                    HapticManager.light();
            }
        }
        onReleased: mouse => {
            if (isDragging) {
                if (swipeProgress > 0.2 || velocity > 0.5) {
                    swipeProgress = 1;
                    HapticManager.medium();
                    unlockTimer.start();
                } else {
                    swipeProgress = 0;
                }
            } else {
                Logger.info("LockScreen", "Tap detected (no drag), x=" + mouse.x + ", y=" + mouse.y);
            }
            isDragging = false;
            velocity = 0;
        }
    }

    Timer {
        id: unlockTimer

        interval: 100
        onTriggered: {
            Logger.state("LockScreen", "unlocked", "dissolve complete");
            unlockRequested();
        }
    }

    Behavior on swipeProgress {
        enabled: swipeProgress < 1

        SmoothedAnimation {
            velocity: 8
            duration: 150
        }
    }
}
