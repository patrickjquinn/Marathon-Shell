// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

import QtQuick
import MarathonOS.Services 1.0

// What the Jolla Camera's native settings object gave Settings: where captures
// go, through Marathon's Captures (~/Pictures/Marathon). There is no memory
// card choice, so the storage path's status stays NotSet (0).
QtObject {
    readonly property Captures captures: Captures {}
    readonly property int storagePathStatus: 0
    readonly property url captureFolder: {
        const path = captures.nextPath("photo");
        return "file://" + path.substring(0, path.lastIndexOf("/"));
    }
    // A video stops before it outgrows this.
    readonly property real storageMaxFileSize: 4 * 1024 * 1024 * 1024

    function refreshMaxFileSize() {
    }

    function photoCapturePath(extension) {
        return captures.nextPath("photo");
    }

    function videoCapturePath(extension) {
        return captures.nextPath("video");
    }

    function completePhoto(url) {
        captures.add(url.toString());
    }

    function completeCapture(url) {
        captures.add(url.toString());
        return url;
    }
}
