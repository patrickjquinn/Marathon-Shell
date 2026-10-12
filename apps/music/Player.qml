import QtQuick
import QtMultimedia
import MarathonApp.Music 1.0
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

    readonly property url artUrl: {
        if (!currentTrack)
            return "";
        const loaded = media.source.toString() === currentTrack.path
                     && [MediaPlayer.LoadedMedia, MediaPlayer.BufferingMedia, MediaPlayer.BufferedMedia].indexOf(media.mediaStatus) >= 0;
        const embedded = loaded && media.metaData
                       ? media.metaData.value(MediaMetaData.CoverArtImage) || media.metaData.value(MediaMetaData.ThumbnailImage)
                       : undefined;
        const cached = embedded ? Artwork.cache(embedded, currentTrack.path) : "";
        return cached.toString() !== "" ? cached : Artwork.folderArt(currentTrack.path);
    }

    property real _resumeAt: 0

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
        media.source = queue[index].path;
        return true;
    }

    function _play(i) {
        if (i < 0)
            return;
        index = i;
        _resumeAt = 0;
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
            else if (player.media.mediaStatus === MediaPlayer.LoadedMedia && player._resumeAt > 0) {
                player.media.position = player._resumeAt;
                player._resumeAt = 0;
            }
        }
        function onErrorOccurred() {
            player.failed(player.currentTrack);
        }
    }
}
