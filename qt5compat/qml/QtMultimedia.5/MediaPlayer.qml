// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Qt 5 MediaPlayer / Audio (QtMultimedia 5.x) over Qt 6's MediaPlayer and
// AudioOutput. Qt 5 API kept: source, autoPlay, autoLoad (accepted; Qt 6
// always loads), loops, playbackState, status (Qt 5 numbering), duration,
// position, volume, muted, playbackRate, hasAudio, hasVideo, bufferProgress,
// seekable, errorString, metaData, availability, play(), pause(), stop(),
// seek(), and the playing(), paused(), stopped() and error(error, errorString)
// signals. Not kept: the `error` property (QML cannot have a property and a
// signal of the same name; `onError` is what apps use), playlist, audioRole,
// notifyInterval, mediaObject.
import QtQml 2.15
import QtMultimedia 6.0 as QM

QtObject {
    id: player

    enum Status {
        UnknownStatus, NoMedia, Loading, Loaded, Stalled, Buffering, Buffered,
        EndOfMedia, InvalidMedia
    }
    enum PlaybackState { StoppedState, PlayingState, PausedState }
    enum Error { NoError, ResourceError, FormatError, NetworkError, AccessDenied, ServiceMissing }
    // Qt 5 has Infinite = -1; Qt 6.4 rejects negative QML enum values, so
    // Infinite is INT_MAX here, and it and any negative value loop forever.
    enum Loop { Infinite = 2147483647 }
    // Loop.Infinite for use inside this file, where the name MediaPlayer
    // resolves to Qt 6's type (re-exported by this module's qmldir), whose
    // Infinite is -1.
    readonly property int __loopInfinite: 2147483647
    enum Availability { Available = 0, Unavailable = 1, Busy = 2, ResourceMissing = 3 }

    property url source
    property bool autoPlay: false
    property bool autoLoad: true
    property int loops: 1
    property real volume: 1.0
    property bool muted: false
    property real playbackRate: 1.0

    // Qt 5 and Qt 6 agree on StoppedState 0, PlayingState 1, PausedState 2.
    readonly property int playbackState: __player.playbackState
    readonly property int status: __status(__player.mediaStatus)
    readonly property int duration: __player.duration
    readonly property int position: __player.position
    readonly property bool hasAudio: __player.hasAudio
    readonly property bool hasVideo: __player.hasVideo
    readonly property real bufferProgress: __player.bufferProgress
    readonly property bool seekable: __player.seekable
    readonly property string errorString: __player.errorString
    readonly property var metaData: __player.metaData
    readonly property int availability: 0

    signal playing()
    signal paused()
    signal stopped()
    signal error(int error, string errorString)

    function play() {
        __player.play()
    }
    function pause() {
        __player.pause()
    }
    function stop() {
        __player.stop()
    }
    function seek(offset) {
        __player.setPosition(offset)
    }

    // Used by the VideoOutput wrapper to attach itself.
    readonly property QM.MediaPlayer __player: QM.MediaPlayer {
        source: player.source
        loops: player.loops < 0 || player.loops === player.__loopInfinite ? QM.MediaPlayer.Infinite
                                                                : player.loops
        playbackRate: player.playbackRate
        audioOutput: QM.AudioOutput {
            volume: player.volume
            muted: player.muted
        }

        onPlaybackStateChanged: {
            switch (playbackState) {
            case QM.MediaPlayer.PlayingState: player.playing(); break
            case QM.MediaPlayer.PausedState: player.paused(); break
            default: player.stopped(); break
            }
        }
        onErrorOccurred: function (error, errorString) {
            player.error(player.__error(error), errorString)
        }
    }

    function __status(s) {
        switch (s) {
        case QM.MediaPlayer.NoMedia: return 1
        case QM.MediaPlayer.LoadingMedia: return 2
        case QM.MediaPlayer.LoadedMedia: return 3
        case QM.MediaPlayer.StalledMedia: return 4
        case QM.MediaPlayer.BufferingMedia: return 5
        case QM.MediaPlayer.BufferedMedia: return 6
        case QM.MediaPlayer.EndOfMedia: return 7
        case QM.MediaPlayer.InvalidMedia: return 8
        default: return 0
        }
    }
    function __error(e) {
        switch (e) {
        case QM.MediaPlayer.NoError: return 0
        case QM.MediaPlayer.ResourceError: return 1
        case QM.MediaPlayer.FormatError: return 2
        case QM.MediaPlayer.NetworkError: return 3
        case QM.MediaPlayer.AccessDeniedError: return 4
        default: return 1
        }
    }
    function __autoPlay() {
        if (autoPlay && String(source) !== "")
            __player.play()
    }

    onSourceChanged: __autoPlay()
    onAutoPlayChanged: __autoPlay()
    Component.onCompleted: __autoPlay()
}
