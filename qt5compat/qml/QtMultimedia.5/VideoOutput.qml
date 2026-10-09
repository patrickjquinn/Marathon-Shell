// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Qt 5 VideoOutput (QtMultimedia 5.x) over Qt 6's VideoOutput. Qt 5 points the
// output at its source (`source: player`, `source: camera`); Qt 6 points the
// player or capture session at the output (`videoOutput`), so setting `source`
// attaches the Qt 6 output to the wrapped player, to the Camera wrapper's
// capture session, or to any Qt 6 object with a `videoOutput` property.
//
// The Qt 6 VideoOutput is created only while there is something to show (a
// player, or a Camera wrapper with a camera device): Qt 6.4 aborts when a
// VideoOutput is created without a Qt Multimedia backend, and a page with a
// camera viewfinder must still load on a machine without a camera.
//
// Kept: source, fillMode, orientation, sourceRect, contentRect, the map*()
// functions (Qt 6 dropped them; computed here from contentRect, sourceRect and
// orientation). Accepted and ignored: autoOrientation, flushMode, and
// `filters` (Qt 5 video filters are C++ QAbstractVideoFilter objects, which
// Qt 6 does not have; a non-empty list warns once).
import QtQuick 2.15
import QtMultimedia 6.0 as QM
import "VideoGeometry.js" as Geometry

Item {
    id: output

    enum FillMode { Stretch, PreserveAspectFit, PreserveAspectCrop }
    enum FlushMode { EmptyFrame, FirstFrame, LastFrame }

    property var source: null
    // Qt 6's FillMode has the same names and values as the enum above.
    property int fillMode: QM.VideoOutput.PreserveAspectFit
    property int orientation: 0
    property bool autoOrientation: false
    property int flushMode: 0
    property list<QtObject> filters
    readonly property rect sourceRect: __output ? __output.sourceRect : Qt.rect(0, 0, 0, 0)
    readonly property rect contentRect: __output ? __output.contentRect : Qt.rect(0, 0, 0, 0)

    // Normalized source coordinates (0..1) to and from item coordinates
    // (VideoGeometry.js).
    function mapNormalizedPointToItem(point) {
        return Geometry.normalizedToItem(point, contentRect, orientation)
    }
    function mapNormalizedRectToItem(rect) {
        return Geometry.mapRect(rect, mapNormalizedPointToItem)
    }
    function mapPointToItem(point) {
        var s = sourceRect
        if (s.width <= 0 || s.height <= 0)
            return Qt.point(0, 0)
        return mapNormalizedPointToItem(Qt.point((point.x - s.x) / s.width, (point.y - s.y) / s.height))
    }
    function mapRectToItem(rect) {
        return Geometry.mapRect(rect, mapPointToItem)
    }
    function mapPointToSourceNormalized(point) {
        return Geometry.itemToNormalized(point, contentRect, orientation)
    }
    function mapRectToSourceNormalized(rect) {
        return Geometry.mapRect(rect, mapPointToSourceNormalized)
    }
    function mapPointToSource(point) {
        var s = sourceRect
        var n = mapPointToSourceNormalized(point)
        return Qt.point(s.x + n.x * s.width, s.y + n.y * s.height)
    }
    function mapRectToSource(rect) {
        return Geometry.mapRect(rect, mapPointToSource)
    }

    // Internal. __output is the Qt 6 VideoOutput while one exists.
    readonly property var __output: loader.item
    property var __attached: null
    property var __attachedOutput: null
    property bool __filtersWarned: false

    // How to attach to `src`: "player" (MediaPlayer wrapper), "camera" (Camera
    // wrapper), "qt6" (an object with videoOutput), or "".
    function __kind(src) {
        if (!src)
            return ""
        if (src.__player !== undefined)
            return "player"
        if (src.__videoOutput !== undefined)
            return "camera"
        if (src.videoOutput !== undefined)
            return "qt6"
        return ""
    }
    function __set(src, value) {
        switch (__kind(src)) {
        case "player": src.__player.videoOutput = value; break
        case "camera": src.__videoOutput = value; break
        case "qt6": src.videoOutput = value; break
        }
    }
    function __get(src) {
        switch (__kind(src)) {
        case "player": return src.__player.videoOutput
        case "camera": return src.__videoOutput
        case "qt6": return src.videoOutput
        default: return null
        }
    }
    // Reads loader.item, not __output: this runs from loader.onItemChanged,
    // possibly before the __output binding has been updated.
    function __reattach() {
        __detach()
        var out = loader.item
        if (out && __kind(source) !== "") {
            __attached = source
            __attachedOutput = out
            __set(source, out)
        }
    }
    // Detaches only if the source still shows our output (an app may have
    // pointed it elsewhere since).
    function __detach() {
        if (__attached && __attachedOutput && __get(__attached) === __attachedOutput)
            __set(__attached, null)
        __attached = null
        __attachedOutput = null
    }

    readonly property bool __wantsOutput: {
        var kind = __kind(source)
        return kind === "player" || kind === "qt6" || (kind === "camera" && source.__hasDevice)
    }

    // A child of this item, so it is created before (and stays below) the
    // children an app declares in its VideoOutput.
    Loader {
        id: loader
        anchors.fill: parent
        active: output.__wantsOutput
        sourceComponent: Component {
            QM.VideoOutput { }
        }
        onItemChanged: output.__reattach()
    }
    Binding {
        target: loader.item
        property: "fillMode"
        value: output.fillMode
        when: loader.item !== null
    }
    Binding {
        target: loader.item
        property: "orientation"
        value: output.orientation
        when: loader.item !== null
    }

    onSourceChanged: {
        if (source && __kind(source) === "")
            console.warn("VideoOutput: unsupported source", source)
        __reattach()
    }
    onFiltersChanged: {
        if (filters.length > 0 && !__filtersWarned) {
            __filtersWarned = true
            console.warn("QtMultimedia 5 shim: VideoOutput.filters is not supported on Keel; ignored")
        }
    }
    Component.onDestruction: __detach()
}
