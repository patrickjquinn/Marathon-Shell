import QtQuick
import QtTest
import "../Playlists.js" as Playlists

TestCase {
    name: "Playlists"

    function test_parseBad() {
        compare(Playlists.parse("{nope").length, 0);
        compare(Playlists.parse("{}").length, 0);
        compare(Playlists.parse("").length, 0);
    }

    function test_createAssignsIds() {
        let p = Playlists.create([], "Run");
        p = Playlists.create(p, "Chill");
        compare(p.map(x => x.name), ["Run", "Chill"]);
        verify(p[0].id !== p[1].id);
        compare(p[0].paths.length, 0);
    }

    function test_addTrackOnce() {
        let p = Playlists.create([], "Run");
        const id = p[0].id;
        p = Playlists.addTrack(p, id, "file:///a.mp3");
        p = Playlists.addTrack(p, id, "file:///a.mp3");
        p = Playlists.addTrack(p, id, "file:///b.mp3");
        compare(p[0].paths, ["file:///a.mp3", "file:///b.mp3"]);
    }

    function test_removeTrackAndPlaylist() {
        let p = Playlists.addTrack(Playlists.create([], "Run"), 1, "file:///a.mp3");
        p = Playlists.removeTrack(p, 1, "file:///a.mp3");
        compare(p[0].paths.length, 0);
        compare(Playlists.remove(p, 1).length, 0);
    }

    function test_tracksOfKeepsOrderAndDropsMissing() {
        const tracks = [{ path: "file:///a.mp3", title: "A" }, { path: "file:///b.mp3", title: "B" }];
        const list = { id: 1, name: "x", paths: ["file:///b.mp3", "file:///gone.mp3", "file:///a.mp3"] };
        compare(Playlists.tracksOf(list, tracks).map(t => t.title), ["B", "A"]);
    }

    function test_inputIsNotMutated() {
        const p = Playlists.create([], "Run");
        Playlists.addTrack(p, p[0].id, "file:///a.mp3");
        compare(p[0].paths.length, 0);
    }
}
