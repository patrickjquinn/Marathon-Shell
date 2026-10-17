pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

Item {
    id: peekComponent

    readonly property real peekProgress: peekDrag.progress
    property real peekThreshold: 0.4
    property bool isPeeking: false
    property bool isFullyOpen: false
    // Where a running settle was caught when the finger came down.
    property real gestureBase: 0

    signal closed
    signal fullyOpened
    signal notificationTapped(var notification)

    function startPeekGesture(x) {
        isPeeking = true;
        peekDrag.press();
        gestureBase = peekDrag.value;
    }

    function updatePeekGesture(deltaX) {
        if (!isPeeking)
            return;

        peekDrag.move(Math.max(0, Math.min(peekDrag.to, gestureBase + deltaX)));
    }

    function endPeekGesture() {
        if (!isPeeking)
            return;

        isPeeking = false;
        var shouldOpen = peekDrag.release();
        if (shouldOpen)
            openPeek();
        else
            peekComponent.closePeek();
        Logger.info("Peek", "Gesture ended - " + (shouldOpen ? "opening" : "closing") + " (velocity: " + peekDrag.velocity.toFixed(0) + "px/s, progress: " + (peekProgress * 100).toFixed(0) + "%)");
    }

    function openPeek() {
        if (!isFullyOpen)
            HapticManager.tick();
        peekDrag.settleTo(peekDrag.to);
        isFullyOpen = true;
        fullyOpened();
    }

    function closePeek() {
        peekDrag.settleTo(0);
        isFullyOpen = false;
        closed();
    }

    // True when the Hub closed something of its own.
    function closeHubOverlay() {
        return hubPanel.closeOverlay();
    }

    anchors.fill: parent
    clip: true
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape && peekProgress > 0) {
            peekComponent.closePeek();
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
        color: "black"
        opacity: peekComponent.peekProgress * 0.6
        visible: peekComponent.peekProgress > 0

        MouseArea {
            anchors.fill: parent
            enabled: peekComponent.peekProgress > 0
            onClicked: peekComponent.closePeek()
        }
    }

    Item {
        id: hubPanelContainer

        // 0.85 parent.width during partial peek (so the surface beneath
        // remains visible on the right). Ramp to parent.width over the
        // last 15 % of progress so a fully-opened Hub covers the
        // screen edge-to-edge.
        width: parent.width * (0.85 + 0.15 * Math.max(0, Math.min(1, (peekComponent.peekProgress - 0.85) / 0.15)))
        height: parent.height
        x: {
            if (peekComponent.peekProgress === 0)
                return -width;
            else
                return -width + (width * peekComponent.peekProgress);
        }
        visible: peekComponent.peekProgress > 0 || peekComponent.isPeeking
        clip: true
        Component.onCompleted: {
            Logger.info("Peek", "hubPanelContainer initialized, width: " + width);
        }

        Item {
            id: notificationPreview

            anchors.fill: parent
            visible: peekComponent.peekProgress < 0.35
            opacity: peekComponent.peekProgress < 0.3 ? 1 : Math.max(0, (0.35 - peekComponent.peekProgress) / 0.05)
            z: 10
            Component.onCompleted: {
                Logger.info("Peek", "NotificationPreview initialized, count: " + NotificationModel.count);
            }

            Rectangle {
                anchors.fill: parent
                color: Silica.Theme.rgba("black", 0.85)

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: Silica.Theme.horizontalPageMargin
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Silica.Theme.paddingMedium

                    Repeater {
                        model: NotificationModel
                        onCountChanged: {
                            Logger.info("Peek", "Repeater count changed: " + count + ", NotificationModel.count: " + NotificationModel.count);
                        }
                        Component.onCompleted: {
                            Logger.info("Peek", "Repeater initialized with count: " + count + ", NotificationModel.count: " + NotificationModel.count);
                        }

                        delegate: Item {
                            id: notifDelegate

                            required property int index
                            required property var model

                            width: Silica.Theme.iconSizeMedium
                            height: width
                            visible: index < 5
                            Component.onCompleted: {
                                Logger.info("Peek", "Notification item created, index: " + index + ", icon: " + (model.icon || "bell") + ", title: " + (model.title || "none"));
                            }

                            Rectangle {
                                id: notifIcon

                                anchors.fill: parent
                                radius: width / 2
                                color: notifMouseArea.pressed ? Silica.Theme.rgba(Silica.Theme.highlightBackgroundColor, Silica.Theme.highlightBackgroundOpacity) : "transparent"
                                border.width: Math.max(1, Math.round(Silica.Theme.paddingSmall / 4))
                                border.color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.35)

                                GlyphIcon {
                                    name: notifDelegate.model.icon || "bell"
                                    size: Silica.Theme.iconSizeExtraSmall
                                    color: notifMouseArea.pressed ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                                    anchors.centerIn: parent
                                }

                                Rectangle {
                                    visible: !notifDelegate.model.isRead
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    width: Silica.Theme.paddingSmall
                                    height: width
                                    radius: width / 2
                                    color: Silica.Theme.highlightColor
                                }
                            }

                            MouseArea {
                                id: notifMouseArea

                                anchors.fill: parent
                                onClicked: {
                                    HapticManager.light();
                                    Logger.info("Peek", "Notification tapped: " + notifDelegate.model.title);
                                    peekComponent.notificationTapped({
                                        "id": notifDelegate.model.id,
                                        "title": notifDelegate.model.title,
                                        "body": notifDelegate.model.body,
                                        "icon": notifDelegate.model.icon,
                                        "appId": notifDelegate.model.appId
                                    });
                                }
                            }
                        }
                    }

                    Silica.Label {
                        visible: NotificationModel.count === 0
                        text: "No notifications"
                        color: Silica.Theme.secondaryColor
                        font.pixelSize: Silica.Theme.fontSizeMedium
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
            visible: peekComponent.peekProgress >= 0.3
            opacity: peekComponent.peekProgress < 0.3 ? 0 : Math.min(1, (peekComponent.peekProgress - 0.3) / 0.05)
            onClosed: {
                peekComponent.closePeek();
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

        // Dragging left from the right side closes the peek. A handler on
        // this parent, not an overlay, so taps and scrolls reach the Hub.
        DragHandler {
            id: closeDrag

            readonly property bool fromRight: centroid.pressPosition.x > parent.width * 0.7

            target: null
            enabled: peekComponent.isFullyOpen
            yAxis.enabled: false
            onActiveChanged: {
                if (!fromRight)
                    return;
                if (active) {
                    peekComponent.startPeekGesture(centroid.position.x);
                    return;
                }
                peekComponent.isPeeking = false;
                // Closing runs the other way along the tracker's range.
                peekDrag.release();
                if (peekDrag.decide(peekDrag.to - peekDrag.value, -peekDrag.velocity))
                    peekComponent.closePeek();
                else
                    peekDrag.settleTo(peekDrag.to);
            }
            onTranslationChanged: {
                if (active && fromRight)
                    peekComponent.updatePeekGesture(Math.min(0, activeTranslation.x));
            }
        }
    }

    MouseArea {
        id: gestureArea

        property real startX: 0

        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Constants.spacingSmall
        enabled: !peekComponent.isFullyOpen
        onPressed: mouse => {
            startX = mouse.x;
            peekComponent.startPeekGesture(mouse.x);
        }
        onPositionChanged: mouse => peekComponent.updatePeekGesture(mouse.x - startX)
        onReleased: peekComponent.endPeekGesture()
        onCanceled: {
            peekComponent.isPeeking = false;
            peekComponent.closePeek();
        }
    }

    GestureTracker {
        id: peekDrag

        to: peekComponent.width * 0.85
        commitDistance: peekComponent.peekThreshold * to
        settleDuration: MMotion.reduceMotion ? MMotion.micro : Constants.animationSlow
    }
}
