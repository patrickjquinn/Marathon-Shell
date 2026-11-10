// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Qt 5 Camera.viewfinder (QtMultimedia 5.x). The Camera wrapper turns
// `resolution` (and the frame rate bounds) into one of the device's Qt 6
// camera formats; Qt.size(-1, -1) or an unsupported size leaves the backend's
// choice.
import QtQml 2.15

QtObject {
    property size resolution: Qt.size(-1, -1)
    property real minimumFrameRate: 0
    property real maximumFrameRate: 0
}
