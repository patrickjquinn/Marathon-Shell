import QtQuick

// QWaylandQuickShellSurfaceItem's members that WaylandShellSurfaceItem sets.
Item {
    property var applicationTerms: []
    property var surface: null
    property var shellSurface: null
    property var output: null
    property bool autoCreatePopupItems: false
    property bool bufferLocked: false
    property bool allowDiscardFrontBuffer: false
    property bool touchEventsEnabled: true
    property bool inputEventsEnabled: true
    property bool focusOnClick: false

    signal surfaceDestroyed

    function takeFocus() {
    }
}
