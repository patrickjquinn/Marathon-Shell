import QtQuick
import QtTest
import "../Library.js" as Library

TestCase {
    name: "Library"

    readonly property var tracks: [
        { id: 1, path: "file:///m/a1.mp3", title: "Blue", artist: "Ava", album: "Sky", duration: 200, trackNumber: 2 },
        { id: 2, path: "file:///m/a2.mp3", title: "Azure", artist: "Ava", album: "Sky", duration: 61, trackNumber: 1 },
        { id: 3, path: "file:///m/b1.mp3", title: "Cold", artist: "Bo", album: "Ice", duration: 9, trackNumber: 1 },
        { id: 4, path: "file:///m/b2.mp3", title: "Dawn", artist: "Bo", album: "Hits", duration: 30, trackNumber: 1 },
        { id: 5, path: "file:///m/c1.mp3", title: "Echo", artist: "Cy", album: "Hits", duration: 30, trackNumber: 2 }
    ]

    function test_formatTime() {
        compare(Library.formatTime(0), "0:00");
        compare(Library.formatTime(9), "0:09");
        compare(Library.formatTime(61.7), "1:01");
        compare(Library.formatTime(-3), "0:00");
        compare(Library.formatTime(NaN), "0:00");
    }

    function test_artistsAreGroupedAndSorted() {
        const a = Library.artists(tracks.slice().reverse());
        compare(a.map(x => x.name), ["Ava", "Bo", "Cy"]);
        compare(a[0].trackCount, 2);
        compare(a[0].albumCount, 1);
        compare(a[1].albumCount, 2);
    }

    function test_albumsAcrossArtists() {
        const a = Library.albums(tracks);
        compare(a.map(x => x.name), ["Hits", "Ice", "Sky"]);
        compare(a[0].artist, "", "an album by several artists has no single artist");
        compare(a[0].trackCount, 2);
        compare(a[2].artist, "Ava");
    }

    function test_albumsOfArtist() {
        compare(Library.albums(tracks, "Bo").map(x => x.name), ["Hits", "Ice"]);
    }

    function test_albumTracksInTrackOrder() {
        compare(Library.albumTracks(tracks, "Sky").map(t => t.title), ["Azure", "Blue"]);
        compare(Library.albumTracks(tracks, "Hits", "Bo").map(t => t.title), ["Dawn"]);
    }

    function test_songsSortedByTitle() {
        compare(Library.songs(tracks).map(t => t.id), [2, 1, 3, 4, 5]);
    }

    function test_searchMatchesTitleArtistAlbum() {
        compare(Library.search(tracks, "ech").map(t => t.id), [5]);
        compare(Library.search(tracks, "  ava ").map(t => t.id), [2, 1]);
        compare(Library.search(tracks, "ICE").map(t => t.id), [3]);
        compare(Library.search(tracks, "").length, 0);
    }
}
