import QtQuick
import QtMultimedia
import "Queue.js" as Queue

QtObject {
    id: player

    property QtObject media: MediaPlayer {
        audioOutput: AudioOutput {}
    }
    property var queue: []
    property int index: -1
    property bool shuffle: false
    property string repeatMode: "off" // "off" | "all" | "one"

    readonly property var currentTrack: index >= 0 && index < queue.length ? queue[index] : null
    readonly property bool playing: media.playbackState === MediaPlayer.PlayingState
    readonly property real position: media.position
    readonly property real duration: media.duration > 0 ? media.duration : (currentTrack ? currentTrack.duration * 1000 : 0)

    signal failed(var track)

    function playTracks(tracks, start) {
        queue = tracks;
        _play(start);
    }

    function toggle() {
        if (!currentTrack)
            return;
        if (playing)
            media.pause();
        else
            media.play();
    }

    function next() {
        _play(Queue.next(queue.length, index, shuffle, true, Math.random()));
    }

    function previous() {
        _play(Queue.previous(queue.length, index));
    }

    function seek(ms) {
        media.position = ms;
    }

    function cycleRepeat() {
        repeatMode = repeatMode === "off" ? "all" : repeatMode === "all" ? "one" : "off";
    }

    function _play(i) {
        if (i < 0)
            return;
        index = i;
        media.source = queue[i].path;
        media.play();
    }

    function _finished() {
        if (repeatMode === "one") {
            _play(index);
            return;
        }
        const i = Queue.next(queue.length, index, shuffle, repeatMode === "all", Math.random());
        if (i < 0)
            media.stop();
        else
            _play(i);
    }

    readonly property Connections _events: Connections {
        target: player.media

        function onMediaStatusChanged() {
            if (player.media.mediaStatus === MediaPlayer.EndOfMedia)
                player._finished();
        }
        function onErrorOccurred() {
            player.failed(player.currentTrack);
        }
    }
}
