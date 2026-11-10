// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Qt 5 Camera.videoRecorder (QtMultimedia 5.x). Settings are accepted, but
// recording is not implemented: record() warns once and stays in
// StoppedState. (Qt 6 records with CaptureSession.recorder / MediaRecorder;
// no corpus app records video.)
import QtQml 2.15

QtObject {
    enum RecorderState { StoppedState, RecordingState }
    enum RecorderStatus {
        UnavailableStatus, UnloadedStatus, LoadingStatus, LoadedStatus, StartingStatus,
        RecordingStatus, PausedStatus, FinalizingStatus
    }

    readonly property int recorderState: 0
    readonly property int recorderStatus: 0
    property size resolution: Qt.size(-1, -1)
    property real frameRate: 0
    property int videoBitRate: 0
    property int audioBitRate: 0
    property int audioChannels: 0
    property int audioSampleRate: 0
    property string videoCodec: ""
    property string audioCodec: ""
    property string mediaContainer: ""
    property int encodingMode: 0
    property int videoEncodingMode: 0
    property int audioEncodingMode: 0
    property url outputLocation
    readonly property url actualLocation: ""
    readonly property int duration: 0
    property bool muted: false
    readonly property int errorCode: 0
    readonly property string errorString: ""

    property bool __warned: false

    function record() {
        if (!__warned) {
            __warned = true
            console.warn("QtMultimedia 5 shim: Camera.videoRecorder.record() is not supported on Keel")
        }
    }
    function stop() {
    }
    function setMetadata(key, value) {
    }
}
