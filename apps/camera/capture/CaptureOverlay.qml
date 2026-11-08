// SPDX-FileCopyrightText: 2016 - 2024 Jolla Ltd.
// SPDX-FileCopyrightText: 2024 - 2025 Jolla Mobile Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
//
// SPDX-License-Identifier: BSD-3-Clause

// Silica's Screen is qualified (S.Screen): which import an unqualified
// `Screen` names depends on the Qt version (the first up to Qt 6.8, the
// last from 6.10).
import Sailfish.Silica 1.0
import Sailfish.Silica 1.0 as S
import QtQuick 2.0
import Nemo.Configuration 1.0
import Nemo.Notifications 1.0
import MarathonApp.Camera 1.0

SettingsOverlay {
    id: settingsOverlay

    property bool reallyWideScreen: captureView.reallyWideScreen
    property var captureView
    property var camera
    property Item focusArea

    property int _recordingDuration: clock.enabled ? ((clock.time - _startTime) / 1000) : 0
    property int _recSecsRemaining: {
        var totalBitRate = (camera.videoRecorder.videoBitRate + camera.videoRecorder.audioBitRate) * 1.05;
        var maxDuration = Settings.storageMaxFileSize * 8 / totalBitRate;
        return maxDuration - _recordingDuration;
    }

    property var _startTime: new Date()

    width: captureView.width
    height: captureView.height

    // How the device is held, from the page orientation (Keel follows the
    // device's orientation sensor). The Jolla Camera read QtSensors'
    // OrientationSensor, which Keel does not provide.
    property int _pictureRotation: {
        switch (captureView.orientation) {
        case Orientation.Landscape:
            return 90;
        case Orientation.PortraitInverted:
            return 180;
        case Orientation.LandscapeInverted:
            return 270;
        default:
            return 0;
        }
    }

    function writeMetaData() {
        // Qt 5's page turn is counter-clockwise and camera.orientation the
        // sensor's, clockwise (as for the focus point in CaptureView): the
        // back camera's picture turns by their difference, the mirrored front
        // camera's by their sum.
        captureView.captureOrientation = camera.position === Camera.FrontFace ? (720 + camera.orientation + _pictureRotation) % 360 : (720 + camera.orientation - _pictureRotation) % 360;

        // Camera documentation says dateTimeOriginal should be used but at the moment CameraBinMetaData uses only
        // date property (which the documentation doesn't even list)
        camera.metaData.date = new Date();

        // No location yet: geotagging needs the Location permission.
        camera.metaData.gpsLatitude = undefined;
        camera.metaData.gpsLongitude = undefined;
        camera.metaData.gpsAltitude = undefined;
    }

    readonly property int storagePathStatus: Settings.storagePathStatus
    onStoragePathStatusChanged: checkStorage()

    readonly property bool _applicationActive: __silica_applicationwindow_instance.applicationActive
    on_ApplicationActiveChanged: if (_applicationActive)
        checkStorage()

    Component.onCompleted: checkStorage()

    function checkStorage() {
        if (!_applicationActive) {
            // We don't want to show notification when we're in the background
            return;
        }

        var prevStatus = previousStoragePathStatus.value;
        if (Settings.storagePathStatus == Settings.Unavailable) {
            if (prevStatus != Settings.storagePathStatus) {
                notification.publishMessage(qsTr("The selected storage is unavailable. Device memory will be used instead"));
            }
        } else if (Settings.storagePathStatus == Settings.Available) {
            if (prevStatus == Settings.Unavailable || prevStatus == Settings.Mounting) {
                notification.publishMessage(qsTr("Using memory card"));
            }
        } else if (Settings.storagePathStatus == Settings.Mounting) {
            notification.publishMessage(qsTr("Busy mounting the memory card. Device memory will be used instead"));
        }
        previousStoragePathStatus.value = Settings.storagePathStatus;

        // Refresh the remaining storage space, in case it was modified while we weren't active
        // TODO: Do this regularly throughout recording, if it doesn't interfere.
        if (!captureView.recording) {
            Settings.refreshMaxFileSize();
        }
    }

    opacity: 0.0

    showCommonControls: !captureView.recording
    isPortrait: captureView.isPortrait
    topButtonRowHeight: S.Screen.sizeCategory >= S.Screen.Large ? Theme.itemSizeLarge : Theme.itemSizeSmall
    deviceToggleEnabled: !captureView.captureBusy

    onPinchStarted: {
        // We're not getting notifications when the maximumDigitalZoom changes,
        // so update the value here.
        zoomIndicator.maximumZoom = camera.maximumDigitalZoom;
    }

    onPinchUpdated: function (pinch) {
        camera.digitalZoom = Math.max(1, Math.min(camera.digitalZoom + ((camera.maximumDigitalZoom - 1) * ((pinch.scale / Math.abs(pinch.previousScale) - 1))), camera.maximumDigitalZoom));
        zoomIndicator.show();
    }

    Connections {
        target: captureView
        ignoreUnknownSignals: true
        function onEffectiveActiveChanged() {
            if (!captureView.effectiveActive) {
                settingsOverlay.closeMenus();
            }
        }
    }

    onClicked: function (mouse) {
        if (!captureView._captureOnFocus && captureView.touchFocusSupported) {
            // Translate and rotate the touch point into focusArea's space.
            var focusPoint;
            switch ((360 - captureView.viewfinderOrientation) % 360) {
            case 90:
                focusPoint = Qt.point(mouse.y - ((height - focusArea.width) / 2) - captureView.viewfinderOffset, width - mouse.x);
                break;
            case 180:
                focusPoint = Qt.point(width - mouse.x - ((width - focusArea.width) / 2) + captureView.viewfinderOffset, height - mouse.y);
                break;
            case 270:
                focusPoint = Qt.point(height - mouse.y - ((height - focusArea.width) / 2) + captureView.viewfinderOffset, mouse.x);
                break;
            default:
                focusPoint = Qt.point(mouse.x - ((width - focusArea.width) / 2) - captureView.viewfinderOffset, mouse.y);
                break;
            }

            // Normalize the focus point.
            focusPoint.x = focusPoint.x / focusArea.width;
            focusPoint.y = focusPoint.y / focusArea.height;
            if (focusPoint.x < 0 || focusPoint.x > 1 || focusPoint.y < 0 || focusPoint.y > 1)
                return;

            // Mirror the point if the viewfinder is mirrored.
            if (captureView._horizontalMirror) {
                focusPoint.x = 1 - focusPoint.x;
            }
            if (captureView._verticalMirror) {
                focusPoint.y = 1 - focusPoint.y;
            }

            if (focusPoint.x >= 0.0 && focusPoint.x <= 1.0 && focusPoint.y >= 0.0 && focusPoint.y <= 1.0) {
                captureView.setFocusPoint(focusPoint);
            }
        }
    }

    shutter: CameraButton {
        id: captureButton

        objectName: "shutter"
        property bool canStopVideo: startRecordTimer.running || camera.videoRecorder.recorderState == CameraRecorder.RecordingState

        z: settingsOverlay.inButtonLayout ? 1 : 0
        size: Theme.iconSizeMedium
        anchors.centerIn: parent
        background.visible: icon.opacity < 1.0
        enabled: captureView._canCapture && !captureView._captureOnFocus

        // The button gives under the finger at once, with a light tap,
        // before the photo is taken on release.
        scale: pressed && containsMouse ? 0.84 : 1.0
        Behavior on scale {
            NumberAnimation {
                duration: captureButton.pressed ? 70 : 160
                easing.type: Easing.OutQuad
            }
        }

        onPressed: {
            captureView.pressFeedback();
            camera.lockAutoFocus();
        }
        onReleased: {
            if (containsMouse) {
                captureView._triggerCapture();
            } else {
                camera.unlockAutoFocus();
            }
        }
        onCanceled: camera.unlockAutoFocus()

        icon {
            opacity: {
                if (captureTimer.running) {
                    return Theme.opacityLow;
                } else if (captureButton.pressed) {
                    return Theme.opacityHigh;
                } else if (captureView._captureOnFocus) {
                    return Theme.opacityOverlay;
                } else {
                    return 1.0;
                }
            }

            source: canStopVideo ? "image://theme/icon-camera-video-shutter-off" : (camera.captureMode == Camera.CaptureVideo ? "image://theme/icon-camera-video-shutter-on" : "image://theme/icon-camera-shutter")
        }

        Label {
            anchors {
                centerIn: parent
                // The font is not monospaced so countdown values over 10 seconds will be slightly off center
                // TODO: FontMetrics might make more sense than magic below, but also be quite much more complex codewise
                verticalCenterOffset: -Math.round(font.pixelSize / 20)
                horizontalCenterOffset: text.length > 1 ? -Math.round(font.pixelSize / 20) : 0
            }
            text: captureTimer.running ? Math.floor(captureView._captureCountdown + 1) : Settings.mode.timer
            visible: Settings.mode.timer != 0 && !captureButton.canStopVideo
            opacity: captureTimer.running ? captureView._captureCountdown % 1 : 1.0
            color: captureTimer.running ? Theme.lightPrimaryColor : Theme.darkPrimaryColor
            font {
                pixelSize: captureTimer.running ? Theme.fontSizeHuge : Theme.fontSizeTiny
                weight: Font.Light
            }
            Behavior on font.pixelSize {
                NumberAnimation {
                    easing.type: Easing.InOutQuad
                    duration: 150
                }
            }
        }
    }

    // How long the video runs, in a pill at the top: a red dot that pulses
    // while recording, and digits that keep their width.
    Rectangle {
        id: timerLabel

        y: Theme.paddingMedium + (isPortrait ? S.Screen.topCutout.height : 0)
        anchors.horizontalCenter: parent.horizontalCenter
        width: timerRow.width + 2 * Theme.paddingMedium
        height: timerText.implicitHeight + Theme.paddingSmall
        radius: height / 2
        color: Theme.rgba(Theme.darkPrimaryColor, 0.55)
        opacity: captureView.recording ? 1.0 : 0.0
        visible: opacity > 0.0
        Behavior on opacity {
            FadeAnimator {}
        }

        Row {
            id: timerRow

            anchors.centerIn: parent
            spacing: Theme.paddingSmall

            Rectangle {
                id: recordingDot

                anchors.verticalCenter: parent.verticalCenter
                width: Theme.paddingMedium
                height: width
                radius: width / 2
                color: Theme.errorColor

                SequentialAnimation on opacity {
                    running: captureView.recording
                    loops: Animation.Infinite
                    alwaysRunToEnd: true
                    NumberAnimation {
                        from: 1.0
                        to: 0.25
                        duration: 600
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        from: 0.25
                        to: 1.0
                        duration: 600
                        easing.type: Easing.InOutSine
                    }
                }
            }

            Label {
                id: timerText

                text: Format.formatDuration(_recordingDuration, _recordingDuration >= 3600 ? Formatter.DurationLong : Formatter.DurationShort)
                font.pixelSize: Theme.fontSizeLarge
                font.features: {
                    "tnum": 1
                }
                color: Theme.lightPrimaryColor
            }
        }
    }

    Label {
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: timerLabel.bottom
        }
        opacity: {
            if (captureView.recording)
                return _recSecsRemaining < 300 || (_recordingDuration > 120 && _recSecsRemaining < 3600) ? 1.0 : 0.0;
            else
                return camera.captureMode == Camera.CaptureVideo && _recSecsRemaining < 300 ? 1.0 : 0.0;
        }
        Behavior on opacity {
            FadeAnimator {}
        }
        text: {
            if (captureView.recording) {
                if (_recSecsRemaining >= 60) {
                    return qsTr("Recording stops in %n min", "", Math.floor(_recSecsRemaining / 60));
                } else {
                    return qsTr("Recording stops in %n sec", "", _recSecsRemaining);
                }
            } else if (_recSecsRemaining == 0) {
                return qsTr("Storage full");
            } else {
                return qsTr("%n min estimated recording time left", "", Math.floor(_recSecsRemaining / 60));
            }
        }
        font.pixelSize: Theme.fontSizeExtraSmall
        color: Theme.lightPrimaryColor
        style: Text.Outline
        styleColor: "#20000000"
    }

    // Nemo.Time's WallClock is not on Keel; a one-second timer does here.
    Timer {
        id: clock

        property bool enabled: camera.videoRecorder.recorderState == CameraRecorder.RecordingState
        property date time: new Date()

        interval: 1000
        repeat: true
        running: enabled
        onTriggered: time = new Date()
        onEnabledChanged: {
            if (enabled) {
                // Now, not the last tick (which may be long gone).
                time = new Date();
                _startTime = time;
            }
        }
        onTimeChanged: {
            if (enabled && _recSecsRemaining <= 0 && camera) {
                camera.videoRecorder.stop();
            }
        }
    }

    // Viewfinder Grid
    Item {
        id: grid

        property real gridWidth: captureView.viewfinderOrientation % 180 == 0 ? focusArea.width : focusArea.height
        property real gridHeight: captureView.viewfinderOrientation % 180 == 0 ? focusArea.height : focusArea.width

        anchors.centerIn: parent
        anchors.verticalCenterOffset: isPortrait ? captureView.viewfinderOffset : 0
        anchors.horizontalCenterOffset: isPortrait ? 0 : captureView.viewfinderOffset

        visible: Settings.global.viewfinderGrid != "none" && camera.cameraStatus == Camera.ActiveStatus

        width: gridWidth / 3
        height: gridHeight / 3

        GridLine {
            anchors {
                horizontalCenter: grid.horizontalCenter
                verticalCenter: grid.top
            }
            width: grid.gridWidth
        }

        GridLine {
            anchors {
                horizontalCenter: grid.horizontalCenter
                verticalCenter: grid.bottom
            }
            width: grid.gridWidth
        }

        GridLine {
            anchors {
                horizontalCenter: grid.left
                verticalCenter: grid.verticalCenter
            }
            width: grid.gridHeight
            rotation: 90
        }

        GridLine {
            anchors {
                horizontalCenter: grid.right
                verticalCenter: grid.verticalCenter
            }
            width: grid.gridHeight
            rotation: 90
        }
    }

    ZoomIndicator {
        id: zoomIndicator

        anchors {
            top: timerLabel.bottom
            horizontalCenter: parent.horizontalCenter
        }

        zoom: camera.digitalZoom
        maximumZoom: camera.maximumDigitalZoom
    }

    Notification {
        id: notification

        function publishMessage(msg) {
            notification.previewBody = msg;
            notification.publish();
        }

        isTransient: true
        urgency: Notification.Critical
    }

    ConfigurationValue {
        id: previousStoragePathStatus
        key: "/apps/camera/previousStoragePathStatus"
    }
}
