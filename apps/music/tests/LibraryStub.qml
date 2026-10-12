import QtQuick

QtObject {
    id: library

    property bool isScanning: false
    property int scanProgress: 0
    property var tracks: [
        { id: 1, path: "file:///m/1.mp3", title: "Blue", artist: "Ava", album: "Sky", duration: 200, trackNumber: 1 },
        { id: 2, path: "file:///m/2.mp3", title: "Cold", artist: "Bo", album: "Ice", duration: 61, trackNumber: 1 },
        { id: 3, path: "file:///m/3.mp3", title: "Dawn", artist: "Bo", album: "Ice", duration: 30, trackNumber: 2 }
    ]
    property int scans: 0
    property int loads: 0
    property bool deliver: true

    signal scanComplete(int trackCount)
    signal libraryChanged
    signal tracksLoaded(var tracks)

    function loadTracksAsync() {
        loads++;
        if (deliver)
            Qt.callLater(() => library.tracksLoaded(library.tracks));
    }
    function scanLibraryAsync() {
        scans++;
    }
}
