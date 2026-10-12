import QtQuick
import QtMultimedia

QtObject {
    property int playbackState: MediaPlayer.StoppedState
    property int mediaStatus: MediaPlayer.NoMedia
    property real position: 0
    property real duration: 0
    property url source
    property int plays: 0

    signal errorOccurred(int error, string errorString)

    function play() {
        plays++;
        playbackState = MediaPlayer.PlayingState;
    }
    function pause() {
        playbackState = MediaPlayer.PausedState;
    }
    function stop() {
        playbackState = MediaPlayer.StoppedState;
    }
}
