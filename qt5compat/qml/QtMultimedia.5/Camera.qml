// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Qt 5 Camera (QtMultimedia 5.x) over Qt 6's CaptureSession, Camera and
// ImageCapture. In Qt 5 the Camera is a VideoOutput's `source`; in Qt 6 a
// CaptureSession joins a Camera, an ImageCapture and the VideoOutput. This
// wrapper owns that session and the Qt 5 VideoOutput wrapper hands it its Qt 6
// output (`__videoOutput`).
//
// The Qt 6 objects are created only while a camera device exists
// (MediaDevices.videoInputs is not empty), so on a host or CI machine without
// a camera nothing needs a Qt Multimedia backend: availability is
// Camera.Unavailable, cameraStatus Camera.UnavailableStatus, and the methods
// do nothing (imageCapture.capture() fails with captureFailed).
//
// Kept: the Qt 5 enums and numbering; cameraState (the requested state, as in
// Qt 5; start() and stop() set it, and leave an app binding alone when the
// state does not change), cameraStatus, captureMode (accepted; the Qt 6
// session always has the image capture), availability, deviceId, position,
// displayName, orientation (Qt 6.7+ correctionAngle, else 0), lockStatus with
// searchAndLock() and unlock() (Qt 6 has no focus lock: the lock is reported
// as soon as the camera is active), digitalZoom and maximumDigitalZoom (Qt 6
// zoomFactor), errorCode, errorString and the error() signal, flash,
// exposure, focus, imageProcessing, imageCapture, viewfinder, videoRecorder
// (no recording), supportedViewfinderResolutions() and
// supportedViewfinderFrameRateRanges(), metaData (accepted, not passed to
// Qt 6). Not kept: mediaObject, opticalZoom (fixed at 1).
import QtQml 2.15
import QtMultimedia 6.0 as QM
import "CameraUtils.js" as Utils

QtObject {
    id: shim

    enum State { UnloadedState, LoadedState, ActiveState }
    enum Status {
        UnavailableStatus, UnloadedStatus, LoadingStatus, UnloadingStatus, LoadedStatus,
        StandbyStatus, StartingStatus, StoppingStatus, ActiveStatus
    }
    enum CaptureMode { CaptureViewfinder, CaptureStillImage, CaptureVideo }
    enum Error { NoError, CameraError, InvalidRequestError, ServiceMissingError, NotSupportedFeatureError }
    enum LockStatus { Unlocked, Searching, Locked }
    enum Position { UnspecifiedPosition, BackFace, FrontFace }
    enum Availability { Available = 0, Unavailable = 1, Busy = 2, ResourceMissing = 3 }
    enum FlashMode {
        FlashAuto = 1, FlashOff = 2, FlashOn = 4, FlashRedEyeReduction = 8, FlashFill = 16,
        FlashTorch = 32, FlashVideoLight = 64, FlashSlowSyncFrontCurtain = 128,
        FlashSlowSyncRearCurtain = 256, FlashManual = 512
    }
    enum ExposureMode {
        ExposureAuto, ExposureManual, ExposurePortrait, ExposureNight, ExposureBacklight,
        ExposureSpotlight, ExposureSports, ExposureSnow, ExposureBeach, ExposureLargeAperture,
        ExposureSmallAperture, ExposureAction, ExposureLandscape, ExposureNightPortrait,
        ExposureTheatre, ExposureSunset, ExposureSteadyPhoto, ExposureFireworks, ExposureParty,
        ExposureCandlelight, ExposureBarcode, ExposureModeVendor = 1000
    }
    enum MeteringMode { MeteringMatrix = 1, MeteringAverage = 2, MeteringSpot = 3 }
    enum FocusMode {
        FocusManual = 1, FocusHyperfocal = 2, FocusInfinity = 4, FocusAuto = 8,
        FocusContinuous = 16, FocusMacro = 32
    }
    enum FocusPointMode { FocusPointAuto, FocusPointCenter, FocusPointFaceDetection, FocusPointCustom }
    enum FocusAreaStatus { FocusAreaUnused = 1, FocusAreaSelected = 2, FocusAreaFocused = 3 }

    // Numbers rather than Camera.X below: inside this module the name Camera
    // is this file, and the values are the enums above.
    property int cameraState: 2 // ActiveState
    readonly property int cameraStatus: {
        if (!__backend)
            return 0 // UnavailableStatus
        if (__backend.qcam.error !== QM.Camera.NoError)
            return 0
        if (__backend.qcam.active)
            return 8 // ActiveStatus
        switch (cameraState) {
        case 2: return 6 // StartingStatus
        case 1: return 4 // LoadedStatus
        default: return 1 // UnloadedStatus
        }
    }
    property int captureMode: 1 // CaptureStillImage
    property string deviceId: ""
    property int position: 0 // UnspecifiedPosition
    readonly property string displayName: __device ? __device.description : ""
    readonly property int orientation: Utils.orientation(__device)
    readonly property int availability: __device ? 0 : 1
    readonly property int lockStatus: __lockStatus
    readonly property int errorCode: __errorCode
    readonly property string errorString: __errorString
    property real digitalZoom: 1.0
    readonly property real maximumDigitalZoom: __backend ? __backend.qcam.maximumZoomFactor : 1.0
    property real opticalZoom: 1.0
    readonly property real maximumOpticalZoom: 1.0

    readonly property CameraFlash flash: CameraFlash { }
    readonly property CameraExposure exposure: CameraExposure { __camera: shim }
    readonly property CameraFocus focus: CameraFocus { }
    readonly property CameraImageProcessing imageProcessing: CameraImageProcessing { }
    readonly property CameraCapture imageCapture: CameraCapture { __camera: shim }
    readonly property CameraViewfinder viewfinder: CameraViewfinder { }
    readonly property CameraRecorder videoRecorder: CameraRecorder { }
    readonly property CameraMetaData metaData: CameraMetaData { }

    signal error(int errorCode, string errorString)

    function start() {
        if (cameraState !== 2)
            cameraState = 2
    }
    function stop() {
        if (cameraState !== 1)
            cameraState = 1
    }
    function searchAndLock() {
        __lockStatus = cameraStatus === 8 ? 2 : 0 // Locked : Unlocked
    }
    function unlock() {
        __lockStatus = 0
    }
    function supportedViewfinderResolutions(minimumFrameRate, maximumFrameRate) {
        var out = []
        var seen = {}
        var formats = __device ? __device.videoFormats : []
        for (var i = 0; i < formats.length; ++i) {
            var f = formats[i]
            if (minimumFrameRate && f.maxFrameRate < minimumFrameRate)
                continue
            if (maximumFrameRate && f.minFrameRate > maximumFrameRate)
                continue
            var key = f.resolution.width + "x" + f.resolution.height
            if (!seen[key]) {
                seen[key] = true
                out.push(Qt.size(f.resolution.width, f.resolution.height))
            }
        }
        return out
    }
    function supportedViewfinderFrameRateRanges(resolution) {
        var out = []
        var formats = __device ? __device.videoFormats : []
        for (var i = 0; i < formats.length; ++i) {
            var f = formats[i]
            if (resolution && (f.resolution.width !== resolution.width
                               || f.resolution.height !== resolution.height))
                continue
            out.push({ minimumFrameRate: f.minFrameRate, maximumFrameRate: f.maxFrameRate })
        }
        return out
    }

    // Internal.
    property QtObject __videoOutput: null // the Qt 6 VideoOutput, set by the VideoOutput wrapper
    property int __lockStatus: 0
    property int __errorCode: 0
    property string __errorString: ""
    readonly property QM.MediaDevices __devices: QM.MediaDevices { }
    readonly property var __device: Utils.pick(__devices, deviceId, position)
    readonly property bool __hasDevice: __device !== null
    property var __backend: null // a CameraBackend (the Qt 6 objects) while a device exists

    function __flashMode(mode) {
        switch (mode) {
        case 1: return QM.Camera.FlashAuto
        case 2: case 32: case 64: return QM.Camera.FlashOff
        default: return QM.Camera.FlashOn
        }
    }
    function __torchMode(mode) {
        return mode === 32 || mode === 64 ? QM.Camera.TorchOn : QM.Camera.TorchOff
    }
    function __focusMode(mode) {
        switch (mode) {
        case 1: return QM.Camera.FocusModeManual
        case 2: return QM.Camera.FocusModeHyperfocal
        case 4: return QM.Camera.FocusModeInfinity
        case 32: return QM.Camera.FocusModeAutoNear
        default: return QM.Camera.FocusModeAuto
        }
    }
    function __exposureMode(mode) {
        switch (mode) {
        case 1: return QM.Camera.ExposureManual
        case 2: return QM.Camera.ExposurePortrait
        case 3: return QM.Camera.ExposureNight
        case 6: return QM.Camera.ExposureSports
        case 7: return QM.Camera.ExposureSnow
        case 8: return QM.Camera.ExposureBeach
        case 11: return QM.Camera.ExposureAction
        case 12: return QM.Camera.ExposureLandscape
        case 13: return QM.Camera.ExposureNightPortrait
        case 14: return QM.Camera.ExposureTheatre
        case 15: return QM.Camera.ExposureSunset
        case 16: return QM.Camera.ExposureSteadyPhoto
        case 17: return QM.Camera.ExposureFireworks
        case 18: return QM.Camera.ExposureParty
        case 19: return QM.Camera.ExposureCandlelight
        case 20: return QM.Camera.ExposureBarcode
        default: return QM.Camera.ExposureAuto
        }
    }
    function __whiteBalanceMode(mode) {
        // Qt 5 and Qt 6 number Auto .. Sunset alike; Qt 6 has no vendor modes.
        return mode >= 0 && mode <= 8 ? mode : QM.Camera.WhiteBalanceAuto
    }
    function __focusPoint() {
        switch (focus.focusPointMode) {
        case 1: return Qt.point(0.5, 0.5)
        case 3: return focus.customFocusPoint
        default: return null
        }
    }
    // The device format for viewfinder.resolution with the highest frame rate
    // within the requested bounds, or null.
    function __format() {
        var res = viewfinder.resolution
        if (!__device || res.width <= 0 || res.height <= 0)
            return null
        var best = null
        var formats = __device.videoFormats
        for (var i = 0; i < formats.length; ++i) {
            var f = formats[i]
            if (f.resolution.width !== res.width || f.resolution.height !== res.height)
                continue
            if (viewfinder.minimumFrameRate > 0 && f.maxFrameRate < viewfinder.minimumFrameRate)
                continue
            if (viewfinder.maximumFrameRate > 0 && f.minFrameRate > viewfinder.maximumFrameRate)
                continue
            if (!best || f.maxFrameRate > best.maxFrameRate)
                best = f
        }
        return best
    }
    function __updateBackend() {
        if (__hasDevice && !__backend) {
            __backend = __backendComponent.createObject(shim, { wrapper: shim })
        } else if (!__hasDevice && __backend) {
            __backend.destroy()
            __backend = null
            __lockStatus = 0
        }
    }

    readonly property Component __backendComponent: Component {
        CameraBackend { }
    }

    on__HasDeviceChanged: __updateBackend()
    Component.onCompleted: __updateBackend()
}
