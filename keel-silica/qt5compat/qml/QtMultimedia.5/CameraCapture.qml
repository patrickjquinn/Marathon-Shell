// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Qt 5 Camera.imageCapture (QtMultimedia 5.x) over the Camera wrapper's Qt 6
// ImageCapture. capture() saves to the default location as in Qt 5 (Qt 6's
// captureToFile("")); imageCaptured gives the preview URL, imageSaved the
// file path. Without a camera, capture() returns -1 and emits captureFailed.
// Not kept: imageMetadataAvailable is never emitted, resolution and
// setMetadata() are accepted and ignored.
import QtQml 2.15

QtObject {
    id: capture

    readonly property bool ready: __camera !== null && __camera.__backend !== null
                                  && __camera.__backend.imageCapture.readyForCapture
    property string capturedImagePath: ""
    property size resolution: Qt.size(-1, -1)
    property string errorString: ""
    readonly property var supportedResolutions: __camera && __camera.__device
                                                ? __camera.__device.photoResolutions : []

    signal imageCaptured(int requestId, string preview)
    signal imageMetadataAvailable(int requestId, string key, var value)
    signal imageSaved(int requestId, string path)
    signal captureFailed(int requestId, string message)

    property var __camera: null // the Camera wrapper

    function captureToLocation(location) {
        var backend = __camera ? __camera.__backend : null
        if (!backend || !backend.imageCapture.readyForCapture) {
            errorString = "Camera is not ready"
            captureFailed(-1, errorString)
            return -1
        }
        return backend.imageCapture.captureToFile(location ? String(location) : "")
    }
    function capture() {
        return captureToLocation("")
    }
    function cancelCapture() {
    }
    function setMetadata(key, value) {
    }
}
