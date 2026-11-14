// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Coordinate mapping for the Qt 5 VideoOutput wrapper's map*() functions:
// between item coordinates in `content` (the displayed video's rectangle) and
// normalized source coordinates (0..1), with the source rotated
// counter-clockwise by `orientation` degrees (0, 90, 180 or 270), as in Qt 5.
.pragma library

function normalizeOrientation(orientation) {
    return ((orientation % 360) + 360) % 360
}

function normalizedToItem(point, content, orientation) {
    var u = point.x
    var v = point.y
    switch (normalizeOrientation(orientation)) {
    case 90: u = point.y; v = 1 - point.x; break
    case 180: u = 1 - point.x; v = 1 - point.y; break
    case 270: u = 1 - point.y; v = point.x; break
    }
    return Qt.point(content.x + u * content.width, content.y + v * content.height)
}

function itemToNormalized(point, content, orientation) {
    if (content.width <= 0 || content.height <= 0)
        return Qt.point(0, 0)
    var u = (point.x - content.x) / content.width
    var v = (point.y - content.y) / content.height
    switch (normalizeOrientation(orientation)) {
    case 90: return Qt.point(1 - v, u)
    case 180: return Qt.point(1 - u, 1 - v)
    case 270: return Qt.point(v, 1 - u)
    default: return Qt.point(u, v)
    }
}

// Maps both corners of `rect` with `map` and returns their bounding rectangle.
function mapRect(rect, map) {
    var a = map(Qt.point(rect.x, rect.y))
    var b = map(Qt.point(rect.x + rect.width, rect.y + rect.height))
    return Qt.rect(Math.min(a.x, b.x), Math.min(a.y, b.y), Math.abs(b.x - a.x), Math.abs(b.y - a.y))
}
