// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Sailfish.Gallery ImageViewer, clean-room from the type's use in apps: one
// photo fitted to the viewer, pinch or double-tap to zoom, drag to pan
// while zoomed.
//   source      the image
//   active      whether the viewer is the one shown (zooming is enabled and
//               the busy indicator runs only then)
//   viewMoving  set by the containing view while it is being swiped (no
//               panning then)
//   zoomed      read only: zoomed in
//   error       read only: the image could not be loaded
//   clicked()   a tap (apps toggle their overlay)
//   zoomOut()   back to the fitted size, animated
import QtQuick 2.6
import QtQuick.Window 2.2 as QtWindow
import Sailfish.Silica 1.0

SilicaFlickable {
    id: viewer

    property url source
    property bool active: true
    property bool viewMoving
    readonly property bool zoomed: image.scale > 1.01
    readonly property bool error: image.status === Image.Error
    readonly property alias status: image.status

    signal clicked

    function zoomOut() {
        zoomAnimation.to = 1.0
        zoomAnimation.restart()
    }

    function _zoomTo(scale, x, y) {
        var s = Math.max(1.0, Math.min(scale, _maximumScale))
        image.scale = s
        contentWidth = Math.max(width, image.paintedWidth * s)
        contentHeight = Math.max(height, image.paintedHeight * s)
        contentX = Math.max(0, Math.min(contentWidth - width, x * s - width / 2))
        contentY = Math.max(0, Math.min(contentHeight - height, y * s - height / 2))
    }

    readonly property real _maximumScale: image.paintedWidth > 0
                                          ? Math.max(3.0, image.sourceSize.width / image.paintedWidth)
                                          : 3.0
    readonly property real _screenSide: Math.max(QtWindow.Screen.width, QtWindow.Screen.height)

    contentWidth: width
    contentHeight: height
    interactive: zoomed && !viewMoving
    clip: true

    Image {
        id: image

        width: viewer.width
        height: viewer.height
        x: (viewer.contentWidth - width) / 2
        y: (viewer.contentHeight - height) / 2
        transformOrigin: Item.Center
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        autoTransform: true
        cache: false
        smooth: !viewer.moving
        source: viewer.source
        sourceSize.width: viewer._screenSide * (viewer.zoomed ? 2 : 1)
        sourceSize.height: viewer._screenSide * (viewer.zoomed ? 2 : 1)
    }

    NumberAnimation {
        id: zoomAnimation

        target: image
        property: "scale"
        duration: 200
        easing.type: Easing.InOutQuad
        onStopped: viewer._zoomTo(image.scale, viewer.width / 2, viewer.height / 2)
    }

    PinchArea {
        anchors.fill: parent
        enabled: viewer.active && image.status === Image.Ready
        onPinchUpdated: function(pinch) {
            viewer._zoomTo(image.scale * pinch.scale / pinch.previousScale,
                           viewer.contentX + pinch.center.x, viewer.contentY + pinch.center.y)
        }

        MouseArea {
            anchors.fill: parent
            onClicked: viewer.clicked()
            onDoubleClicked: function(mouse) {
                if (viewer.zoomed)
                    viewer.zoomOut()
                else
                    viewer._zoomTo(2.5, viewer.contentX + mouse.x, viewer.contentY + mouse.y)
            }
        }
    }

    BusyIndicator {
        anchors.centerIn: parent
        running: image.status === Image.Loading && viewer.active
        size: BusyIndicatorSize.Large
    }
}
