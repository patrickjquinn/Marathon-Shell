import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

Item {
    id: peekComponent

    property real peekProgress: 0
    property real peekThreshold: 0.4
    property bool isPeeking: false
    property bool isFullyOpen: false
    property real gestureStartX: 0
    property real gestureVelocity: 0
    property real gestureLastX: 0
    property real gestureLastTime: 0

    signal closed
    signal fullyOpened
    signal notificationTapped(var notification)

    function startPeekGesture(x) {
        gestureStartX = x;
        gestureLastX = x;
        gestureLastTime = Date.now();
        isPeeking = true;
        Logger.info("Peek", "Gesture started from external capture");
    }

    function updatePeekGesture(deltaX) {
        if (!isPeeking)
            return;

        var now = Date.now();
        var deltaTime = now - gestureLastTime;
        if (deltaTime > 0)
            gestureVelocity = (deltaX - (gestureLastX - gestureStartX)) / deltaTime * 1000;

        gestureLastX = gestureStartX + deltaX;
        gestureLastTime = now;
        peekProgress = Math.max(0, Math.min(1, deltaX / (peekComponent.width * 0.85)));
        Logger.info("Peek", "Progress: " + (peekProgress * 100).toFixed(1) + "%, notif visible: " + (peekProgress < 0.35) + ", hub visible: " + (peekProgress >= 0.3));
    }

    function endPeekGesture() {
        if (!isPeeking)
            return;

        isPeeking = false;
        var shouldOpen = (gestureVelocity > 300) || (peekProgress > peekThreshold);
        if (shouldOpen)
            openPeek();
        else
            closePeek();
        Logger.info("Peek", "Gesture ended - " + (shouldOpen ? "opening" : "closing") + " (velocity: " + gestureVelocity.toFixed(0) + "px/s, progress: " + (peekProgress * 100).toFixed(0) + "%)");
    }

    function openPeek() {
        peekProgress = 1;
        isFullyOpen = true;
        fullyOpened();
    }

    function closePeek() {
        peekProgress = 0;
        isFullyOpen = false;
        closed();
    }

    function openFully() {
        openPeek();
    }

    anchors.fill: parent
    clip: true
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape && peekProgress > 0) {
            closePeek();
            event.accepted = true;
        }
    }
    Component.onCompleted: {
        Logger.info("Peek", "MarathonPeek component initialized, progress: " + peekProgress);
        forceActiveFocus();
    }
    onVisibleChanged: {
        Logger.debug("Peek", "Visibility changed: " + visible);
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: peekProgress * 0.6
        visible: peekProgress > 0

        MouseArea {
            anchors.fill: parent
            enabled: peekProgress > 0
            onClicked: {
                closePeek();
            }
        }
    }

    Item {
        id: hubPanelContainer

        width: parent.width * 0.85
        height: parent.height
        x: {
            if (peekProgress === 0)
                return -width;
            else
                return -width + (width * peekProgress);
        }
        visible: peekProgress > 0 || isPeeking
        clip: true
        Component.onCompleted: {
            Logger.info("Peek", "hubPanelContainer initialized, width: " + width);
        }

        Item {
            id: notificationPreview

            anchors.fill: parent
            visible: peekProgress < 0.35
            opacity: peekProgress < 0.3 ? 1 : Math.max(0, (0.35 - peekProgress) / 0.05)
            z: 10
            Component.onCompleted: {
                Logger.info("Peek", "NotificationPreview initialized, count: " + NotificationModel.count);
            }

            Rectangle {
                anchors.fill: parent
                color: MColors.surface

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: MSpacing.lg
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: MSpacing.md

                    Repeater {
                        model: NotificationModel
                        onCountChanged: {
                            Logger.info("Peek", "Repeater count changed: " + count + ", NotificationModel.count: " + NotificationModel.count);
                        }
                        Component.onCompleted: {
                            Logger.info("Peek", "Repeater initialized with count: " + count + ", NotificationModel.count: " + NotificationModel.count);
                        }

                        delegate: Item {
                            width: 48
                            height: 48
                            visible: index < 5
                            Component.onCompleted: {
                                Logger.info("Peek", "Notification item created, index: " + index + ", icon: " + (model.icon || "bell") + ", title: " + (model.title || "none"));
                            }

                            Rectangle {
                                id: notifIcon

                                anchors.fill: parent
                                radius: 24
                                color: "transparent"
                                border.width: 1
                                border.color: MColors.border
                                scale: notifMouseArea.pressed ? 0.9 : 1

                                Icon {
                                    name: model.icon || "bell"
                                    size: 24
                                    color: MColors.textPrimary
                                    anchors.centerIn: parent
                                }

                                Rectangle {
                                    visible: !model.isRead
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.rightMargin: -2
                                    anchors.topMargin: -2
                                    width: 10
                                    height: 10
                                    radius: 5
                                    color: MColors.marathonTeal
                                }

                                Behavior on scale {
                                    NumberAnimation {
                                        duration: 100
                                    }
                                }
                            }

                            MouseArea {
                                id: notifMouseArea

                                anchors.fill: parent
                                onClicked: {
                                    HapticManager.light();
                                    Logger.info("Peek", "Notification tapped: " + model.title);
                                    peekComponent.notificationTapped({
                                        "id": model.id,
                                        "title": model.title,
                                        "body": model.body,
                                        "icon": model.icon,
                                        "appId": model.appId
                                    });
                                }
                            }
                        }
                    }

                    Text {
                        visible: NotificationModel.count === 0
                        text: "No notifications"
                        color: MColors.textSecondary
                        font.pixelSize: MTypography.sizeBody
                        font.family: MTypography.fontFamily
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }
        }

        MarathonHub {
            id: hubPanel

            anchors.fill: parent
            isInPeekMode: true
            visible: peekProgress >= 0.3
            opacity: peekProgress < 0.3 ? 0 : Math.min(1, (peekProgress - 0.3) / 0.05)
            onClosed: {
                closePeek();
            }
            Component.onCompleted: {
                Logger.info("Hub", "Initialized in peek panel, width: " + hubPanelContainer.width);
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }
        }

        MouseArea {
            id: closeGestureArea

            property real startX: 0
            property real lastX: 0
            property real velocity: 0
            property real lastTime: 0
            property bool isDragging: false

            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * 0.3
            enabled: isFullyOpen
            z: 100
            onPressed: mouse => {
                startX = mouse.x;
                lastX = mouse.x;
                lastTime = Date.now();
                isDragging = false;
                velocity = 0;
            }
            onPositionChanged: mouse => {
                if (!isDragging) {
                    var deltaX = mouse.x - startX;
                    if (deltaX < -15) {
                        isDragging = true;
                        isPeeking = true;
                        startX = mouse.x;
                        lastX = mouse.x;
                        lastTime = Date.now();
                        Logger.info("Peek", "Close drag started");
                    }
                } else {
                    var now = Date.now();
                    var deltaTime = now - lastTime;
                    if (deltaTime > 0)
                        velocity = (mouse.x - lastX) / deltaTime * 1000;

                    lastX = mouse.x;
                    lastTime = now;
                    var deltaX = mouse.x - startX;
                    var maxDrag = hubPanelContainer.width;
                    peekProgress = Math.max(0, Math.min(1, 1 + (deltaX / maxDrag)));
                }
            }
            onReleased: mouse => {
                if (isDragging) {
                    isDragging = false;
                    isPeeking = false;
                    if (peekProgress < 0.65 || velocity < -500) {
                        Logger.info("Peek", "Closing from drag (progress: " + peekProgress + ", velocity: " + velocity + ")");
                        closePeek();
                    } else {
                        Logger.info("Peek", "Snapping back open");
                        peekProgress = 1;
                    }
                }
            }
            onCanceled: {
                if (isDragging) {
                    isDragging = false;
                    isPeeking = false;
                    peekProgress = 1;
                }
            }
        }

        Behavior on x {
            enabled: !isPeeking

            NumberAnimation {
                duration: 350
                easing.type: Easing.OutCubic
            }
        }
    }

    MouseArea {
        id: gestureArea

        property real startX: 0
        property real lastX: 0
        property real velocity: 0
        property real lastTime: 0

        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Constants.spacingSmall
        enabled: !isFullyOpen
        onPressed: mouse => {
            startX = mouse.x;
            lastX = mouse.x;
            lastTime = Date.now();
            isPeeking = true;
            console.log("👈 Peek gesture started from left edge");
        }
        onPositionChanged: mouse => {
            if (!isPeeking)
                return;

            var absoluteX = gestureArea.x + mouse.x;
            var deltaX = absoluteX - startX;
            var now = Date.now();
            var deltaTime = now - lastTime;
            if (deltaTime > 0)
                velocity = (absoluteX - lastX) / deltaTime * 1000;

            lastX = absoluteX;
            lastTime = now;
            peekProgress = Math.max(0, Math.min(1, deltaX / (peekComponent.width * 0.85)));
        }
        onReleased: {
            if (!isPeeking)
                return;

            isPeeking = false;
            if (peekProgress > peekThreshold || velocity > 500) {
                peekProgress = 1;
                isFullyOpen = true;
                fullyOpened();
            } else {
                closePeek();
            }
        }
        onCanceled: {
            isPeeking = false;
            closePeek();
        }
    }
}
