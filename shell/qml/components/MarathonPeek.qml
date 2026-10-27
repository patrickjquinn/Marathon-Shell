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
    // As BB10's peek, a pull first rests on the apps with notifications.
    property bool iconsShown: false
    readonly property real iconsStop: Math.max(0.2 * peekDrag.to, Silica.Theme.iconSizeMedium + 2 * Silica.Theme.paddingLarge)
    // Where a running settle was caught when the finger came down.
    property real gestureBase: 0

    signal closed
    signal fullyOpened

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
        peekDrag.release();
        settleAtStop();
    }

    // A fling goes all the way; otherwise the nearest of shut, the icons
    // and the Hub, with the Hub from peekThreshold.
    function settleAtStop() {
        const v = peekDrag.velocity, x = peekDrag.value;
        if (v >= peekDrag.flingVelocity || (v > -peekDrag.flingVelocity && x >= peekThreshold * peekDrag.to))
            openPeek();
        else if (v > -peekDrag.flingVelocity && x >= iconsStop / 2)
            showIcons();
        else
            closePeek();
    }

    function showIcons() {
        if (!iconsShown)
            HapticManager.tick();
        peekDrag.settleTo(iconsStop);
        iconsShown = true;
        isFullyOpen = false;
    }

    function openPeek() {
        if (!isFullyOpen)
            HapticManager.tick();
        peekDrag.settleTo(peekDrag.to);
        iconsShown = false;
        isFullyOpen = true;
        fullyOpened();
    }

    function closePeek() {
        peekDrag.settleTo(0);
        hubPanel.filterApp = "";
        iconsShown = false;
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
        Accessible.role: Accessible.Pane
        //: Accessible name of the Hub panel while it is pulled out
        Accessible.name: qsTr("Hub")
        Component.onCompleted: {
            Logger.info("Peek", "hubPanelContainer initialized, width: " + width);
        }

        Rectangle {
            anchors.fill: parent
            color: MColors.elev1
            visible: peekComponent.peekProgress < 0.35
            opacity: Math.max(0, Math.min(1, (0.35 - peekComponent.peekProgress) / 0.05))
        }

        // The apps with notifications, newest first, on the edge the pull
        // reveals; a tap opens the Hub on that app.
        Item {
            id: iconStrip

            objectName: "peekIcons"
            anchors.right: parent.right
            width: peekComponent.iconsStop
            height: parent.height
            visible: peekComponent.peekProgress < 0.35
            opacity: Math.max(0, Math.min(1, (0.35 - peekComponent.peekProgress) / 0.05))
            z: 10

            Column {
                anchors.centerIn: parent
                spacing: Silica.Theme.paddingLarge

                Repeater {
                    objectName: "peekSources"
                    model: hubPanel.sources.slice(0, Math.max(1, Math.floor((iconStrip.height - 2 * Constants.navBarHeight) / (Silica.Theme.iconSizeMedium + Silica.Theme.paddingLarge))))

                    delegate: Item {
                        id: source

                        required property var modelData
                        readonly property string icon: AppModel.count === 0 ? "" : (AppModel.findById(modelData.app).icon || "")

                        objectName: "peekIcon"
                        width: Silica.Theme.iconSizeMedium
                        height: width
                        opacity: sourceArea.pressed ? Silica.Theme.opacityHigh : 1

                        MAppIcon {
                            visible: source.icon !== ""
                            source: source.icon
                            size: parent.width
                            anchors.centerIn: parent
                        }

                        Rectangle {
                            visible: source.icon === ""
                            anchors.fill: parent
                            radius: width / 2
                            color: MColors.elev4

                            GlyphIcon {
                                name: "bell"
                                size: Silica.Theme.iconSizeSmall
                                color: Silica.Theme.primaryColor
                                anchors.centerIn: parent
                            }
                        }

                        Rectangle {
                            objectName: "peekBadge"
                            visible: source.modelData.unread > 0
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.topMargin: -4
                            anchors.rightMargin: -4
                            height: badgeLabel.font.pixelSize + 8
                            width: Math.max(height, badgeLabel.implicitWidth + 10)
                            radius: height / 2
                            color: MColors.marathonTealBright
                            border.width: 2
                            border.color: MColors.elev0

                            Text {
                                id: badgeLabel

                                text: source.modelData.unread > 9 ? "9+" : source.modelData.unread.toString()
                                color: MColors.textOnAccent
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeEyebrow
                                font.weight: MTypography.weightDemiBold
                                font.features: ({
                                        "tnum": 1
                                    })
                                anchors.centerIn: parent
                            }
                        }

                        MouseArea {
                            id: sourceArea

                            anchors.fill: parent
                            onClicked: {
                                HapticManager.light();
                                hubPanel.filterApp = source.modelData.app;
                                peekComponent.openPeek();
                            }
                        }
                    }
                }

                Silica.Label {
                    visible: hubPanel.sources.length === 0
                    width: iconStrip.width - 2 * Silica.Theme.paddingSmall
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: qsTr("No notifications")
                    color: Silica.Theme.secondaryColor
                    font.pixelSize: Silica.Theme.fontSizeExtraSmall
                }
            }

            // Resting on the icons, a drag carries on to the Hub or back shut.
            DragHandler {
                target: null
                enabled: peekComponent.iconsShown
                yAxis.enabled: false
                onActiveChanged: {
                    if (active)
                        peekComponent.startPeekGesture(centroid.position.x);
                    else
                        peekComponent.endPeekGesture();
                }
                onTranslationChanged: {
                    if (active)
                        peekComponent.updatePeekGesture(activeTranslation.x);
                }
            }
        }

        MarathonHub {
            id: hubPanel

            objectName: "peekHub"
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

            // Dragging left from its right side, above the nav bar, closes
            // the peek. The mask keeps the handler off everything else, and
            // as the Hub's own handler it lets taps and scrolls reach the Hub.
            containmentMask: QtObject {
                function contains(point: point): bool {
                    return point.x > hubPanel.width * 0.7 && point.y < hubPanel.height - Constants.navBarHeight;
                }
            }

            DragHandler {
                target: null
                enabled: peekComponent.isFullyOpen
                yAxis.enabled: false
                onActiveChanged: {
                    if (active) {
                        peekComponent.startPeekGesture(centroid.position.x);
                        return;
                    }
                    peekComponent.endPeekGesture();
                }
                onTranslationChanged: {
                    if (active)
                        peekComponent.updatePeekGesture(Math.min(0, activeTranslation.x));
                }
            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                }
            }
        }
    }

    MouseArea {
        id: gestureArea

        property real startX: 0

        anchors.left: parent.left
        anchors.top: parent.top
        // Over an app, leave its page header's back indicator its taps, as
        // Android excludes gesture regions an app claims.
        anchors.topMargin: UIStore.appWindowOpen ? Constants.statusBarHeight + Silica.Theme.itemSizeLarge : 0
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
