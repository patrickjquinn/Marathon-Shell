import "./ui"
import MarathonOS.Shell 1.0
import MarathonOS.Shell 1.0 as Shell
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick
import QtQuick.Effects

Item {
    id: lockScreen

    property real swipeProgress: 0
    property string expandedCategory: ""
    property int idleTimeoutMs: 30000

    signal unlockRequested
    signal cameraLaunched
    signal phoneLaunched
    signal notificationTapped(int notifId, string appId, string title)

    function roleId(name) {
        if (!NotificationModel || !name)
            return -1;
        return NotificationModel.roleId(name);
    }

    readonly property int roleIsRead: roleId("isRead")
    readonly property int roleAppId: roleId("appId")
    readonly property int roleIcon: roleId("icon")
    readonly property int roleIdValue: roleId("id")
    readonly property int roleTitle: roleId("title")
    readonly property int roleBody: roleId("body")
    readonly property int roleTimestamp: roleId("timestamp")

    function resetIdleTimer() {
        if (lockScreen.visible && (typeof DisplayPolicyControllerCpp !== "undefined" && DisplayPolicyControllerCpp ? DisplayPolicyControllerCpp.screenOn : true))
            idleTimer.restart();
    }

    function updateCategories() {
        var cats = {};
        for (var i = 0; i < NotificationModel.rowCount(); i++) {
            var idx = NotificationModel.index(i, 0);
            var isRead = NotificationModel.data(idx, roleIsRead) || false;
            if (isRead)
                continue;

            var appId = NotificationModel.data(idx, roleAppId) || "other";
            var icon = NotificationModel.data(idx, roleIcon) || "bell";
            if (!cats[appId])
                cats[appId] = {
                    "appId": appId,
                    "icon": icon,
                    "count": 0
                };

            cats[appId].count++;
        }
        categoriesModel.clear();
        for (var cat in cats) {
            categoriesModel.append(cats[cat]);
        }
        Logger.info("LockScreen", "Updated categories. Count: " + categoriesModel.count);
    }

    anchors.fill: parent
    visible: opacity > 0.01
    onVisibleChanged: {
        if (visible) {
            Logger.info("LockScreen", "Lock screen visible - refreshing categories");
            lockScreen.updateCategories();
            SessionStore.isOnLockScreen = true;
        } else {
            SessionStore.isOnLockScreen = false;
        }
    }
    Component.onCompleted: {
        if (visible) {
            Logger.info("LockScreen", "Lock screen created visible - setting initial state");
            console.log("[LockScreen] SessionStore.isLocked =", SessionStore.isLocked);
            SessionStore.isOnLockScreen = true;
            lockScreen.updateCategories();
        }
    }
    layer.enabled: true
    layer.smooth: true

    Timer {
        id: idleTimer

        interval: idleTimeoutMs
        running: lockScreen.visible && (typeof DisplayPolicyControllerCpp !== "undefined" && DisplayPolicyControllerCpp ? DisplayPolicyControllerCpp.screenOn : true)
        repeat: false
        onTriggered: {
            if (typeof compositor !== 'undefined' && compositor.hasIdleInhibitingSurface) {
                Logger.info("LockScreen", "Idle inhibitor active (video playback?) - postponing screen blank");
                idleTimer.restart();
                return;
            }
            Logger.info("LockScreen", "Idle timeout - blanking screen");
            if (typeof DisplayPolicyControllerCpp !== "undefined" && DisplayPolicyControllerCpp)
                DisplayPolicyControllerCpp.turnScreenOff();
            else if (typeof DisplayManagerCpp !== "undefined" && DisplayManagerCpp)
                DisplayManagerCpp.setScreenState(false);
        }
    }

    Connections {
        function onNotificationReceived(notification) {
            if (lockScreen.visible) {
                Logger.info("LockScreen", "New notification while on lock screen: " + notification.title);
                var screenOn = (typeof DisplayPolicyControllerCpp !== "undefined" && DisplayPolicyControllerCpp) ? DisplayPolicyControllerCpp.screenOn : true;
                if (!screenOn) {
                    if (typeof DisplayPolicyControllerCpp !== "undefined" && DisplayPolicyControllerCpp)
                        DisplayPolicyControllerCpp.turnScreenOn();
                    else if (typeof DisplayManagerCpp !== "undefined" && DisplayManagerCpp)
                        DisplayManagerCpp.setScreenState(true);
                }
                var appId = notification.appId || "other";
                expandedCategory = appId;
                resetIdleTimer();
                Logger.info("LockScreen", "Auto-expanded category: " + appId);
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

        target: typeof DisplayManagerCpp !== "undefined" ? DisplayManagerCpp : null
    }

    ListModel {
        id: categoriesModel
    }

    Connections {
        function onCountChanged() {
            lockScreen.updateCategories();
        }

        target: NotificationModel
    }

    Item {
        id: lockContent

        anchors.fill: parent
        z: 1
        opacity: 1 - Math.pow(swipeProgress, 0.7)

        Image {
            anchors.fill: parent
            source: WallpaperStore.path
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            smooth: true
            layer.enabled: true
            layer.smooth: true
        }

        MouseArea {
            anchors.fill: parent
            z: 1
            enabled: expandedCategory !== ""
            onClicked: {
                expandedCategory = "";
                resetIdleTimer();
                Logger.info("LockScreen", "Notifications dismissed");
            }
        }

        MarathonStatusBar {
            id: statusBar

            width: parent.width
            z: 5
        }

        Column {
            id: clockColumn

            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Constants.spacingSmall
            width: parent.width * 0.9
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: Math.round(-80 * Constants.scaleFactor)
            onYChanged: Logger.info("LockScreen", "ClockColumn Y changed to: " + y)
            layer.enabled: true
            layer.smooth: true

            Text {
                text: SystemStatusStore.timeString
                color: MColors.text
                font.pixelSize: Constants.fontSizeGigantic
                font.weight: Font.Thin
                anchors.horizontalCenter: parent.horizontalCenter
                renderType: Text.NativeRendering
                layer.enabled: true

                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: "#80000000"
                    shadowBlur: 0.3
                    shadowVerticalOffset: 2
                }
            }

            Text {
                text: SystemStatusStore.dateString
                color: MColors.text
                font.pixelSize: MTypography.sizeLarge
                font.weight: Font.Normal
                anchors.horizontalCenter: parent.horizontalCenter
                opacity: 0.9
                renderType: Text.NativeRendering
                layer.enabled: true

                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: "#80000000"
                    shadowBlur: 0.3
                    shadowVerticalOffset: 2
                }
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

            states: State {
                name: "hasNotifications"
                when: categoriesModel.count > 0

                AnchorChanges {
                    target: clockColumn
                    anchors.verticalCenter: undefined
                    anchors.top: parent.top
                }

                PropertyChanges {
                    clockColumn.anchors.topMargin: Math.round(80 * Constants.scaleFactor)
                    clockColumn.anchors.verticalCenterOffset: 0
                }
            }

            transitions: Transition {
                AnchorAnimation {
                    duration: 300
                    easing.type: Easing.OutCubic
                }

                NumberAnimation {
                    properties: "anchors.topMargin,anchors.verticalCenterOffset"
                    duration: 300
                    easing.type: Easing.OutCubic
                }
            }
        }

        Item {
            id: notificationContainer

            anchors.top: clockColumn.bottom
            anchors.topMargin: Constants.spacingMedium
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            visible: categoriesModel.count > 0
            z: 10
            onYChanged: Logger.info("LockScreen", "NotificationContainer Y changed to: " + y)

            Column {
                id: categoryIcons

                anchors.left: parent.left
                anchors.leftMargin: Constants.spacingMedium
                anchors.top: categoriesModel.count <= 3 ? parent.top : undefined
                anchors.topMargin: categoriesModel.count <= 3 ? Math.round(20 * Constants.scaleFactor) : 0
                anchors.verticalCenter: categoriesModel.count > 3 ? parent.verticalCenter : undefined
                spacing: Constants.spacingLarge
                z: 100

                Repeater {
                    model: categoriesModel

                    delegate: Item {
                        property string category: model.appId
                        property bool isActive: expandedCategory === category

                        width: Math.round(56 * Constants.scaleFactor)
                        height: Math.round(56 * Constants.scaleFactor)

                        Rectangle {
                            id: categoryIconBg

                            width: Math.round(48 * Constants.scaleFactor)
                            height: Math.round(48 * Constants.scaleFactor)
                            radius: Math.round(24 * Constants.scaleFactor)
                            color: isActive ? MColors.elevated : MColors.surface
                            border.width: 1
                            border.color: isActive ? MColors.accent : "#3A3A3A"
                            anchors.centerIn: parent
                            antialiasing: true
                            layer.enabled: true

                            Icon {
                                name: model.icon
                                size: 24
                                color: MColors.textPrimary
                                anchors.centerIn: parent
                            }

                            Rectangle {
                                visible: model.count > 0
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.rightMargin: Math.round(-4 * Constants.scaleFactor)
                                anchors.topMargin: Math.round(-4 * Constants.scaleFactor)
                                width: Math.round(20 * Constants.scaleFactor)
                                height: Math.round(20 * Constants.scaleFactor)
                                radius: Math.round(10 * Constants.scaleFactor)
                                color: MColors.accent
                                border.width: 2
                                border.color: MColors.background
                                antialiasing: true

                                Text {
                                    text: model.count
                                    color: "white"
                                    font.pixelSize: MTypography.sizeXSmall
                                    font.weight: Font.Bold
                                    anchors.centerIn: parent
                                    renderType: Text.NativeRendering
                                }
                            }

                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: "#000000"
                                shadowOpacity: 0.5
                                shadowBlur: 0.5
                                shadowVerticalOffset: 2
                                shadowHorizontalOffset: 1
                            }

                            Behavior on color {
                                ColorAnimation {
                                    duration: 200
                                }
                            }

                            Behavior on border.color {
                                ColorAnimation {
                                    duration: 200
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                HapticManager.light();
                                resetIdleTimer();
                                if (expandedCategory === category) {
                                    expandedCategory = "";
                                    Logger.info("LockScreen", "Collapsed category: " + category);
                                } else {
                                    expandedCategory = category;
                                    Logger.info("LockScreen", "Expanded category: " + category);
                                }
                            }
                        }
                    }
                }
            }

            Item {
                id: lineAndChevron

                function calculateChevronY() {
                    var activeIndex = -1;
                    for (var i = 0; i < categoriesModel.count; i++) {
                        if (categoriesModel.get(i).appId === expandedCategory) {
                            activeIndex = i;
                            break;
                        }
                    }
                    if (activeIndex === -1)
                        activeIndex = 0;

                    var itemHeight = Math.round(56 * Constants.scaleFactor);
                    var itemSpacing = Math.round(20 * Constants.scaleFactor);
                    var yPos = activeIndex * (itemHeight + itemSpacing) + Math.round(20 * Constants.scaleFactor);
                    Logger.info("LockScreen", "Chevron Y calculated: " + yPos + " for category: " + expandedCategory + " at index: " + activeIndex);
                    return yPos;
                }

                visible: expandedCategory !== ""
                anchors.left: categoryIcons.right
                anchors.leftMargin: Math.round(16 * Constants.scaleFactor)
                anchors.top: categoryIcons.top
                anchors.bottom: categoryIcons.bottom
                width: Math.round(24 * Constants.scaleFactor)
                z: 50

                Connections {
                    function onExpandedCategoryChanged() {
                        chevronCanvas.y = lineAndChevron.calculateChevronY();
                        topLineSegment.height = chevronCanvas.y;
                        bottomLineSegment.anchors.topMargin = chevronCanvas.y + Math.round(16 * Constants.scaleFactor);
                    }

                    target: lockScreen
                }

                Rectangle {
                    id: topLineSegment

                    anchors.left: parent.left
                    anchors.top: parent.top
                    width: Math.round(2 * Constants.scaleFactor)
                    height: Math.round(20 * Constants.scaleFactor)
                    color: "white"
                    opacity: 0.6
                    layer.enabled: true

                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: "#000000"
                        shadowOpacity: 0.6
                        shadowBlur: 0.4
                        shadowVerticalOffset: 1
                        shadowHorizontalOffset: 1
                    }
                }

                Canvas {
                    id: chevronCanvas

                    anchors.right: topLineSegment.horizontalCenter
                    y: Math.round(20 * Constants.scaleFactor)
                    width: Math.round(12 * Constants.scaleFactor)
                    height: Math.round(16 * Constants.scaleFactor)
                    layer.enabled: true
                    onYChanged: {
                        Logger.info("LockScreen", "Chevron Y changed to: " + y);
                        requestPaint();
                    }
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        ctx.strokeStyle = "white";
                        ctx.lineWidth = 2;
                        ctx.globalAlpha = 0.6;
                        ctx.beginPath();
                        ctx.moveTo(width, 0);
                        ctx.lineTo(0, height / 2);
                        ctx.lineTo(width, height);
                        ctx.stroke();
                    }

                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: "#000000"
                        shadowOpacity: 0.6
                        shadowBlur: 0.4
                        shadowVerticalOffset: 1
                        shadowHorizontalOffset: 1
                    }
                }

                Rectangle {
                    id: bottomLineSegment

                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.topMargin: Math.round(36 * Constants.scaleFactor)
                    anchors.bottom: parent.bottom
                    width: Math.round(2 * Constants.scaleFactor)
                    color: "white"
                    opacity: 0.6
                    layer.enabled: true

                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: "#000000"
                        shadowOpacity: 0.6
                        shadowBlur: 0.4
                        shadowVerticalOffset: 1
                        shadowHorizontalOffset: 1
                    }
                }
            }

            ListView {
                id: notificationList

                function updateFilteredNotifications() {
                    filteredNotificationsModel.clear();
                    if (expandedCategory === "")
                        return;

                    for (var i = 0; i < NotificationModel.rowCount(); i++) {
                        var idx = NotificationModel.index(i, 0);
                        var isRead = NotificationModel.data(idx, roleIsRead) || false;
                        if (isRead)
                            continue;

                        var appId = NotificationModel.data(idx, roleAppId) || "other";
                        if (appId === expandedCategory)
                            filteredNotificationsModel.append({
                                "notifId": NotificationModel.data(idx, roleIdValue),
                                "title": NotificationModel.data(idx, roleTitle),
                                "body": NotificationModel.data(idx, roleBody),
                                "timestamp": NotificationModel.data(idx, roleTimestamp)
                            });
                    }
                }

                visible: expandedCategory !== ""
                anchors.left: lineAndChevron.right
                anchors.leftMargin: Math.round(4 * Constants.scaleFactor)
                anchors.right: parent.right
                anchors.rightMargin: Math.round(16 * Constants.scaleFactor)
                anchors.top: categoryIcons.top
                anchors.topMargin: Math.round(-8 * Constants.scaleFactor)
                height: Math.min(count * Math.round(80 * Constants.scaleFactor), parent.height * 0.5)
                spacing: Constants.spacingSmall
                clip: true
                z: 40
                onVisibleChanged: {
                    if (visible)
                        updateFilteredNotifications();
                }

                Connections {
                    function onExpandedCategoryChanged() {
                        notificationList.updateFilteredNotifications();
                    }

                    target: lockScreen
                }

                Connections {
                    function onCountChanged() {
                        if (notificationList.visible)
                            notificationList.updateFilteredNotifications();
                    }

                    target: NotificationModel
                }

                model: ListModel {
                    id: filteredNotificationsModel
                }

                delegate: Item {
                    width: notificationList.width
                    height: Math.round(70 * Constants.scaleFactor)

                    Row {
                        anchors.fill: parent
                        anchors.margins: Constants.spacingMedium
                        spacing: 0

                        Column {
                            width: parent.width - timestampText.width - Constants.spacingMedium
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Math.round(4 * Constants.scaleFactor)

                            Text {
                                text: model.title || ""
                                color: "white"
                                font.pixelSize: MTypography.sizeBody
                                font.weight: Font.Bold
                                font.family: MTypography.fontFamily
                                elide: Text.ElideRight
                                width: parent.width
                                renderType: Text.NativeRendering
                                layer.enabled: true

                                layer.effect: MultiEffect {
                                    shadowEnabled: true
                                    shadowColor: "#80000000"
                                    shadowBlur: 0.4
                                    shadowVerticalOffset: 2
                                }
                            }

                            Text {
                                text: model.body || ""
                                color: "#E0FFFFFF"
                                font.pixelSize: MTypography.sizeSmall
                                font.family: MTypography.fontFamily
                                elide: Text.ElideRight
                                width: parent.width
                                renderType: Text.NativeRendering
                                layer.enabled: true

                                layer.effect: MultiEffect {
                                    shadowEnabled: true
                                    shadowColor: "#80000000"
                                    shadowBlur: 0.3
                                    shadowVerticalOffset: 1
                                }
                            }
                        }

                        Text {
                            id: timestampText

                            text: Qt.formatTime(new Date(model.timestamp), "h:mm AP")
                            color: "#B0FFFFFF"
                            font.pixelSize: MTypography.sizeSmall
                            font.family: MTypography.fontFamily
                            anchors.verticalCenter: parent.verticalCenter
                            renderType: Text.NativeRendering
                            layer.enabled: true

                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: "#80000000"
                                shadowBlur: 0.3
                                shadowVerticalOffset: 1
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            HapticManager.light();
                            resetIdleTimer();
                            Logger.info("LockScreen", "Notification tapped: " + model.title);
                            var notifId = model.notifId || 0;
                            var appId = "";
                            for (var i = 0; i < NotificationModel.rowCount(); i++) {
                                var idx = NotificationModel.index(i, 0);
                                var id = NotificationModel.data(idx, roleIdValue);
                                if (id === notifId) {
                                    appId = NotificationModel.data(idx, roleAppId) || "";
                                    break;
                                }
                            }
                            notificationTapped(notifId, appId, model.title);
                        }
                    }
                }
            }
        }

        MarathonBottomBar {
            id: lockScreenBottomBar

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            showPageIndicators: false
            z: 10
            onAppLaunched: app => {
                if (app.id === "phone") {
                    HapticManager.medium();
                    Logger.info("LockScreen", "Phone quick action tapped");
                    phoneLaunched();
                } else if (app.id === "camera") {
                    HapticManager.medium();
                    Logger.info("LockScreen", "Camera quick action tapped");
                    cameraLaunched();
                }
            }
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: lockScreenBottomBar.verticalCenter
            spacing: Math.round(4 * Constants.scaleFactor)
            opacity: 0.7
            z: 11

            Icon {
                name: "chevron-up"
                size: Math.round(24 * Constants.scaleFactor)
                color: "white"
                anchors.horizontalCenter: parent.horizontalCenter

                SequentialAnimation on y {
                    running: true
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
                    expandedCategory = "";
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
