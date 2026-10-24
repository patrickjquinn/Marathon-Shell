import MarathonOS.Shell 1.0
import QtQuick

NativeSurfaceItem {
    id: surfaceItem
    property var surfaceObj: null
    property int surfaceId: -1
    property size lastSentSize: Qt.size(0, 0)
    property bool sizeUpdateScheduled: false
    property bool hasSentInitialSize: false
    property bool autoResize: true
    property bool isMinimized: false
    // Preview views must never bufferLock: a fresh second view has no
    // buffer yet, and a locked empty view can never take one — the lock
    // exists to hold the detached foreground item's last frame, not this.
    property bool isPreview: false
    // Typed QObject in C++; the members used here are WaylandCompositor's.
    readonly property var launchCompositor: WaylandCompositorManager.compositor
    // The client's marathon_surface_v1 state, if it has one.
    readonly property var marathonSurface: launchCompositor ? launchCompositor.marathonSurfaces[surfaceId] : undefined
    readonly property bool focusable: !marathonSurface || marathonSurface.focusable
    readonly property bool hasFirstFrame: {
        var s = _surfaceFromObj(surfaceObj);
        return s ? s.hasContent : false;
    }
    // A native client draws in its own pixels, the shell's over nativeScale.
    // The item takes the surface's size in those and is scaled up, so popups,
    // subsurfaces and touch points map 1:1 onto the client's coordinates.
    readonly property real clientScale: !isPreview && launchCompositor && launchCompositor.usesNativeScale(surface) ? launchCompositor.nativeScale : 1
    readonly property size configureSize: parent ? Qt.size(Math.round(parent.width / clientScale), Math.round(parent.height / clientScale)) : Qt.size(0, 0)
    applicationTerms: {
        var toplevel = _toplevelFromObj(surfaceObj);
        if (!toplevel || !toplevel.appId)
            return [];
        var app = AppModel.findById(toplevel.appId);
        return app.searchTerms || [];
    }

    function scheduleSizeUpdate() {
        sizeUpdateScheduled = true;
        later.start();
    }

    // The next turn of the event loop, through a timer that goes with the
    // item: a Qt.callLater could run after the item was destroyed.
    property bool _primaryScheduled: false
    property bool _focusScheduled: false
    property bool _nudgePreviewScheduled: false
    function _later(what) {
        if (what === "primary")
            _primaryScheduled = true;
        else if (what === "focus")
            _focusScheduled = true;
        else
            _nudgePreviewScheduled = true;
        later.start();
    }
    Timer {
        id: later
        interval: 0
        onTriggered: {
            if (surfaceItem.sizeUpdateScheduled) {
                surfaceItem.sizeUpdateScheduled = false;
                surfaceItem.sendSizeToApp();
            }
            if (surfaceItem._primaryScheduled) {
                surfaceItem._primaryScheduled = false;
                surfaceItem._assertPrimary();
            }
            if (surfaceItem._focusScheduled) {
                surfaceItem._focusScheduled = false;
                surfaceItem.takeFocusForKeyboard();
            }
            if (surfaceItem._nudgePreviewScheduled) {
                surfaceItem._nudgePreviewScheduled = false;
                surfaceItem._nudgePreview();
            }
        }
    }

    function _xdgSurfaceFromObj(obj) {
        if (!obj)
            return null;

        if (obj.xdgSurface)
            return obj.xdgSurface;

        return obj;
    }

    function _surfaceFromObj(obj) {
        if (!obj)
            return null;

        if (obj.surface)
            return obj.surface;

        if (obj.xdgSurface && obj.xdgSurface.surface)
            return obj.xdgSurface.surface;

        return null;
    }

    function _toplevelFromObj(obj) {
        if (!obj)
            return null;

        if (obj.toplevel)
            return obj.toplevel;

        var xdg = _xdgSurfaceFromObj(obj);
        if (xdg && xdg.toplevel)
            return xdg.toplevel;

        return null;
    }

    function sendSizeToApp() {
        if (!autoResize) {
            Logger.debug("WaylandShellSurfaceItem", "sendSizeToApp skipped: autoResize is false");
            return;
        }
        var areaWidth = parent ? parent.width : 0;
        var areaHeight = parent ? parent.height : 0;
        if (areaWidth <= 0 || areaHeight <= 0) {
            Logger.debug("WaylandShellSurfaceItem", "sendSizeToApp skipped: invalid size " + areaWidth + "x" + areaHeight);
            return;
        }
        var expectedWidth = (Constants && Constants.screenWidth > 0) ? Constants.screenWidth : areaWidth;
        var minWidth = Math.max(1, expectedWidth * 0.6);
        if (areaWidth < minWidth) {
            Logger.debug("WaylandShellSurfaceItem", "sendSizeToApp skipped: width " + areaWidth + " is below minimum (" + Math.round(minWidth) + "px) - waiting for layout completion");
            return;
        }
        var toplevel = _toplevelFromObj(surfaceObj);
        if (!toplevel) {
            Logger.debug("WaylandShellSurfaceItem", "sendSizeToApp skipped: no toplevel (surfaceObj: " + (surfaceObj ? "exists" : "null") + ")");
            return;
        }
        var xdgSurface = toplevel.xdgSurface;
        if (!xdgSurface) {
            Logger.debug("WaylandShellSurfaceItem", "sendSizeToApp deferred: toplevel.xdgSurface not ready yet");
            scheduleSizeUpdate();
            return;
        }
        if (!xdgSurface.surface) {
            Logger.debug("WaylandShellSurfaceItem", "sendSizeToApp deferred: xdgSurface.surface not ready yet");
            scheduleSizeUpdate();
            return;
        }
        var newSize = configureSize;
        if (hasSentInitialSize && Math.abs(newSize.width - lastSentSize.width) < 2 && Math.abs(newSize.height - lastSentSize.height) < 2) {
            Logger.debug("WaylandShellSurfaceItem", "sendSizeToApp skipped: size unchanged (" + newSize.width + "x" + newSize.height + " vs " + lastSentSize.width + "x" + lastSentSize.height + ")");
            return;
        }
        var firstConfigure = !hasSentInitialSize;
        lastSentSize = newSize;
        hasSentInitialSize = true;
        Logger.info("WaylandShellSurfaceItem", "Configuring app size: " + newSize.width + "x" + newSize.height);
        if (surfaceItem.launchCompositor)
            surfaceItem.launchCompositor.resizeToplevel(toplevel, newSize);
        // Focus a surface when it first maps; after that, keyboard focus
        // follows QML focus. Re-taking it on every resize let a background
        // surface steal focus whenever the keyboard resized the app area,
        // and the keyboard toggling that caused bounced focus between apps
        // hundreds of times a second.
        if (firstConfigure)
            _later("focus");
    }

    // Only a window on screen takes the keyboard, and only once its client has
    // acked the last configure. Nothing signals an ack, and Waydroid's toplevel
    // may not commit again, so the ack is looked for each frame, for a second.
    function takeFocusForKeyboard() {
        focusRetry.stop();
        if (!focusable || isPreview || isMinimized || !hasSentInitialSize || !visible)
            return;
        if (launchCompositor && !launchCompositor.configureSettled(surfaceId) && focusRetry.tries < 60) {
            focusRetry.tries++;
            focusRetry.start();
            return;
        }
        focusRetry.tries = 0;
        forceActiveFocus();
        if (launchCompositor)
            launchCompositor.activateSurface(surfaceId);
    }
    Timer {
        id: focusRetry

        property int tries: 0

        interval: 16
        onTriggered: surfaceItem.takeFocusForKeyboard()
    }

    width: clientScale === 1 ? (parent ? parent.width : 0) : implicitWidth
    height: clientScale === 1 ? (parent ? parent.height : 0) : implicitHeight
    scale: clientScale
    transformOrigin: Item.TopLeft
    // NativeSurfaceItem creates popup children itself because Qt's built-in
    // integration ignores configured popup geometry and loses our input policy.
    autoCreatePopupItems: false
    // Keep the surface item visible from when it's mapped. The compositor now
    // sends an initial xdg_toplevel.configure from C++ (see handleXdgToplevelCreated
    // in waylandcompositor.cpp) so the client can ack and commit its first buffer
    // immediately. The splash overlay below covers the "no buffer yet" gap visually.
    opacity: 1
    bufferLocked: !isPreview && isMinimized && hasFirstFrame
    // Eager buffer release for the live foreground view (MARATHON_DISCARD_FRONT):
    // release the client's buffer once composited instead of holding it to the
    // next commit, so a scrolling double-buffered client isn't starved by
    // etnaviv's implicit fence. Never on preview views or a locked (minimized)
    // view -- those intentionally retain their last frame.
    allowDiscardFrontBuffer: !isPreview && !bufferLocked
                             && surfaceItem.launchCompositor
                             && surfaceItem.launchCompositor.discardFrontBuffer
    shellSurface: {
        var xdg = _xdgSurfaceFromObj(surfaceObj);
        if (xdg && xdg.surface)
            return xdg;

        return null;
    }
    touchEventsEnabled: true
    inputEventsEnabled: !marathonSurface || marathonSurface.touchable
    focusOnClick: focusable
    output: surfaceItem.launchCompositor ? surfaceItem.launchCompositor.output : null
    onShellSurfaceChanged: {
        if (shellSurface) {
            if (autoResize)
                scheduleSizeUpdate();
            _later("primary");
            // A window switched to another surface keeps the keyboard on it:
            // Waydroid moves Android's resumed task to the window with focus.
            if (hasSentInitialSize)
                _later("focus");
        }
    }
    onConfigureSizeChanged: {
        if (autoResize)
            scheduleSizeUpdate();
    }
    // An idle client only commits when its frame callbacks flow, and a
    // view with no current buffer paints nothing — which itself stops the
    // callbacks. nudgeSurface fires the pending callbacks so the client
    // commits: on foreground (re)attach after re-asserting primary, and
    // once at preview attach so an idle client fills the second view.
    function _nudge() {
        if (surfaceId !== -1 && surfaceItem.launchCompositor)
            surfaceItem.launchCompositor.nudgeSurface(surfaceId);
    }
    function _assertPrimary() {
        if (!isMinimized && surface) {
            setPrimary();
            _nudge();
        }
    }
    // The surface id this view is registered under; a switch to another
    // surface takes the old registration away, or a card shows this view
    // for the surface it no longer shows.
    property int registeredSurfaceId: -1
    function _nudgePreview() {
        if (isMinimized) {
            _nudge();
            return;
        }
        if (registeredSurfaceId !== -1 && registeredSurfaceId !== surfaceId && SurfaceRegistry.getSurfaceItem(registeredSurfaceId) === this)
            SurfaceRegistry.unregisterSurface(registeredSurfaceId);
        registeredSurfaceId = surfaceId;
        if (surfaceId !== -1)
            SurfaceRegistry.registerSurface(surfaceId, this);
    }
    onIsMinimizedChanged: {
        if (!isMinimized) {
            _later("primary");
            _later("focus");
        }
    }
    // A restored or switched-to app is shown, not resized, so its surface
    // takes keyboard focus here (focus follows QML focus from then on).
    onVisibleChanged: {
        if (visible)
            _later("focus");
    }
    // A restored / just-thawed idle client won't commit a fresh buffer until a
    // frame callback fires. The single nudge in _assertPrimary can race ahead
    // of the cgroup thaw, leaving the foreground view with no current buffer =
    // black void. Re-nudge briefly until the surface actually has content. The
    // binding stops the instant it paints (hasFirstFrame); a genuinely dead
    // client is still caught by MarathonAppWindow's 20 s launch watchdog.
    Timer {
        id: contentNudge
        interval: 150
        repeat: true
        running: !surfaceItem.isPreview && !surfaceItem.isMinimized && surfaceItem.surfaceId !== -1
                 && surfaceItem.shellSurface && !surfaceItem.hasFirstFrame
        onTriggered: surfaceItem._nudge()
    }
    // Deferred one tick: preview items get isMinimized set just after creation.
    onSurfaceIdChanged: _later("nudgePreview")
    Component.onCompleted: _later("nudgePreview")
    Component.onDestruction: {
        // isPreview, not isMinimized: a backgrounded app is minimized but is
        // still the registered view, and preview views never register.
        if (registeredSurfaceId !== -1 && !isPreview && SurfaceRegistry.getSurfaceItem(registeredSurfaceId) === this)
            SurfaceRegistry.unregisterSurface(registeredSurfaceId);
    }

    // Until the client's first buffer lands, show the app background rather than nothing.
    Rectangle {
        anchors.fill: parent
        color: MColors.background
        visible: !surfaceItem.hasFirstFrame
    }
}
