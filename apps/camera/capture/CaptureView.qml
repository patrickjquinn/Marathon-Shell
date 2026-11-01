// SPDX-FileCopyrightText: 2013 - 2022 Jolla Ltd.
// SPDX-FileCopyrightText: 2020 Open Mobile Platform LLC.
// SPDX-FileCopyrightText: 2024 - 2025 Jolla Mobile Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
//
// SPDX-License-Identifier: BSD-3-Clause

// Silica's Screen is qualified (S.Screen): which import an unqualified
// `Screen` names depends on the Qt version (the first up to Qt 6.8, the
// last from 6.10).
import Sailfish.Silica 1.0
import Sailfish.Silica 1.0 as S
import QtQuick 2.4
import Nemo.Ngf 1.0
import MarathonApp.Camera 1.0

FocusScope {
    id: captureView

    property bool active
    // Starting the camera blocks the GUI thread; the app holds it back until
    // its first frame is on screen.
    property bool cameraAllowed: true
    property int orientation
    property bool inButtonLayout: captureOverlay == null || captureOverlay.inButtonLayout
    property QtObject captureModel

    readonly property int viewfinderOrientation: {
        var rotation = 0;
        switch (captureView.orientation) {
        case Orientation.Landscape:
            rotation = 90;
            break;
        case Orientation.PortraitInverted:
            rotation = 180;
            break;
        case Orientation.LandscapeInverted:
            rotation = 270;
            break;
        }

        // Qt 5's turn, counter-clockwise, which the focus point and focus
        // area below work in; camera.orientation is the sensor's, clockwise
        // (as the viewfinder turns it). Added as it was, a tap focused the
        // point opposite it on a sideways sensor: on the floor, the near
        // object.
        return (720 - camera.orientation + rotation) % 360;
    }
    property int captureOrientation
    property int pageRotation
    property bool orientationTransitionRunning

    property alias camera: camera
    property QtObject viewfinder

    readonly property bool recording: active && camera.videoRecorder.recorderState == CameraRecorder.RecordingState

    property bool _unload

    property bool touchFocusSupported: (camera.focus.focusMode == Camera.FocusAuto || camera.focus.focusMode == Camera.FocusContinuous) && camera.captureMode != Camera.CaptureVideo

    // not bound to focusTimer.running, restarting timer shouldn't exit tap focus mode temporarily and lose focus state
    property bool tapFocusActive
    property bool _captureOnFocus
    property real _captureCountdown

    property bool reallyWideScreen: (S.Screen.height / S.Screen.width) >= 2.0
    // wide screen can move 4:3 viewfinder a little lower and avoid overlap with top&bottom buttons
    readonly property real viewfinderOffset: Math.min(0, isPortrait ? (focusArea.width - height) / 2 : (focusArea.width - width) / 2) + ((reallyWideScreen && (focusArea.width / focusArea.height <= 1.4)) ? Theme.itemSizeLarge + S.Screen.topCutout.height : 0)

    readonly property bool isPortrait: orientation == Orientation.Portrait || orientation == Orientation.PortraitInverted
    // A recording carries on for a while in the background (the timer below).
    readonly property bool effectiveActive: cameraAllowed && (active || recording) && (_applicationActive || recording) && pageStack.depth < 2

    readonly property bool _canCapture: {
        switch (camera.captureMode) {
        case Camera.CaptureStillImage:
            return camera.imageCapture.ready;
        case Camera.CaptureVideo:
            return camera.videoRecorder.recorderStatus >= CameraRecorder.LoadedStatus && captureOverlay != null && captureOverlay._recSecsRemaining > 0;
        default:
            return false;
        }
    }

    property bool _captureQueued
    property bool captureBusy
    onCaptureBusyChanged: {
        if (!captureBusy && _captureQueued) {
            _captureQueued = false;
            camera.captureImage();
        }
    }

    property bool handleVolumeKeys: camera.imageCapture.ready && camera.captureMode == Camera.CaptureStillImage && !captureView._captureOnFocus
    property bool captureOnVolumeRelease

    onHandleVolumeKeysChanged: {
        if (!handleVolumeKeys)
            captureOnVolumeRelease = false;
    }

    readonly property bool _mirrorViewfinder: camera.position === Camera.FrontFace
    readonly property bool _horizontalMirror: _mirrorViewfinder && camera.orientation % 180 == 0
    readonly property bool _verticalMirror: _mirrorViewfinder && camera.orientation % 180 != 0

    readonly property bool _applicationActive: __silica_applicationwindow_instance.applicationActive

    readonly property string deviceId: Settings.deviceId

    property var captureOverlay: null

    signal recordingStopped(url url, string mimeType)
    signal loaded
    signal captured

    // The shutter's sound and animation have played for this capture.
    property bool _feedbackGiven
    property real _snapX
    property real _snapY
    property real _snapScale: 0.4

    // A photo answers when it is exposed: the frame on screen then is the
    // photo. HDR waits until it is saved: the user must hold still until its
    // frames are in.
    function shutterFeedback() {
        if (_feedbackGiven)
            return;
        _feedbackGiven = true;
        shutterEvent.play();
        captureAnimation.start();
    }

    function _instantFeedback() {
        return camera.exposure.exposureMode != Camera.ExposureHDR && camera.exposure.exposureMode != Camera.ExposureNight;
    }

    // The snapshot flies off to the roll on the left.
    function _aimSnapshot() {
        _snapScale = 0.4;
        _snapX = isPortrait ? -height : -width;
        _snapY = 0;
    }

    Item {
        id: captureSnapshot

        property alias sourceItem: captureSnapshotEffect.sourceItem

        visible: false
        width: parent.width
        height: parent.height

        ShaderEffectSource {
            id: captureSnapshotEffect

            hideSource: false
            live: false
            anchors.centerIn: parent
            width: isPortrait ? captureView.width : captureView.height
            height: isPortrait ? captureView.height : captureView.width
            rotation: -captureView.pageRotation
        }
    }

    function setFocusPoint(point) {
        focusTimer.restart();
        camera.unlock();
        tapFocusActive = true;
        camera.focus.customFocusPoint = point;
        camera.searchAndLock();
    }

    function _resetFocus() {
        focusTimer.running = false;
        tapFocusActive = false;
        camera.unlock();
    }

    function _triggerCapture() {
        // avoid duplicate capture if volume key and some other key trigger (e.g. shutter)
        captureOnVolumeRelease = false;

        if (captureTimer.running) {
            captureTimer.reset();
        } else if (startRecordTimer.running) {
            startRecordTimer.running = false;
        } else if (camera.videoRecorder.recorderState == CameraRecorder.RecordingState) {
            camera.videoRecorder.stop();
        } else if (_canCapture) {
            if (Settings.mode.timer != 0) {
                captureTimer.restart();
            } else if (camera.captureMode == Camera.CaptureStillImage) {
                camera.captureImage();
            } else {
                camera.record();
            }
        }
    }

    function _pickViewfinderResolution(resolutions, aspectRatio) {
        var ratio;
        if (aspectRatio === CameraConfigs.AspectRatio_16_9) {
            ratio = 16.0 / 9.0;
        } else { // CameraConfigs.AspectRatio_4_3
            ratio = 4.0 / 3.0;
        }

        if (resolutions && resolutions.length > 0) {
            var selectedPixels = 0;
            var selectedIndex = 0;
            var targetWidth = Math.round(S.Screen.width * ratio);
            for (var i = 0; i < resolutions.length; i++) {
                var resolution = resolutions[i];
                if (resolution.height === S.Screen.width && resolution.width === targetWidth) {
                    return resolution;
                }
            }
            return _pickResolution(resolutions, aspectRatio);
        }
        return "-1x-1";
    }

    function aspectRatioToFraction(aspectRatio) {
        if (aspectRatio < 0) {
            return aspectRatio;
        }

        var ratio = 4.0 / 3.0;
        if (aspectRatio === CameraConfigs.AspectRatio_16_9) {
            ratio = 16.0 / 9.0;
        } else if (aspectRatio !== CameraConfigs.AspectRatio_4_3) {
            console.warn("Unknown aspect ratio", aspectRatio);
        }
        return ratio;
    }

    // negative aspect ratio means ignored
    function _pickResolution(resolutions, aspectRatio) {
        var ratio = aspectRatioToFraction(aspectRatio);

        if (resolutions && resolutions.length > 0) {
            var selectedPixels = 0;
            var selectedIndex = -1;
            for (var i = 0; i < resolutions.length; i++) {
                var resolution = resolutions[i];
                var pixels = resolution.width * resolution.height;

                if (ratio < 0 || (Math.abs(ratio - resolution.width / resolution.height) < 0.05 && pixels > selectedPixels)) {
                    selectedPixels = pixels;
                    selectedIndex = i;
                }
            }

            if (selectedIndex >= 0) {
                return resolutions[selectedIndex];
            }
        }
        return "-1x-1";
    }

    on_CanCaptureChanged: {
        if (!_canCapture) {
            startRecordTimer.running = false;
        }
    }

    Component.onCompleted: {
        loadOverlay();
    }

    onDeviceIdChanged: {
        _resetFocus();
        captureTimer.reset();
        Settings.global.deviceId = Settings.deviceId;
        camera.deviceId = Settings.deviceId;
        Settings.global.position = camera.position;
        if (camera.position === Camera.BackFace) {
            Settings.global.previousBackFacingDeviceId = camera.deviceId;
        }
    }

    onEffectiveActiveChanged: {
        if (!effectiveActive) {
            _resetFocus();
            captureTimer.reset();
        }
    }

    Timer {
        // prevent video recording continuing forever in the background
        running: recording && !_applicationActive
        interval: 60 * 1000
        onTriggered: camera.videoRecorder.stop()
    }

    Timer {
        interval: 1000
        running: captureView._unload && (camera.cameraStatus === Camera.UnloadedStatus || camera.cameraStatus === Camera.CameraError)
        onTriggered: {
            captureView._unload = false;
        }
    }

    Timer {
        id: reactivateTimer

        property int retryCounter
        readonly property bool abort: retryCounter >= 5

        interval: 1000
        running: camera.cameraStatus == Camera.LoadingStatus && !abort
        onTriggered: {
            // Try re-activate when stuck in loading status for 1sec.
            active = false;
            active = true;
            ++retryCounter;
        }
    }

    NonGraphicalFeedback {
        id: shutterEvent
        event: "camera_shutter"
    }

    // A light tap under the finger when the shutter goes down.
    NonGraphicalFeedback {
        id: pressEvent
        event: "feedback_press_weak"
    }

    function pressFeedback() {
        pressEvent.play();
    }

    NonGraphicalFeedback {
        id: recordStartEvent
        event: "video_record_start"
    }

    Timer {
        id: startRecordTimer

        interval: 200
        onTriggered: {
            captureOverlay.writeMetaData();
            camera.videoRecorder.record();
            if (camera.videoRecorder.recorderState == CameraRecorder.RecordingState) {
                camera.videoRecorder.recorderStateChanged.connect(camera._finishRecording);
            }
        }
    }

    SequentialAnimation {
        id: captureTimer

        property bool resetCameraOnStop

        function reset() {
            if (resetCameraOnStop) {
                _resetFocus();
                resetCameraOnStop = false;
            }
            stop();
        }

        NumberAnimation {
            duration: Settings.mode.timer * 1000
            from: Settings.mode.timer
            to: 0
            easing.type: Easing.Linear
            target: captureView
            property: "_captureCountdown"
        }
        ScriptAction {
            script: {
                if (camera.captureMode == Camera.CaptureStillImage) {
                    if (camera.focus.focusPointMode == Camera.FocusPointAuto) {
                        camera.searchAndLock();
                    }
                    camera.captureImage();
                } else {
                    camera.record();
                }

                if (captureTimer.resetCameraOnStop) {
                    _resetFocus();
                    captureTimer.resetCameraOnStop = false;
                }
            }
        }
    }

    NonGraphicalFeedback {
        id: recordStopEvent
        event: "video_record_stop"
    }

    onRecordingStopped: function (url, mimeType) {
        if (captureModel) {
            captureModel.appendCapture(url, mimeType);
        }
    }

    Camera {
        id: camera

        function lockAutoFocus() {
            captureOverlay.closeMenus();
            // timed capture locks when timer triggers
            if (camera.captureMode == Camera.CaptureStillImage && focus.focusMode != Camera.FocusInfinity && focus.focusMode != Camera.FocusHyperfocal && camera.lockStatus == Camera.Unlocked && focus.focusPointMode == Camera.FocusPointAuto && Settings.mode.timer == 0) {
                camera.searchAndLock();
            }
        }

        function unlockAutoFocus() {
            if (camera.captureMode == Camera.CaptureStillImage && focus.focusMode != Camera.FocusInfinity && focus.focusMode != Camera.FocusHyperfocal && focus.focusPointMode == Camera.FocusPointAuto) {
                camera.unlock();
            }
        }

        function captureImage() {
            if (camera.lockStatus != Camera.Searching) {
                _completeCapture();
            } else {
                captureView._captureOnFocus = true;
            }
        }

        function record() {
            videoRecorder.outputLocation = Settings.videoCapturePath("mp4");
            startRecordTimer.running = true;
            recordStartEvent.play();
        }

        function _completeCapture() {
            if (captureBusy) {
                _captureQueued = true;
                return;
            }

            captureBusy = true;
            captureOverlay.writeMetaData();

            camera.imageCapture.captureToLocation(Settings.photoCapturePath('jpg'));
            if (captureView._instantFeedback())
                captureView.shutterFeedback();

            if (focusTimer.running) {
                focusTimer.restart();
            }
        }

        function _finishRecording() {
            if (videoRecorder.recorderState == CameraRecorder.StoppedState) {
                videoRecorder.recorderStateChanged.disconnect(_finishRecording);
                var finalUrl = Settings.completeCapture(videoRecorder.outputLocation);
                if (finalUrl !== "") {
                    captureView.recordingStopped(finalUrl, videoRecorder.mediaContainer);
                }
                recordStopEvent.play();
            }
        }

        property bool hasCameraOnBothSides
        property var backFacingCameras

        // On some adaptations media booster makes camera initialization fail
        // and Camera must be reloaded, try to do that once when that happens.
        // Wait until the Camera item has completed and activation has been
        // requested before checking so its construction-time default
        // UnloadedState/UnloadedStatus is not treated as a reload failure.
        property bool reloadCheckEnabled
        property bool needsReload: reloadCheckEnabled && captureView.effectiveActive && (camera.errorCode === Camera.CameraError || (camera.cameraState === Camera.UnloadedState && camera.cameraStatus === Camera.UnloadedStatus))
        property bool initialized

        Component.onCompleted: reloadCheckEnabled = true

        onErrorCodeChanged: {
            if (errorCode == Camera.CameraError) {
                captureView._unload = true;
            }
        }

        onNeedsReloadChanged: {
            if (needsReload) {
                captureView._unload = true;
            }
        }

        deviceId: Settings.deviceId
        captureMode: Settings.global.captureMode == "image" ? Camera.CaptureStillImage : Camera.CaptureVideo

        onCaptureModeChanged: {
            // Reset flash mode when changing to video mode
            if (initialized && captureMode === Camera.CaptureVideo) {
                Settings.mode.flash = Camera.FlashOff;
            }
            captureView._resetFocus();
        }

        cameraState: {
            if (captureView.effectiveActive && !captureView._unload) {
                if (CameraConfigs.ready) {
                    return Camera.ActiveState;
                } else {
                    return Camera.LoadedState;
                }
            } else {
                return Camera.UnloadedState;
            }
        }

        onCameraStateChanged: {
            if (cameraState == Camera.ActiveState && captureOverlay) {
                captureView.loaded();
            }
        }

        onCameraStatusChanged: {
            if (camera.cameraStatus === Camera.ActiveStatus) {
                reactivateTimer.retryCounter = 0;
            } else {
                _captureQueued = false;
                captureBusy = false;
            }

            var backCameras = [];
            if (cameraStatus === Camera.LoadedStatus && !initialized) {
                initialized = true;
                var hasFrontFace = false;
                var hasBackFace = false;

                for (var i = 0; i < camera.availableCameras.length; i++) {
                    var device = camera.availableCameras[i];
                    if (!hasFrontFace && device.position === Camera.FrontFace) {
                        hasFrontFace = true;
                        Settings.global.frontFacingDeviceId = device.deviceId;
                    } else if (device.position === Camera.BackFace) {
                        hasBackFace = true;
                        backCameras.push(device);
                    }
                }

                backFacingCameras = backCameras;

                hasCameraOnBothSides = hasFrontFace && hasBackFace;

                // A stored camera that is gone (or never was) counts as none.
                var backIds = backCameras.map(function (d) {
                    return d.deviceId;
                });
                if (backIds.indexOf(Settings.global.previousBackFacingDeviceId) < 0 && backCameras.length > 0) {
                    if (backIds.indexOf(camera.defaultCameraId) >= 0) {
                        Settings.global.previousBackFacingDeviceId = camera.defaultCameraId;
                    } else {
                        Settings.global.previousBackFacingDeviceId = backIds[0];
                    }
                }

                // On a first start nothing is chosen yet and the camera falls
                // back to the first device unnamed, so the lens switch showed
                // no lens as the one in use. Choose it by name.
                var knownIds = camera.availableCameras.map(function (d) {
                    return d.deviceId;
                });
                if (knownIds.indexOf(Settings.deviceId) < 0 && Settings.global.previousBackFacingDeviceId.length > 0) {
                    Settings.deviceId = Settings.global.previousBackFacingDeviceId;
                }
                // The stored camera was applied before the cameras were
                // known, so its side was not.
                Settings.global.position = camera.position;

                // Always disable flash torch at startup
                if (captureMode === Camera.CaptureVideo) {
                    Settings.mode.flash = Camera.FlashOff;
                }
            }
        }

        imageCapture {
            resolution: (Settings.mode.enableHighres && CameraConfigs.supportedHighresImageResolutions.length > 0) ? _pickResolution(CameraConfigs.supportedHighresImageResolutions, -1) : _pickResolution(CameraConfigs.supportedImageResolutions, Settings.aspectRatio)

            onImageSaved: function (requestId, path) {
                // HDR case emits the exposed already on the first image, delay the feedback so user avoids
                // moving the device until it's safe again.
                if (camera.exposure.exposureMode == Camera.ExposureHDR) {
                    shutterEvent.play();
                    captureAnimation.start();
                }

                camera.unlockAutoFocus();
                captureBusy = false;
                captureView._feedbackGiven = false;

                if (captureModel) {
                    captureModel.appendCapture(path, "image/jpeg");
                }

                Settings.completePhoto(Qt.resolvedUrl(path));
            }
            onImageExposed: function (requestId) {
                if (camera.exposure.exposureMode != Camera.ExposureHDR) {
                    captureView.shutterFeedback();
                } else {
                    flashAnimation.start();
                }
            }
            onCaptureFailed: function (requestId, message) {
                camera.unlockAutoFocus();
                captureBusy = false;
                captureView._feedbackGiven = false;
            }
        }
        videoRecorder {
            resolution: _pickResolution(CameraConfigs.supportedVideoResolutions, CameraConfigs.AspectRatio_16_9)

            audioChannels: 2
            audioSampleRate: Settings.global.audioSampleRate
            audioCodec: Settings.global.audioCodec
            videoCodec: Settings.global.videoCodec
            mediaContainer: Settings.global.mediaContainer

            videoEncodingMode: Settings.global.videoEncodingMode
            videoBitRate: Settings.global.videoBitRate
        }
        focus {
            // could expect that locking focus on auto or continous behaves the same, but
            // continuous doesn't work as well
            focusMode: {
                // The cameraStatus doesn't really matter as a precondition but incorporating
                // it ensures the binding is reevaluated when the status changes and the desired
                // focus mode is assigned. Otherwise QtMultimedia may reject a mode as unsupported
                // and default to auto because the binding was evaluated in the unloaded state and
                // real support was unknown at that time.
                if (camera.cameraStatus == Camera.ActiveStatus && tapFocusActive) {
                    return Camera.FocusAuto;
                } else if (CameraConfigs.supportedFocusModes.indexOf(Camera.FocusContinuous) >= 0) {
                    return Camera.FocusContinuous;
                } else if (CameraConfigs.supportedFocusModes.length > 0) {
                    return CameraConfigs.supportedFocusModes[0];
                } else {
                    return Camera.FocusAuto;
                }
            }
            focusPointMode: tapFocusActive ? Camera.FocusPointCustom : Camera.FocusPointAuto
        }
        flash.mode: Settings.mode.flash
        imageProcessing.whiteBalanceMode: {
            var hasFilter = camera.imageProcessing.colorFilter !== CameraImageProcessing.ColorFilterNone;
            return hasFilter ? CameraImageProcessing.WhiteBalanceAuto : Settings.global.whiteBalance;
        }

        exposure {
            exposureMode: Settings.mode.exposureMode
            exposureCompensation: Settings.global.exposureCompensation / 2.0
            meteringMode: Settings.mode.meteringMode
        }

        viewfinder {
            resolution: {
                var resolutions = CameraConfigs.supportedViewfinderResolutions;
                if (resolutions.length > 0) {
                    // assuming high res is 4:3
                    var aspectRatio = (Settings.mode.enableHighres && CameraConfigs.supportedHighresImageResolutions.length > 0) ? CameraConfigs.AspectRatio_4_3 : Settings.aspectRatio;

                    return _pickViewfinderResolution(resolutions, aspectRatio);
                }
                return "-1x-1";
            }

            // Let gst-droid decide the best framerate
        }

        metaData {
            orientation: captureView.captureOrientation
        }

        focus.onFocusModeChanged: camera.unlock()

        onLockStatusChanged: {
            if (lockStatus != Camera.Searching && captureView._captureOnFocus) {
                captureView._captureOnFocus = false;
                camera._completeCapture();
            }
        }
    }

    Connections {
        target: CameraConfigs
        function onReadyChanged() {
            // Reset flash torch mode if it's not supported
            if (camera.captureMode === Camera.CaptureVideo && CameraConfigs.supportedFlashModes.indexOf(Settings.mode.flash) === -1) {
                Settings.mode.flash = Camera.FlashOff;
            }
        }
    }

    Binding {
        target: CameraConfigs
        property: "camera"
        value: camera
    }

    Binding {
        target: captureView.viewfinder
        property: "source"
        value: camera
    }

    Rectangle {
        id: flashRectangle

        anchors.fill: parent
        color: "white"
        opacity: 0
    }

    SequentialAnimation {
        id: flashAnimation

        PropertyAction {
            target: flashRectangle
            property: "visible"
            value: true
        }
        OpacityAnimator {
            target: flashRectangle
            from: Theme.opacityHigh
            to: 0
            duration: 250
        }
        PropertyAction {
            target: flashRectangle
            property: "visible"
            value: false
        }
    }

    // The shutter's blink, over the viewfinder.
    Rectangle {
        id: blinkRectangle

        anchors.fill: parent
        color: Theme.darkPrimaryColor
        opacity: 0
        visible: opacity > 0
    }

    // A quick dark blink, then the frame shrinks off to the roll on the left.
    SequentialAnimation {
        id: captureAnimation

        PropertyAction {
            target: captureSnapshot
            property: "sourceItem"
            value: viewfinder
        }
        ScriptAction {
            script: {
                captureSnapshotEffect.scheduleUpdate();
                captureView._aimSnapshot();
            }
        }
        PropertyAction {
            target: captureSnapshot
            property: "x"
            value: 0
        }
        PropertyAction {
            target: captureSnapshot
            property: "y"
            value: 0
        }
        PropertyAction {
            target: captureSnapshot
            property: "scale"
            value: 1
        }
        PropertyAction {
            target: captureSnapshot
            property: "opacity"
            value: 1
        }
        PropertyAction {
            target: captureSnapshot
            property: "visible"
            value: true
        }
        ParallelAnimation {
            SequentialAnimation {
                NumberAnimation {
                    target: blinkRectangle
                    property: "opacity"
                    from: 0
                    to: 0.65
                    duration: 35
                }
                NumberAnimation {
                    target: blinkRectangle
                    property: "opacity"
                    to: 0
                    duration: 170
                    easing.type: Easing.OutQuad
                }
            }
            SequentialAnimation {
                PauseAnimation {
                    duration: 80
                }
                ParallelAnimation {
                    NumberAnimation {
                        target: captureSnapshot
                        property: "x"
                        to: captureView._snapX
                        duration: 320
                        easing.type: Easing.InOutCubic
                    }
                    NumberAnimation {
                        target: captureSnapshot
                        property: "y"
                        to: captureView._snapY
                        duration: 320
                        easing.type: Easing.InOutCubic
                    }
                    NumberAnimation {
                        target: captureSnapshot
                        property: "scale"
                        to: captureView._snapScale
                        duration: 320
                        easing.type: Easing.InOutCubic
                    }
                }
            }
        }
        PropertyAction {
            target: captureSnapshot
            property: "visible"
            value: false
        }
        PropertyAction {
            target: captureSnapshot
            property: "sourceItem"
            value: null
        }
        ScriptAction {
            script: captureView.captured()
        }
    }

    property Component overlayComponent
    property var overlayIncubator

    function loadOverlay() {
        overlayComponent = Qt.createComponent("CaptureOverlay.qml", Component.Asynchronous, captureView);
        if (overlayComponent) {
            if (overlayComponent.status === Component.Ready) {
                incubateOverlay();
            } else if (overlayComponent.status === Component.Loading) {
                overlayComponent.statusChanged.connect(function (status) {
                    if (overlayComponent) {
                        if (status == Component.Ready) {
                            incubateOverlay();
                        } else if (status == Component.Error) {
                            console.warn(overlayComponent.errorString());
                        }
                    }
                });
            } else {
                console.log("Error loading capture overlay", overlayComponent.errorString());
            }
        }
    }

    function incubateOverlay() {
        overlayIncubator = overlayComponent.incubateObject(captureView, {
            "captureView": captureView,
            "camera": camera,
            "focusArea": focusArea
        }, Qt.Asynchronous);
        overlayIncubator.onStatusChanged = function (status) {
            if (status == Component.Ready) {
                captureOverlay = overlayIncubator.object;
                captureOverlay.orientationTransitionRunning = Qt.binding(function () {
                    return captureView.orientationTransitionRunning;
                });
                overlayFadeIn.start();
                overlayIncubator = null;
                if (camera.cameraState == Camera.ActiveState && captureOverlay) {
                    captureView.loaded();
                }
            } else if (status == Component.Error) {
                console.log("Failed to create capture overlay");
                overlayIncubator = null;
            }
        };
    }

    FadeAnimator {
        id: overlayFadeIn

        target: captureOverlay
        to: 1.0
        duration: 100
    }

    Item {
        id: focusArea

        // The frame as the viewfinder fits it into the view, turned
        // upright: on a tall screen it fills the width, on a square one the
        // height.
        readonly property bool _turned: captureView.viewfinderOrientation % 180 != 0
        readonly property real _scale: {
            var r = camera.viewfinder.resolution;
            var w = _turned ? r.height : r.width;
            var h = _turned ? r.width : r.height;
            return w > 0 && h > 0 ? Math.min(captureView.width / w, captureView.height / h) : 1;
        }

        width: camera.viewfinder.resolution.width * _scale
        height: camera.viewfinder.resolution.height * _scale

        rotation: -captureView.viewfinderOrientation
        anchors {
            centerIn: parent
            verticalCenterOffset: isPortrait ? viewfinderOffset : 0
            horizontalCenterOffset: isPortrait ? 0 : viewfinderOffset
        }
        opacity: captureOverlay ? 1.0 - captureOverlay.settingsOpacity : 1.0

        Repeater {
            model: camera.focus.focusZones
            delegate: Item {
                readonly property rect area: modelData.area
                readonly property int status: modelData.status

                x: focusArea.width * (captureView._horizontalMirror ? 1 - area.x - area.width : area.x)
                y: focusArea.height * (captureView._verticalMirror ? 1 - area.y - area.height : area.y)
                width: focusArea.width * area.width
                height: focusArea.height * area.height

                visible: status != Camera.FocusAreaUnused && camera.focus.focusPointMode == Camera.FocusPointCustom

                Rectangle {
                    width: Math.min(parent.width, parent.height)
                    height: width
                    anchors.centerIn: parent
                    radius: width / 2
                    border {
                        width: Math.round(Theme.pixelRatio * 2)
                        color: status == Camera.FocusAreaFocused ? (Theme.colorScheme == Theme.LightOnDark ? Theme.highlightColor : Theme.highlightFromColor(Theme.highlightColor, Theme.LightOnDark)) : "white"
                    }
                    color: "#00000000"
                }
            }
        }
    }

    Timer {
        id: focusTimer

        interval: 5000
        onTriggered: {
            if (!captureTimer.running) {
                captureView._resetFocus();
            } else {
                captureTimer.resetCameraOnStop = true;
            }
        }
    }

    Keys.onVolumeDownPressed: function (event) {
        if (handleVolumeKeys && !event.isAutoRepeat) {
            camera.lockAutoFocus();
            captureOnVolumeRelease = true;
        }
    }
    Keys.onVolumeUpPressed: function (event) {
        if (handleVolumeKeys && !event.isAutoRepeat) {
            camera.lockAutoFocus();
            captureOnVolumeRelease = true;
        }
    }

    function supportedKey(key) {
        return key === Qt.Key_CameraFocus || key === Qt.Key_Camera || key === Qt.Key_VolumeDown || key === Qt.Key_VolumeUp;
    }

    Keys.onPressed: function (event) {
        if (supportedKey(event.key)) {
            event.accepted = true;
        }

        if (event.isAutoRepeat) {
            return;
        }

        if (event.key == Qt.Key_CameraFocus) {
            camera.lockAutoFocus();
        } else if (event.key == Qt.Key_Camera) {
            captureView._triggerCapture(); // key having half-pressed state too so can capture already here
        }
    }

    Keys.onReleased: function (event) {
        if (supportedKey(event.key)) {
            event.accepted = true;
        }

        if (event.isAutoRepeat) {
            return;
        }

        if (event.key == Qt.Key_CameraFocus) {
            // note: forces capture if it was still pending. debatable if that should be allowed to finish.
            camera.unlockAutoFocus();
        } else if ((event.key == Qt.Key_VolumeDown || event.key == Qt.Key_VolumeUp) && captureOnVolumeRelease && handleVolumeKeys) {
            captureView._triggerCapture();
        }
    }
}
