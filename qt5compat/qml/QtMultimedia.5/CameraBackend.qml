// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// The Qt 6 side of the Qt 5 Camera wrapper (Camera.qml): a CaptureSession
// with a Camera and an ImageCapture, set from the wrapper's Qt 5 properties.
// Camera.qml creates it only while a camera device exists. Internal to this
// module.
import QtQml 2.15
import QtMultimedia 6.0 as QM

QtObject {
    id: backend

    required property var wrapper // the Camera wrapper

    readonly property QM.Camera qcam: QM.Camera {
        // A null device value, not null, while the device goes away.
        cameraDevice: backend.wrapper.__device ? backend.wrapper.__device : backend.wrapper.__devices.defaultVideoInput
        active: backend.wrapper.cameraState === 2
        flashMode: backend.wrapper.__flashMode(backend.wrapper.flash.mode)
        torchMode: backend.wrapper.__torchMode(backend.wrapper.flash.mode)
        focusMode: backend.wrapper.__focusMode(backend.wrapper.focus.focusMode)
        exposureMode: backend.wrapper.__exposureMode(backend.wrapper.exposure.exposureMode)
        exposureCompensation: backend.wrapper.exposure.exposureCompensation
        whiteBalanceMode: backend.wrapper.__whiteBalanceMode(backend.wrapper.imageProcessing.whiteBalanceMode)
        zoomFactor: Math.max(minimumZoomFactor, Math.min(backend.wrapper.digitalZoom, maximumZoomFactor))

        onActiveChanged: if (!active) backend.wrapper.__lockStatus = 0
        onErrorOccurred: function (error, errorString) {
            backend.wrapper.__errorCode = 1 // CameraError
            backend.wrapper.__errorString = errorString
            backend.wrapper.error(1, errorString)
        }
    }
    readonly property QM.ImageCapture imageCapture: QM.ImageCapture {
        onImageCaptured: function (requestId, previewImage) {
            // Qt 6 sets `preview` (an image URL) before this handler runs.
            backend.wrapper.imageCapture.imageCaptured(requestId, backend.imageCapture.preview)
        }
        onImageSaved: function (requestId, path) {
            backend.wrapper.imageCapture.capturedImagePath = path
            backend.wrapper.imageCapture.imageSaved(requestId, path)
        }
        onErrorOccurred: function (requestId, error, message) {
            backend.wrapper.imageCapture.errorString = message
            backend.wrapper.imageCapture.captureFailed(requestId, message)
        }
    }
    readonly property QM.CaptureSession session: QM.CaptureSession {
        camera: backend.qcam
        imageCapture: backend.imageCapture
        videoOutput: backend.wrapper.__videoOutput
    }

    // Qt 6 applies these only when set, so they are set imperatively.
    function applyFormat() {
        var f = backend.wrapper.__format()
        if (f)
            backend.qcam.cameraFormat = f
    }
    function applyFocusPoint() {
        var p = backend.wrapper.__focusPoint()
        if (p)
            backend.qcam.customFocusPoint = p
    }
    function applyManualExposure() {
        if (backend.wrapper.exposure.manualIso > 0)
            backend.qcam.manualIsoSensitivity = backend.wrapper.exposure.manualIso
        if (backend.wrapper.exposure.manualShutterSpeed > 0)
            backend.qcam.manualExposureTime = backend.wrapper.exposure.manualShutterSpeed
        if (backend.wrapper.imageProcessing.manualWhiteBalance > 0)
            backend.qcam.colorTemperature = backend.wrapper.imageProcessing.manualWhiteBalance
    }

    readonly property Connections viewfinderChanges: Connections {
        target: backend.wrapper.viewfinder
        function onResolutionChanged() { backend.applyFormat() }
        function onMinimumFrameRateChanged() { backend.applyFormat() }
        function onMaximumFrameRateChanged() { backend.applyFormat() }
    }
    readonly property Connections focusChanges: Connections {
        target: backend.wrapper.focus
        function onFocusPointModeChanged() { backend.applyFocusPoint() }
        function onCustomFocusPointChanged() { backend.applyFocusPoint() }
    }
    readonly property Connections exposureChanges: Connections {
        target: backend.wrapper.exposure
        function onManualIsoChanged() { backend.applyManualExposure() }
        function onManualShutterSpeedChanged() { backend.applyManualExposure() }
    }
    readonly property Connections whiteBalanceChanges: Connections {
        target: backend.wrapper.imageProcessing
        function onManualWhiteBalanceChanged() { backend.applyManualExposure() }
    }
    readonly property Connections deviceChanges: Connections {
        target: backend.wrapper
        function on__DeviceChanged() { backend.applyFormat() }
    }

    Component.onCompleted: {
        applyFormat()
        applyFocusPoint()
        applyManualExposure()
    }
}
