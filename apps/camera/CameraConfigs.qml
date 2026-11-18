// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

pragma Singleton

import QtQuick
import MarathonApp.Camera

// What the current camera offers, as the Jolla Camera's CameraConfigs reports
// it. An empty list hides that control.
QtObject {
    enum AspectRatio {
        AspectRatio_4_3,
        AspectRatio_16_9,
        // A square cut from the middle of the 4:3 frame.
        AspectRatio_1_1
    }

    // Set by CaptureView.
    property Camera camera

    readonly property CameraController _controller: camera ? camera.controller : null
    readonly property bool ready: !!camera && camera.configured
    // The software ISP debayers each frame the viewfinder (or a video) gets:
    // nothing over 1080 lines, or a 12 MP sensor's full frame is offered.
    readonly property var supportedViewfinderResolutions: ready ? _controller.previewResolutions.filter(s => s.height <= 1080) : []
    // A photo is one debayered frame: none over 3072 lines (a 50 MP one).
    readonly property var supportedImageResolutions: ready ? _controller.photoResolutions.filter(s => s.height <= 3072) : []
    readonly property var supportedHighresImageResolutions: []
    readonly property var supportedVideoResolutions: supportedViewfinderResolutions
    readonly property var supportedFlashModes: {
        if (!ready || !_controller.flashAvailable)
            return [];
        return camera.captureMode === Camera.CaptureVideo ? [Camera.FlashOff, Camera.FlashTorch] : [Camera.FlashOff, Camera.FlashOn];
    }
    // No focus control reaches libcamera's cameras through Qt Multimedia.
    // A camera with a focus motor focuses continuously, and on a tap.
    readonly property var supportedFocusModes: ready && _controller.focusSupported ? [Camera.FocusAuto, Camera.FocusContinuous] : [Camera.FocusInfinity]
    readonly property var supportedExposureModes: [Camera.ExposureManual]
    readonly property var supportedIsoSensitivities: []
    readonly property var supportedWhiteBalanceModes: []
    readonly property var supportedColorFilters: []
    readonly property bool supportsRaw: false
    // Qt Multimedia offers it, but the software ISP ignores ExposureValue.
    readonly property bool supportsExposureCompensation: false
}
