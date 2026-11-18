// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

import QtQuick
import Marathon.Platform 1.0 as Platform
import MarathonApp.Camera

// The part of Qt 5 Multimedia's Camera that the Jolla Camera's QML is written
// against, over CameraController. A control the controller lacks keeps its
// value and does nothing; CameraConfigs reports it unsupported, so the UI
// leaves it out.
QtObject {
    id: root

    enum CaptureMode {
        CaptureViewfinder,
        CaptureStillImage,
        CaptureVideo
    }
    // QCameraDevice::Position's values.
    enum Position {
        UnspecifiedPosition,
        BackFace,
        FrontFace
    }
    enum CameraState {
        UnloadedState,
        LoadedState,
        ActiveState
    }
    enum CameraStatus {
        UnavailableStatus,
        UnloadedStatus,
        LoadingStatus,
        LoadedStatus,
        StartingStatus,
        ActiveStatus
    }
    enum ErrorCode {
        NoError,
        CameraError
    }
    enum LockStatus {
        Unlocked,
        Searching,
        Locked
    }
    enum FlashMode {
        FlashAuto,
        FlashOff,
        FlashOn,
        FlashRedEyeReduction,
        FlashTorch
    }
    enum FocusMode {
        FocusManual,
        FocusHyperfocal,
        FocusInfinity,
        FocusAuto,
        FocusContinuous
    }
    enum FocusPointMode {
        FocusPointAuto,
        FocusPointCustom
    }
    enum FocusAreaStatus {
        FocusAreaUnused,
        FocusAreaSelected,
        FocusAreaFocused
    }
    // ExposureManual is the Jolla Camera's automatic mode.
    enum ExposureMode {
        ExposureManual,
        ExposurePortrait,
        ExposureNight,
        ExposureSports,
        ExposureHDR
    }
    enum MeteringMode {
        MeteringMatrix,
        MeteringAverage,
        MeteringSpot
    }

    component ImageCaptureControl: QtObject {
        required property CameraController controller
        // Clockwise degrees that stand the photo upright.
        property int orientation
        property size resolution
        readonly property bool ready: controller.active && !_pending
        property bool _pending

        signal imageExposed(int requestId)
        signal imageSaved(int requestId, string path)
        signal captureFailed(int requestId, string message)

        function captureToLocation(path) {
            _pending = true;
            controller.capturePhoto(path, orientation);
        }

        onResolutionChanged: controller.photoResolution = resolution.width > 0 ? resolution : Qt.size(-1, -1)
    }

    component FocusControl: QtObject {
        required property CameraController controller
        property int focusMode: Camera.FocusAuto
        property int focusPointMode: Camera.FocusPointAuto
        property point customFocusPoint: Qt.point(0.5, 0.5)
        // The ring where the person tapped: white while it focuses, then lit.
        readonly property var focusZones: focusPointMode === Camera.FocusPointCustom && controller.focusState !== CameraController.FocusUnlocked ? [
            {
                area: Qt.rect(customFocusPoint.x - 0.1, customFocusPoint.y - 0.1, 0.2, 0.2),
                status: controller.focusState === CameraController.FocusLocked ? Camera.FocusAreaFocused : Camera.FocusAreaSelected
            }
        ] : []
    }

    component FlashControl: QtObject {
        required property CameraController controller
        property int mode: Camera.FlashOff

        onModeChanged: controller.flashEnabled = mode === Camera.FlashOn || mode === Camera.FlashTorch
    }

    component ExposureControl: QtObject {
        property int exposureMode: Camera.ExposureManual
        property real exposureCompensation
        property int meteringMode: Camera.MeteringMatrix
    }

    component ViewfinderControl: QtObject {
        required property CameraController controller
        property size resolution

        onResolutionChanged: controller.viewfinderResolution = resolution.width > 0 ? resolution : Qt.size(-1, -1)
    }

    component MetaData: QtObject {
        property var date
        property var gpsLatitude
        property var gpsLongitude
        property var gpsAltitude
        property int orientation
    }

    property string deviceId
    property int captureMode: Camera.CaptureStillImage
    property int cameraState: Camera.UnloadedState
    readonly property int cameraStatus: {
        if (controller.active)
            return Camera.ActiveStatus;
        switch (cameraState) {
        case Camera.ActiveState:
            return Camera.StartingStatus;
        case Camera.LoadedState:
            return controller.discovered ? Camera.LoadedStatus : Camera.LoadingStatus;
        default:
            return Camera.UnloadedStatus;
        }
    }
    property int errorCode: Camera.NoError
    // The cameras are known and the UI has seen LoadedStatus (it reads the
    // list then); CameraConfigs is ready from here.
    property bool configured
    readonly property int lockStatus: {
        switch (controller.focusState) {
        case CameraController.FocusSearching:
            return Camera.Searching;
        case CameraController.FocusLocked:
            return Camera.Locked;
        default:
            return Camera.Unlocked;
        }
    }
    readonly property var _device: availableCameras.find(c => c.deviceId === controller.cameraId)
    readonly property int position: _device ? _device.position : Camera.UnspecifiedPosition
    // How far the sensor's frames turn clockwise to stand upright. A front
    // camera's rotation is Android's orientation, seen from the scene: the
    // mirrored viewfinder and the picture turn the other way.
    readonly property int orientation: _device ? (position === Camera.FrontFace ? (360 - _device.rotation) % 360 : _device.rotation) : 0
    property real digitalZoom: 1.0
    readonly property real maximumDigitalZoom: controller.maxZoom
    readonly property var availableCameras: controller.cameras.map(c => ({
                deviceId: c.id,
                displayName: c.description,
                position: c.position,
                rotation: c.rotation
            }))
    readonly property string defaultCameraId: controller.defaultCameraId

    readonly property ImageCaptureControl imageCapture: ImageCaptureControl {
        controller: root.controller
        orientation: root.metaData.orientation
    }
    readonly property CameraRecorder videoRecorder: CameraRecorder {
        controller: root.controller
    }
    readonly property FocusControl focus: FocusControl {
        controller: root.controller
    }
    readonly property FlashControl flash: FlashControl {
        controller: root.controller
    }
    readonly property ExposureControl exposure: ExposureControl {}
    readonly property CameraImageProcessing imageProcessing: CameraImageProcessing {}
    readonly property ViewfinderControl viewfinder: ViewfinderControl {
        controller: root.controller
    }
    readonly property MetaData metaData: MetaData {}

    // Failures other than a photo's or a recording's: the camera itself.
    signal error(string message)

    // From the shutter until the file is written the app stays awake: frozen
    // in the background, the photo was never saved.
    readonly property bool _saving: imageCapture._pending
    property int _saveTask: 0
    on_SavingChanged: {
        if (_saving && _saveTask === 0) {
            _saveTask = Platform.Lifecycle.beginBackgroundTask("recording", "saving a photo");
        } else if (!_saving && _saveTask !== 0) {
            Platform.Lifecycle.endBackgroundTask(_saveTask);
            _saveTask = 0;
        }
    }

    readonly property CameraController controller: CameraController {
        cameraId: root.deviceId
        zoomLevel: root.digitalZoom

        onActiveChanged: {
            if (active)
                root.errorCode = Camera.NoError;
        }
        onPhotoExposed: root.imageCapture.imageExposed(0)
        onPhotoSaved: function (url) {
            root.imageCapture._pending = false;
            root.imageCapture.imageSaved(0, decodeURIComponent(url.replace(/^file:\/\//, "")));
        }
        onErrorOccurred: function (message) {
            if (root.imageCapture._pending) {
                root.imageCapture._pending = false;
                root.imageCapture.captureFailed(0, message);
            } else if (!root.videoRecorder.recording) {
                root.errorCode = Camera.CameraError;
            }
            root.error(message);
        }
    }

    function searchAndLock() {
        if (focus.focusPointMode !== Camera.FocusPointCustom)
            return;
        // The point is on the viewfinder, which shows the frame turned by
        // the camera's orientation; the controller takes it on the frame.
        const p = focus.customFocusPoint;
        switch (orientation) {
        case 90:
            controller.focusOnPoint(p.y, 1 - p.x);
            break;
        case 180:
            controller.focusOnPoint(1 - p.x, 1 - p.y);
            break;
        case 270:
            controller.focusOnPoint(1 - p.y, p.x);
            break;
        default:
            controller.focusOnPoint(p.x, p.y);
        }
    }

    function unlock() {
        controller.unlockFocus();
    }

    function _applyState() {
        if (cameraState === Camera.ActiveState) {
            controller.start();
            return;
        }
        // Finishes the file; stopping the camera alone would cut it off unsaved.
        const recording = videoRecorder.recording;
        if (recording)
            controller.stopRecording();
        // Out of sight the camera is dropped, so its devices close; a recording
        // still being written keeps it.
        if (cameraState === Camera.UnloadedState && !recording)
            controller.release();
        else
            controller.stop();
        imageCapture._pending = false;
        if (cameraState === Camera.LoadedState) {
            controller.discover();
            configured = controller.discovered;
        }
    }

    // Later: discovery readies CameraConfigs, which cameraState's binding reads.
    onCameraStateChanged: Qt.callLater(_applyState)
}
