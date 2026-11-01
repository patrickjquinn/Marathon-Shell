// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

import QtQuick
import MarathonApp.Camera

// Qt 5 Multimedia's CameraRecorder, as Camera.videoRecorder. The encoding
// settings are the controller's own (H.264 in MP4, no sound); the ones here
// are what the Jolla Camera reads back.
QtObject {
    enum RecorderState {
        StoppedState,
        RecordingState,
        PausedState
    }
    enum RecorderStatus {
        UnavailableStatus,
        UnloadedStatus,
        LoadingStatus,
        LoadedStatus,
        StartingStatus,
        RecordingStatus,
        PausedStatus,
        FinalizingStatus
    }
    enum EncodingMode {
        ConstantQualityEncoding,
        ConstantBitRateEncoding,
        AverageBitRateEncoding
    }

    required property CameraController controller

    readonly property bool recording: controller.isRecording
    readonly property int recorderState: recording ? CameraRecorder.RecordingState : CameraRecorder.StoppedState
    readonly property int recorderStatus: {
        if (recording)
            return CameraRecorder.RecordingStatus;
        return controller.active ? CameraRecorder.LoadedStatus : CameraRecorder.UnloadedStatus;
    }
    property string outputLocation
    property size resolution
    property int audioChannels
    property int audioSampleRate
    property string audioCodec
    property string videoCodec
    property string mediaContainer
    property int videoEncodingMode
    property int videoBitRate
    readonly property int audioBitRate: 0

    function record() {
        controller.startRecording(outputLocation, Settings.captures.posterPath(outputLocation));
    }

    function stop() {
        controller.stopRecording();
    }
}
