pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import QtQuick.Effects
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

Item {
    id: taskCard

    required property int index
    required property string id
    required property string appId
    required property string title
    required property string icon
    required property string type
    required property int surfaceId
    required property var waylandSurface
    property bool haveWayland: false
    property real bannerHeight: Theme.itemSizeSmall
    property var compositor: null
    property bool taskSwitcherVisible: true
    property bool gridMoving: false
    property bool gridDragging: false
    property bool suppressTapOpen: false
    property Item nativeSurfaceItem: null
    property bool nativeSurfaceActive: false
    property Item registeredSurfaceItem: null
    // Which preview path this card takes. Not `type === "native"`: a task
    // created through the warm-pool route carries its manifest type instead,
    // so an out-of-process app can read "marathon". Owning a surface is the
    // test that holds whichever route launched it.
    readonly property bool hasWaylandSurface: taskCard.surfaceId > 0 && typeof taskCard.waylandSurface !== 'undefined' && taskCard.waylandSurface !== null
    // Plain bool, not a derived property binding: Qt's binding-loop detector
    // misfires when 14 TaskCards initialize concurrently with SurfaceRegistry
    // fanning out signals. Updated explicitly from updateRegisteredSurface().
    property bool useRegisteredSurface: false
    // An upward drag on the cover closes the app unless the grid needs it to scroll.
    property bool swipeClaimsDrag: true
    // The switcher holds a minimising window over this card's cover.
    readonly property bool docking: WindowOrigins.dockingAppId !== "" && WindowOrigins.dockingAppId === taskCard.appId
    // Showing the last captured cover: the card is on its way out.
    property bool frozen: false

    signal closed
    signal taskClosed(string appId)

    // A function, not a derived property, and every term read straight from
    // its source: this is called from onTaskSwitcherVisibleChanged, and Qt
    // does not guarantee a binding has been re-evaluated by the time a change
    // handler for one of its dependencies runs.
    function wantsNativeSurface() {
        return taskCard.taskSwitcherVisible && taskCard.haveWayland && taskCard.surfaceId > 0 && typeof taskCard.waylandSurface !== 'undefined' && taskCard.waylandSurface !== null;
    }

    function refreshNativeSurface() {
        if (!wantsNativeSurface()) {
            nativeSurfaceActive = false;
            return;
        }
        nativeSurfaceActive = false;
        Qt.callLater(function () {
            nativeSurfaceActive = taskCard.wantsNativeSurface();
        });
    }

    function coverSceneRect() {
        return glass.mapToItem(null, 0, 0, glass.width, glass.height);
    }

    function open() {
        Logger.info("TaskCard", "Opening: " + taskCard.appId);
        WindowOrigins.markLaunch(glass, true);
        var appId = taskCard.appId;
        var appTitle = taskCard.title;
        var appIcon = taskCard.icon;
        var appType = taskCard.type;
        Qt.callLater(function () {
            if (appType !== "native")
                AppLifecycleManager.restoreApp(appId);
            else
                AppLifecycleManager.bringToForeground(appId);
            UIStore.restoreApp(appId, appTitle, appIcon);
            taskCard.closed();
        });
    }

    function flyDistance() {
        return Math.max(cardRoot.height, cardRoot.mapToItem(null, 0, cardRoot.height).y);
    }

    function freeze() {
        coverSnapshot.scheduleUpdate();
        frozen = true;
    }

    function closeTask() {
        Logger.info("TaskCard", "Closing task: " + taskCard.appId + " type: " + taskCard.type);
        if (taskCard.type === "native") {
            if (typeof taskCard.compositor !== 'undefined' && taskCard.compositor && taskCard.surfaceId >= 0) {
                Logger.info("TaskCard", "Closing native app via compositor, surfaceId: " + taskCard.surfaceId);
                AppLifecycleManager.prepareClose(taskCard.appId);
                taskCard.compositor.closeWindow(taskCard.surfaceId);
            }
            TaskModel.closeTask(taskCard.id);
        } else {
            AppLifecycleManager.closeApp(taskCard.appId);
        }
        // A close that left the task in place brings its card back.
        restoreTimer.restart();
    }

    function reset() {
        closeAnimation.stop();
        restoreTimer.stop();
        swipe.stop();
        swipe.value = 0;
        cardRoot.closing = false;
        cardRoot.dismissing = false;
        frozen = false;
    }

    function updateRegisteredSurface() {
        if (taskCard.surfaceId <= 0) {
            registeredSurfaceItem = null;
            useRegisteredSurface = false;
            return;
        }
        registeredSurfaceItem = SurfaceRegistry.getSurfaceItem(taskCard.surfaceId);
        useRegisteredSurface = registeredSurfaceItem !== null;
    }

    onWaylandSurfaceChanged: refreshNativeSurface()
    onSurfaceIdChanged: updateRegisteredSurface()
    onTaskSwitcherVisibleChanged: {
        refreshNativeSurface();
        updateRegisteredSurface();
    }
    onHaveWaylandChanged: {
        refreshNativeSurface();
        updateRegisteredSurface();
    }
    // The app can exit before its card has animated out; the card keeps its last face.
    GridView.onRemove: freeze()
    GridView.onReused: reset()
    Component.onCompleted: {
        refreshNativeSurface();
        updateRegisteredSurface();
    }

    // Swipe-to-close: value is the cover's upward travel in px.
    GestureTracker {
        id: swipe

        from: 0
        commitDistance: cardRoot.height * 0.3
        settleDuration: MMotion.moderate
        // Close as soon as the cover has faded out; the spring's tail is invisible.
        onValueChanged: {
            if (cardRoot.dismissing && cardRoot.opacity === 0) {
                swipe.stop();
                cardRoot.dismissing = false;
                cardRoot.closing = true;
                taskCard.closeTask();
            }
        }
        onSettled: {
            if (cardRoot.dismissing) {
                cardRoot.dismissing = false;
                cardRoot.closing = true;
                taskCard.closeTask();
            }
        }
    }

    Timer {
        id: restoreTimer

        interval: 1000
        onTriggered: taskCard.reset()
    }

    Item {
        id: cardRoot

        property bool closing: false
        property bool dismissing: false

        anchors.centerIn: parent
        anchors.verticalCenterOffset: swipe.value
        // The cell's width, or narrower where the cover's shape would overrun its height.
        width: Math.max(0, Math.min(taskCard.width - 2 * Theme.paddingSmall, (taskCard.height - 2 * Theme.paddingSmall - taskCard.bannerHeight) * Theme.coverSizeLarge.width / Theme.coverSizeLarge.height))
        height: glass.height + bannerRect.height
        readonly property bool pressed: (previewTapArea.pressed || handleTapArea.pressed) && !taskCard.suppressTapOpen

        property real closeFade: closing ? 0 : 1

        scale: closing ? 0.7 : (pressed ? 0.97 : 1)
        opacity: closeFade * (1 - Math.min(1, -swipe.value / Math.max(1, swipe.commitDistance * 2.5)))

        SequentialAnimation {
            id: closeAnimation

            ScriptAction {
                script: {
                    taskCard.freeze();
                    cardRoot.closing = true;
                }
            }

            PauseAnimation {
                duration: MMotion.moderate
            }

            ScriptAction {
                script: taskCard.closeTask()
            }
        }

        // The cover's own shape (Theme.coverSizeLarge at the card's width).
        Rectangle {
            id: glass

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: Math.round(width * Theme.coverSizeLarge.height / Theme.coverSizeLarge.width)
            // Neutral dark glass: the highlight colours only mark text and state.
            color: Qt.rgba(0, 0, 0, 0.55)
            radius: Theme.paddingMedium
            antialiasing: true
            visible: !taskCard.docking
        }

        // Taps open the app; an upward drag carries the cover off to close it.
        MouseArea {
            id: previewTapArea

            property real pressX: 0
            property real pressY: 0
            property real pressValue: 0
            property bool swiping: false

            // In taskCard coordinates: the cover moves under the finger.
            function cardPoint(mouse) {
                return mapToItem(taskCard, mouse.x, mouse.y);
            }

            anchors.fill: glass
            z: 50
            enabled: !cardRoot.dismissing && !cardRoot.closing
            preventStealing: false
            propagateComposedEvents: true
            onPressed: mouse => {
                var p = cardPoint(mouse);
                pressX = p.x;
                pressY = p.y;
                pressValue = swipe.value;
                swiping = false;
                preventStealing = taskCard.swipeClaimsDrag;
                swipe.to = -taskCard.flyDistance();
                swipe.press();
                mouse.accepted = true;
            }
            onPositionChanged: mouse => {
                var p = cardPoint(mouse);
                var dx = p.x - pressX;
                var dy = p.y - pressY;
                if (!swiping && Math.abs(dy) > Qt.styleHints.startDragDistance && Math.abs(dy) > Math.abs(dx)) {
                    if (dy < 0 && taskCard.swipeClaimsDrag)
                        swiping = true;
                    else
                        preventStealing = false;
                }
                if (swiping) {
                    var v = pressValue + dy;
                    swipe.move(v < 0 ? v : v * 0.2);
                }
            }
            onReleased: mouse => {
                var commit = swipe.release();
                if (swiping) {
                    swiping = false;
                    if (commit) {
                        taskCard.freeze();
                        cardRoot.dismissing = true;
                        swipe.settleTo(swipe.to, Math.min(swipe.velocity, -swipe.flingVelocity));
                    } else {
                        swipe.settleTo(0);
                    }
                    return;
                }
                var p = cardPoint(mouse);
                if (!taskCard.suppressTapOpen && Math.abs(p.x - pressX) < 15 && Math.abs(p.y - pressY) < 15) {
                    mouse.accepted = true;
                    taskCard.open();
                }
            }
            onCanceled: {
                swipe.release();
                if (swiping)
                    swipe.settleTo(0);
                swiping = false;
            }
        }

        Rectangle {
            anchors.fill: glass
            anchors.margins: 1
            z: 3
            radius: glass.radius - 1
            color: "transparent"
            border.width: 1
            border.color: cardRoot.pressed ? Theme.highlightColor : Theme.rgba(Theme.primaryColor, 0.1)
            visible: !taskCard.docking
        }

        // The cover fills the glass; a live preview keeps the app's shape,
        // centred when wider than the card. One layer rounds both corners.
        Item {
            id: cardContent

            anchors.centerIn: glass
            width: glass.width
            height: coverView.available ? glass.height : Math.min(glass.height, glass.width * (Constants.screenWidth > 0 ? Constants.screenHeight / Constants.screenWidth : 1))
            visible: !taskCard.docking
            layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: previewMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            Item {
                anchors.fill: parent

                KeelCoverView {
                    id: coverView

                    anchors.fill: parent
                    z: 2
                    appId: taskCard.appId
                    compositor: taskCard.compositor
                    shown: taskCard.taskSwitcherVisible
                }

                Loader {
                    id: appPreview

                    anchors.fill: parent
                    visible: !coverView.available
                    active: true
                    asynchronous: true

                    sourceComponent: Item {
                        anchors.fill: parent
                        clip: true
                        enabled: false

                        Item {
                            id: livePreview

                            anchors.fill: parent

                            Item {
                                id: previewContainer

                                property var liveApp: null
                                property string trackedAppId: ""
                                property string watchedAppId: taskCard.appId

                                function updateLiveApp() {
                                    if (trackedAppId !== "" && trackedAppId !== taskCard.appId) {
                                        Logger.info("TaskCard", "DELEGATE RECYCLED: " + trackedAppId + " → " + taskCard.appId);
                                        liveApp = null;
                                    }
                                    trackedAppId = taskCard.appId;
                                    if (taskCard.hasWaylandSurface) {
                                        liveApp = null;
                                        return;
                                    }
                                    var instance = AppLifecycleManager.getAppInstance(taskCard.appId);
                                    liveApp = instance;
                                    if (liveApp)
                                        snapshotUpdateDebounce.restart();
                                }

                                anchors.fill: parent
                                visible: true
                                clip: true
                                onWatchedAppIdChanged: updateLiveApp()
                                Component.onCompleted: updateLiveApp()
                                onLiveAppChanged: snapshotUpdateDebounce.restart()

                                Timer {
                                    id: snapshotUpdateDebounce

                                    interval: 16
                                    repeat: false
                                    onTriggered: {
                                        if (liveSnapshot.visible)
                                            liveSnapshot.scheduleUpdate();
                                    }
                                }

                                Connections {
                                    function onAppRegistered(appId, instance) {
                                        if (taskCard.hasWaylandSurface)
                                            return;

                                        if (appId !== taskCard.appId)
                                            return;

                                        previewContainer.liveApp = instance;
                                        snapshotUpdateDebounce.restart();
                                    }

                                    function onAppUnregistered(appId) {
                                        if (appId !== taskCard.appId)
                                            return;

                                        previewContainer.liveApp = null;
                                    }

                                    target: AppLifecycleManager
                                }

                                Connections {
                                    function onTaskSwitcherVisibleChanged() {
                                        if (taskCard.taskSwitcherVisible)
                                            snapshotUpdateDebounce.restart();
                                    }

                                    function onGridMovingChanged() {
                                        if (!taskCard.gridMoving)
                                            snapshotUpdateDebounce.restart();
                                    }

                                    function onGridDraggingChanged() {
                                        if (!taskCard.gridDragging)
                                            snapshotUpdateDebounce.restart();
                                    }

                                    target: taskCard
                                }

                                ShaderEffectSource {
                                    id: liveSnapshot

                                    // Fill the card at the app's aspect from the top, so the
                                    // header shows; the card clips the overflow.
                                    property real appAspect: (Constants.screenHeight > 0 && Constants.screenWidth > 0) ? (Constants.screenHeight / Constants.screenWidth) : 1.0
                                    property real parentAspect: (parent.height > 0 && parent.width > 0) ? (parent.height / parent.width) : 1.0
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.top: parent.top
                                    width: parentAspect >= appAspect ? parent.height / appAspect : parent.width
                                    height: parentAspect >= appAspect ? parent.height : parent.width * appAspect
                                    sourceItem: previewContainer.liveApp
                                    live: false
                                    recursive: true
                                    visible: previewContainer.liveApp !== null
                                    hideSource: false
                                    mipmap: false
                                    smooth: false
                                    format: ShaderEffectSource.RGBA
                                    samples: 0
                                    onVisibleChanged: {
                                        if (visible)
                                            liveSnapshot.scheduleUpdate();
                                    }
                                }

                                // Periodic 200 ms snapshot refresh REMOVED — it was
                                // causing visible flicker when entering card mode.
                                // The card-mode-enter animation transforms the live
                                // app surface mid-capture, and re-snapshotting every
                                // 200 ms during that animation produced inconsistent
                                // textures (a frame of mid-transform, then the next
                                // frame, etc.) that read as flashing. Snapshot is
                                // now taken once when the switcher becomes visible
                                // and when grid moving/dragging stops (see
                                // Connections above), iOS-style frozen preview.

                                Loader {
                                    id: nativeSurfaceLoader

                                    // Fills the card like liveSnapshot above.
                                    property real appAspect: (Constants.screenHeight > 0 && Constants.screenWidth > 0) ? (Constants.screenHeight / Constants.screenWidth) : 1.0
                                    property real parentAspect: (parent.height > 0 && parent.width > 0) ? (parent.height / parent.width) : 1.0
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.top: parent.top
                                    width: parentAspect >= appAspect ? parent.height / appAspect : parent.width
                                    height: parentAspect >= appAspect ? parent.height : parent.width * appAspect
                                    visible: taskCard.hasWaylandSurface
                                    active: taskCard.nativeSurfaceActive
                                    source: taskCard.haveWayland ? "qrc:/qt/qml/MarathonOS/Shell/qml/components/WaylandShellSurfaceItem.qml" : ""
                                    onItemChanged: {
                                        if (item) {
                                            taskCard.nativeSurfaceItem = item;
                                            taskCard.nativeSurfaceItem.anchors.fill = nativeSurfaceLoader;
                                            item.autoResize = false;
                                            item.hasSentInitialSize = true;
                                            item.isMinimized = true;
                                            // Gates bufferLocked, front-buffer discard and
                                            // the content nudge. Without it this view takes
                                            // foreground semantics and locks onto a buffer it
                                            // was never given.
                                            item.isPreview = true;
                                        } else {
                                            taskCard.nativeSurfaceItem = null;
                                        }
                                    }

                                    Binding {
                                        target: taskCard.nativeSurfaceItem
                                        property: "surfaceObj"
                                        value: taskCard.waylandSurface
                                        when: taskCard.nativeSurfaceItem !== null
                                    }

                                    Binding {
                                        target: taskCard.nativeSurfaceItem
                                        property: "surfaceId"
                                        value: taskCard.surfaceId
                                        when: taskCard.nativeSurfaceItem !== null
                                    }

                                    Binding {
                                        target: taskCard.nativeSurfaceItem
                                        property: "touchEventsEnabled"
                                        value: false
                                        when: taskCard.nativeSurfaceItem !== null
                                    }

                                    Binding {
                                        target: taskCard.nativeSurfaceItem
                                        property: "inputEventsEnabled"
                                        value: false
                                        when: taskCard.nativeSurfaceItem !== null
                                    }
                                }

                                ShaderEffectSource {
                                    id: registeredSurfacePreview

                                    anchors.fill: nativeSurfaceLoader
                                    sourceItem: taskCard.registeredSurfaceItem
                                    // Mirror only when the card is on screen and has
                                    // no view of its own. Declared after the loader, so
                                    // a stale `visible` here paints over it; and
                                    // useRegisteredSurface tracks the registry alone, so
                                    // without the page term this reads true precisely
                                    // when the page is off screen.
                                    visible: taskCard.taskSwitcherVisible && taskCard.useRegisteredSurface && !taskCard.nativeSurfaceActive
                                    live: registeredSurfacePreview.visible
                                    recursive: true
                                    hideSource: false
                                    smooth: false
                                    format: ShaderEffectSource.RGBA
                                    samples: 0
                                }

                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: parent.width
                                    height: (Constants.screenHeight / Constants.screenWidth) * width
                                    visible: previewContainer.liveApp === null && !taskCard.hasWaylandSurface
                                    color: "transparent"

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: Theme.paddingMedium

                                        MAppIcon {
                                            size: Theme.iconSizeLarge
                                            source: taskCard.icon || "layout-grid"
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }

                                        Label {
                                            text: taskCard.title || taskCard.appId
                                            color: Theme.secondaryColor
                                            font.pixelSize: Theme.fontSizeSmall
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }

                                        Label {
                                            text: "Preview unavailable"
                                            color: Theme.secondaryColor
                                            font.pixelSize: Theme.fontSizeExtraSmall
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // The cover's last face, refreshed when the switcher opens and as
        // the card starts to close; shown once the app behind it may be gone.
        ShaderEffectSource {
            id: coverSnapshot

            anchors.fill: cardContent
            sourceItem: cardContent
            readonly property bool shown: taskCard.frozen && GraphicsInfo.api !== GraphicsInfo.Software

            live: false
            hideSource: shown
            opacity: shown ? 1 : 0
            visible: !taskCard.docking
        }

        Rectangle {
            id: previewMask

            anchors.fill: cardContent
            radius: glass.radius
            antialiasing: true
            visible: false
            layer.enabled: true
        }

        Rectangle {
            id: bannerRect

            anchors.top: glass.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: taskCard.bannerHeight
            color: "transparent"

            MouseArea {
                id: handleTapArea

                property real pressX: 0
                property real pressY: 0
    
                anchors.fill: parent
                z: 50
                preventStealing: false
                propagateComposedEvents: false
                onPressed: mouse => {
                    // Mirror the close button's expanded MouseArea bounds
                    // (anchors.margins: -16) — otherwise this banner-wide tap
                    // area steals taps in the 16 px ring meant to enlarge the
                    // close target.
                    var hitMargin = 16;
                    var p = closeButtonRect.mapToItem(handleTapArea, -hitMargin, -hitMargin);
                    var w = closeButtonRect.width + (hitMargin * 2);
                    var h = closeButtonRect.height + (hitMargin * 2);
                    if (mouse.x >= p.x && mouse.x <= p.x + w && mouse.y >= p.y && mouse.y <= p.y + h) {
                        mouse.accepted = false;
                        return;
                    }
                    pressX = mouse.x;
                    pressY = mouse.y;
                        mouse.accepted = true;
                }
                onReleased: mouse => {
                    var deltaX = Math.abs(mouse.x - pressX);
                    var deltaY = Math.abs(mouse.y - pressY);
                    if (!taskCard.suppressTapOpen && deltaX < 15 && deltaY < 15) {
                        mouse.accepted = true;
                        taskCard.open();
                    }
                }
            }

            Row {
                anchors.fill: parent
                spacing: Theme.paddingSmall

                MAppIcon {
                    id: bannerIcon
                    anchors.verticalCenter: parent.verticalCenter
                    source: taskCard.icon
                    size: Theme.iconSizeSmall
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - bannerIcon.width - closeButtonContainer.width - parent.spacing * 2

                    Label {
                        text: taskCard.title
                        color: Theme.secondaryColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                        truncationMode: TruncationMode.Fade
                        width: parent.width
                    }
                }

                Item {
                    id: closeButtonContainer

                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.iconSizeSmall
                    height: Theme.iconSizeSmall

                    Rectangle {
                        id: closeButtonRect

                        anchors.centerIn: parent
                        width: Theme.iconSizeSmall
                        height: Theme.iconSizeSmall
                        color: "transparent"

                        Accessible.role: Accessible.Button
                        Accessible.name: "Close " + taskCard.title

                        HighlightImage {
                            anchors.centerIn: parent
                            width: Theme.iconSizeSmall
                            height: width
                            sourceSize.width: width
                            sourceSize.height: height
                            source: "image://theme/icon-m-close"
                            highlighted: closeButtonArea.pressed
                        }

                        MouseArea {
                            id: closeButtonArea

                            anchors.fill: parent
                            anchors.margins: -Theme.paddingLarge
                            z: 1000
                            preventStealing: true
                            onPressed: mouse => {
                                taskCard.suppressTapOpen = true;
                                mouse.accepted = true;
                            }
                            onClicked: mouse => {
                                Logger.info("TaskCard", "Closing task via button: " + taskCard.appId);
                                mouse.accepted = true;
                                closeAnimation.start();
                            }
                            onReleased: mouse => {
                                taskCard.suppressTapOpen = false;
                                mouse.accepted = true;
                            }
                            onCanceled: {
                                taskCard.suppressTapOpen = false;
                            }
                        }
                    }
                }
            }
        }

        Behavior on scale {
            NumberAnimation {
                duration: cardRoot.closing ? MMotion.moderate : MMotion.quick
                easing.type: Easing.OutCubic
            }
        }

        Behavior on closeFade {
            NumberAnimation {
                duration: MMotion.moderate
                easing.type: Easing.OutCubic
            }
        }
    }

    Connections {
        function onSurfaceRegistered(surfaceId) {
            if (surfaceId === taskCard.surfaceId)
                taskCard.updateRegisteredSurface();
        }

        function onSurfaceUnregistered(surfaceId) {
            if (surfaceId === taskCard.surfaceId)
                taskCard.updateRegisteredSurface();
        }

        target: SurfaceRegistry
    }

    Behavior on scale {
        enabled: Constants.enableAnimations

        NumberAnimation {
            duration: 250
            easing.type: Easing.OutCubic
        }
    }
}
