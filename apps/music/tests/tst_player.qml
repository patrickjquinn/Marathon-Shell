import QtQuick
import QtTest
import QtMultimedia
import MarathonApp.Music 1.0
import ".."

TestCase {
    name: "Player"

    readonly property var tracks: [
        { id: 1, path: "file:///m/1.mp3", title: "One", artist: "A", album: "X", duration: 100 },
        { id: 2, path: "file:///m/2.mp3", title: "Two", artist: "A", album: "X", duration: 100 },
        { id: 3, path: "file:///m/3.mp3", title: "Three", artist: "A", album: "X", duration: 100 }
    ]

    Component { id: mediaStub; MediaStub {} }
    Component { id: playerComponent; Player {} }
    SignalSpy { id: failedSpy; signalName: "failed" }

    function makePlayer() {
        const media = createTemporaryObject(mediaStub, this);
        return createTemporaryObject(playerComponent, this, { media: media });
    }

    function test_idle() {
        const p = makePlayer();
        compare(p.currentTrack, null);
        verify(!p.playing);
        p.toggle();
        compare(p.media.plays, 0);
    }

    function test_playTracksStartsAtIndex() {
        const p = makePlayer();
        p.playTracks(tracks, 1);
        compare(p.currentTrack.title, "Two");
        compare(p.media.source, "file:///m/2.mp3");
        verify(p.playing);
    }

    function test_toggle() {
        const p = makePlayer();
        p.playTracks(tracks, 0);
        p.toggle();
        verify(!p.playing);
        p.toggle();
        verify(p.playing);
    }

    function test_nextAndPreviousWrap() {
        const p = makePlayer();
        p.playTracks(tracks, 2);
        p.next();
        compare(p.currentTrack.title, "One");
        p.previous();
        compare(p.currentTrack.title, "Three");
    }

    function test_endOfMediaAdvances() {
        const p = makePlayer();
        p.playTracks(tracks, 0);
        p.media.mediaStatus = MediaPlayer.EndOfMedia;
        compare(p.currentTrack.title, "Two");
    }

    function test_endOfQueueStopsUnlessRepeating() {
        const p = makePlayer();
        p.playTracks(tracks, 2);
        p.media.mediaStatus = MediaPlayer.EndOfMedia;
        compare(p.currentTrack.title, "Three");
        verify(!p.playing);

        p.repeatMode = "all";
        p.playTracks(tracks, 2);
        p.media.mediaStatus = MediaPlayer.LoadedMedia;
        p.media.mediaStatus = MediaPlayer.EndOfMedia;
        compare(p.currentTrack.title, "One");
    }

    function test_repeatOneReplays() {
        const p = makePlayer();
        p.repeatMode = "one";
        p.playTracks(tracks, 1);
        const plays = p.media.plays;
        p.media.mediaStatus = MediaPlayer.EndOfMedia;
        compare(p.currentTrack.title, "Two");
        compare(p.media.plays, plays + 1);
    }

    function test_cycleRepeat() {
        const p = makePlayer();
        compare(p.repeatMode, "off");
        p.cycleRepeat();
        compare(p.repeatMode, "all");
        p.cycleRepeat();
        compare(p.repeatMode, "one");
        p.cycleRepeat();
        compare(p.repeatMode, "off");
    }

    function test_enqueueAppends() {
        const p = makePlayer();
        p.playTracks(tracks.slice(0, 2), 1);
        p.enqueue(tracks[2]);
        compare(p.queue.length, 3);
        compare(p.queue[2].title, "Three");
        compare(p.currentTrack.title, "Two", "the current track keeps playing");
        p.next();
        compare(p.currentTrack.title, "Three");
    }

    function test_enqueueStartsAnIdlePlayer() {
        const p = makePlayer();
        p.enqueue(tracks[1]);
        compare(p.currentTrack.title, "Two");
        verify(p.playing);
    }

    function test_seekAndDuration() {
        const p = makePlayer();
        p.playTracks(tracks, 0);
        compare(p.duration, 100000, "falls back to the library's duration");
        p.media.duration = 123000;
        compare(p.duration, 123000);
        p.seek(5000);
        compare(p.position, 5000);
    }

    function test_errorReportsTrack() {
        const p = makePlayer();
        failedSpy.target = p;
        failedSpy.clear();
        p.playTracks(tracks, 0);
        p.media.errorOccurred(1, "boom");
        compare(failedSpy.count, 1);
        compare(failedSpy.signalArguments[0][0].title, "One");
    }

    function test_snapshotRestoresPaused() {
        const p = makePlayer();
        p.playTracks(tracks, 1);
        p.shuffle = true;
        p.repeatMode = "one";
        p.media.position = 42000;
        const saved = JSON.parse(JSON.stringify(p.snapshot()));
        compare(saved.paths, ["file:///m/1.mp3", "file:///m/2.mp3", "file:///m/3.mp3"]);

        const r = makePlayer();
        verify(r.restore(saved, tracks.slice().reverse()));
        compare(r.queue.map(t => t.title), ["One", "Two", "Three"]);
        compare(r.currentTrack.title, "Two");
        compare(r.media.source, "file:///m/2.mp3");
        verify(!r.playing);
        compare(r.media.plays, 0);
        verify(r.shuffle);
        compare(r.repeatMode, "one");
        r.media.mediaStatus = MediaPlayer.LoadedMedia;
        compare(r.media.position, 42000);
    }

    function test_restoreSkipsMissingTracks() {
        const p = makePlayer();
        verify(p.restore({ paths: ["file:///gone.mp3", "file:///m/3.mp3"], index: 1, position: 0 }, tracks));
        compare(p.queue.length, 1);
        compare(p.currentTrack.title, "Three");
        verify(!p.restore({ paths: ["file:///gone.mp3"], index: 0 }, tracks));
        verify(!makePlayer().restore({}, tracks));
    }

    function test_artFromTheFolder() {
        const p = makePlayer();
        compare(p.artUrl, "");
        Artwork.folders = { "file:///m/2.mp3": "file:///m/cover.jpg" };
        p.playTracks(tracks, 1);
        compare(p.artUrl, "file:///m/cover.jpg");
        p.next();
        compare(p.artUrl, "");
        Artwork.folders = {};
    }
}
