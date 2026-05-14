import "./ui"
import MarathonOS.Shell 1.0
import MarathonOS.Shell 1.0 as Shell
import MarathonUI.Core
import MarathonUI.Effects
import MarathonUI.Theme
import QtQuick
import QtQuick.Effects

Item {
    id: lockScreen

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
        }

        MarathonStatusBar {
            id: statusBar

            width: parent.width
            z: 5
        }

        Column {
            id: clockColumn

            // DS spec: lock clock anchors near top — top:190 in the source.
            // Top-anchored composition; the swipe-up state machine below
            // overrides this anchor when the lock screen is being dragged.
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Constants.spacingSmall
            width: parent.width * 0.9
            anchors.top: parent.top
            anchors.topMargin: Math.round(190 * Constants.scaleFactor)
            onYChanged: Logger.debug("LockScreen", "ClockColumn Y changed to: " + y)
            layer.enabled: true
            layer.smooth: true

            // Lock-clock variant of the Display role per screens-shell.jsx
            // LockScreen() — 84 px, weight 100 (Thin), -2 tracking. Quieter
            // than the DS Display token (96/200/-3) so it sits at top:190
            // on a 390-wide canvas without dominating.
            MHaloedDisplay {
                text: SystemStatusStore.timeString
                font.family: MTypography.fontFamily
                font.pixelSize: Math.round(84 * Constants.scaleFactor)
                font.weight: MTypography.weightThin
                font.letterSpacing: -2
                color: MColors.textPrimary
                anchors.horizontalCenter: parent.horizontalCenter
            }

            // Date — Subhead 15/500 per JSX, but tracking is +0.3 (the
            // lock screen overrides Subhead's default -0.1 to give the
            // date a quieter, lightly tracked feel).
            Text {
                text: SystemStatusStore.dateString
                color: MColors.textSecondary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeSubhead
                font.weight: MTypography.weightMedium
                font.letterSpacing: 0.3
                anchors.horizontalCenter: parent.horizontalCenter
                renderType: Text.NativeRendering
            }

            Item {
                width: parent.width
                height: Constants.spacingMedium
                visible: lockScreenMediaPlayer.visible
            }

            MediaPlaybackManager {
                id: lockScreenMediaPlayer

                width: Math.min(parent.width, 400 * Constants.scaleFactor)
                anchors.horizontalCenter: parent.horizontalCenter
                visible: hasMedia
                border.width: Constants.borderWidthThin
                border.color: Qt.rgba(0, 191 / 255, 165 / 255, 0.3)

                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: Qt.rgba(0, 191 / 255, 165 / 255, 0.15)
                    }

                    GradientStop {
                        position: 1
                        color: Qt.rgba(0, 0, 0, 0.2)
                    }
                }
            }
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
                    height: Math.max(60, cardContent.implicitHeight + 24)
                    radius: MRadius.md   // 4 — DS default
                    color: MColors.bb10Elevated   // elev-2
                    border.width: 1
                    border.color: MColors.whiteOverlay08

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
                height: 44
                radius: MRadius.md
                color: MColors.bb10Elevated
                border.width: 1
                border.color: MColors.whiteOverlay08
                visible: lockScreen.moreCount > 0

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
                renderType: Text.NativeRendering
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
