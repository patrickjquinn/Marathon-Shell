pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0

Item {
    id: taskCard

    required property int index
    required property string id
    required property string appId
    required property string title
    required property string icon
    required property string type
    required property int surfaceId
    readonly property var waylandSurface: surfaceId > 0 && WaylandCompositorManager.compositor ? WaylandCompositorManager.compositor.shellSurfaceById(surfaceId) : null
    property bool haveWayland: false
    property real bannerHeight: Theme.itemSizeSmall
    // The cover area, the size Keel covers are laid out at.
    property size coverSize
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
    // A marathon_surface_v1 secure window, or a secure app's: its content stays off the card.
    readonly property var marathonSurface: compositor && compositor.marathonSurfaces ? compositor.marathonSurfaces[surfaceId] : undefined
    readonly property bool secure: (marathonSurface ? marathonSurface.secure : false) || (Tasks.secureApps || []).indexOf(taskCard.appId) >= 0

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
                Tasks.restoreApp(appId);
            else
                Tasks.bringToForeground(appId);
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
                Tasks.prepareClose(taskCard.appId);
                // Its live windows: Waydroid re-creates an app's window, so the
                // card's own surface may be gone.
                if (Tasks.closeAppWindows(taskCard.appId) === 0)
                    taskCard.compositor.closeWindow(taskCard.surfaceId);
            }
            Tasks.closeTask(taskCard.id);
        } else {
            Tasks.closeApp(taskCard.appId, false);
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
    // Gone with its task, it stays closed.
    GridView.onRemove: {
        restoreTimer.stop();
        freeze();
    }
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
        width: glass.width
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

        Rectangle {
            id: glass

            anchors.top: parent.top
            anchors.left: parent.left
            width: Math.floor(taskCard.coverSize.width)
            height: Math.floor(taskCard.coverSize.height)
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
                preventStealing = false;
                swipe.to = -taskCard.flyDistance();
                swipe.press();
                mouse.accepted = true;
            }
            onPositionChanged: mouse => {
                var p = cardPoint(mouse);
                var dx = p.x - pressX;
                var dy = p.y - pressY;
                if (!swiping && Math.abs(dy) > Application.styleHints.startDragDistance && Math.abs(dy) > Math.abs(dx)) {
                    // Held only once it is a close: sideways is the pager's.
                    if (dy < 0 && taskCard.swipeClaimsDrag) {
                        swiping = true;
                        preventStealing = true;
                    }
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

        // The cover is laid out at the glass's size; a live preview fills it,
        // cropped from the top. Both draw through rounded WindowTextureItems,
        // so the card needs no layer.
        Item {
            id: cardContent

            anchors.fill: glass
            visible: !taskCard.docking

            Item {
                anchors.fill: parent

                KeelCoverView {
                    id: coverView

                    anchors.fill: parent
                    z: 2
                    appId: taskCard.appId
                    compositor: taskCard.compositor
                    shown: taskCard.taskSwitcherVisible
                    radius: glass.radius
                }

                Loader {
                    id: appPreview

                    anchors.fill: parent
                    visible: !coverView.available
                    active: !taskCard.secure
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
                                    var instance = AppInstances.get(taskCard.appId);
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

                                    target: Tasks
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
                                    property real appAspect: previewContainer.liveApp && previewContainer.liveApp.width > 0 && previewContainer.liveApp.height > 0 ? previewContainer.liveApp.height / previewContainer.liveApp.width : (Constants.screenHeight > 0 && Constants.screenWidth > 0) ? (Constants.screenHeight / Constants.screenWidth) : 1.0
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
                                    opacity: liveTexture.ready ? 0 : 1
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
                                    opacity: liveTexture.ready ? 0 : 1
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

                                // Draws whichever of the views above has the app's
                                // frame, cropped to the card from the top and
                                // rounded; the views stay at opacity 0 to keep their
                                // textures current. The registered surface is the
                                // fallback while the card has no view of its own,
                                // and only while the page is on screen.
                                // A window that draws in subsurfaces (Waydroid: a black
                                // 1x1 toplevel, Android's layers in subsurfaces) has
                                // nothing in its own texture; the card takes its tree.
                                ShaderEffectSource {
                                    id: surfaceTree

                                    readonly property Item surfaceItem: taskCard.nativeSurfaceActive ? taskCard.nativeSurfaceItem : taskCard.taskSwitcherVisible && taskCard.useRegisteredSurface ? taskCard.registeredSurfaceItem : null
                                    readonly property bool drawsInSubsurfaces: surfaceItem !== null && surfaceItem.children.some(child => child.surface !== undefined && child.surface !== null) // qmllint disable missing-property

                                    width: surfaceItem ? surfaceItem.width : 0
                                    height: surfaceItem ? surfaceItem.height : 0
                                    sourceItem: drawsInSubsurfaces ? surfaceItem : null
                                    live: taskCard.taskSwitcherVisible
                                    hideSource: false
                                    opacity: 0
                                }

                                WindowTextureItem {
                                    id: liveTexture

                                    // The texture's own shape: a surface's buffer, which
                                    // can be any size, or the snapshot's.
                                    readonly property size textureSize: source && source.surface ? source.surface.bufferSize : source ? Qt.size(source.width, source.height) : Qt.size(0, 0) // qmllint disable missing-property
                                    readonly property real appAspect: textureSize.width > 0 && textureSize.height > 0 ? textureSize.height / textureSize.width : liveSnapshot.appAspect
                                    readonly property real cardAspect: liveSnapshot.parentAspect

                                    anchors.fill: parent
                                    source: surfaceTree.drawsInSubsurfaces ? surfaceTree : taskCard.nativeSurfaceActive ? taskCard.nativeSurfaceItem : taskCard.taskSwitcherVisible && taskCard.useRegisteredSurface ? taskCard.registeredSurfaceItem : previewContainer.liveApp !== null ? liveSnapshot : null
                                    radius: glass.radius
                                    sourceRect: cardAspect >= appAspect ? Qt.rect((1 - appAspect / cardAspect) / 2, 0, appAspect / cardAspect, 1) : Qt.rect(0, 0, 1, cardAspect / appAspect)
                                }

                                Rectangle {
                                    anchors.fill: parent
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

                                        // On the card's dark glass, whatever the ambience.
                                        Label {
                                            text: taskCard.title || taskCard.appId
                                            color: Theme.lightPrimaryColor
                                            font.pixelSize: Theme.fontSizeSmall
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }

                                        Label {
                                            text: qsTr("Preview unavailable")
                                            color: Theme.lightSecondaryColor
                                            font.pixelSize: Theme.fontSizeExtraSmall
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                MAppIcon {
                    anchors.centerIn: parent
                    size: Theme.iconSizeLarge
                    source: taskCard.icon || "layout-grid"
                    visible: taskCard.secure
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

            // The banner sits on the wallpaper, under the card.
            WallpaperTone {
                id: bannerTone

                objectName: "bannerTone"
                anchors.fill: parent
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
                        objectName: "bannerTitle"
                        text: taskCard.title
                        color: bannerTone.glyph
                        style: Text.Outline
                        styleColor: bannerTone.halo
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
                        //: %1 is the app name
                        Accessible.name: qsTr("Close %1").arg(taskCard.title)

                        HighlightImage {
                            anchors.centerIn: parent
                            width: Theme.iconSizeSmall
                            height: width
                            sourceSize.width: width
                            sourceSize.height: height
                            source: "image://theme/icon-m-close"
                            color: bannerTone.target
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
