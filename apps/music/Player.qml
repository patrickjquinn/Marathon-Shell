import QtQuick
import QtMultimedia
import MarathonOS.Music 1.0
import "Queue.js" as Queue

QtObject {
    id: player

    property var media: MediaPlayer {
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

    readonly property url artUrl: currentTrack ? Artwork.art(currentTrack.path) : ""

    property real _resumeAt: 0
    // Consecutive tracks that failed to play, so a queue of broken files stops.
    property int _failures: 0
    // A restored queue loads paused; a broken file there is reported, not skipped.
    property bool _autoplay: false

    signal failed(var track)

    function playTracks(tracks, start) {
        _failures = 0;
        queue = tracks;
        _play(start);
    }

    // Plays `tracks` once in a random order, leaving the shuffle mode as it was.
    function shuffleTracks(tracks) {
        playTracks(Queue.shuffled(tracks, Math.random), 0);
    }

    // Appends to the queue, or starts playing when nothing is loaded.
    function enqueue(track) {
        if (!currentTrack)
            playTracks([track], 0);
        else
            queue = queue.concat([track]);
    }

    function toggle() {
        if (!currentTrack)
            return;
        if (playing) {
            media.pause();
        } else {
            _autoplay = true;
            media.play();
        }
    }

    function next() {
        _play(Queue.next(queue.length, index, shuffle, true, Math.random()));
    }

    // Past the first seconds, Previous restarts the track.
    function previous() {
        if (currentTrack && media.position > 3000)
            media.position = 0;
        else
            _play(Queue.previous(queue.length, index));
    }

    function seek(ms) {
        media.position = ms;
    }

    function cycleRepeat() {
        repeatMode = repeatMode === "off" ? "all" : repeatMode === "all" ? "one" : "off";
    }

    function snapshot() {
        return { paths: queue.map(t => t.path), index: index, position: media.position, shuffle: shuffle, repeatMode: repeatMode };
    }

    // Loads a saved queue paused; returns false when none of it is in the library.
    function restore(s, tracks) {
        const byPath = {};
        for (const t of tracks)
            byPath[t.path] = t;
        const paths = Array.isArray(s.paths) ? s.paths : [];
        const current = paths[s.index];
        const restored = paths.filter(p => byPath[p] !== undefined).map(p => byPath[p]);
        if (restored.length === 0)
            return false;
        const i = restored.findIndex(t => t.path === current);
        queue = restored;
        index = i >= 0 ? i : 0;
        shuffle = s.shuffle === true;
        repeatMode = ["off", "all", "one"].indexOf(s.repeatMode) >= 0 ? s.repeatMode : "off";
        _resumeAt = i >= 0 && s.position > 0 ? s.position : 0;
        _autoplay = false;
        media.source = queue[index].path;
        return true;
    }

    function _play(i) {
        if (i < 0)
            return;
        index = i;
        _resumeAt = 0;
        _autoplay = true;
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
            else if (player.media.mediaStatus === MediaPlayer.LoadedMedia) {
                player._failures = 0;
                if (player._resumeAt > 0) {
                    player.media.position = player._resumeAt;
                    player._resumeAt = 0;
                }
            }
        }
        function onErrorOccurred() {
            player.failed(player.currentTrack);
            if (!player._autoplay)
                return;
            const i = ++player._failures < player.queue.length
                    ? Queue.next(player.queue.length, player.index, player.shuffle, player.repeatMode === "all", Math.random())
                    : -1;
            if (i < 0)
                player.media.stop();
            else
                player._play(i);
        }
    }
}
