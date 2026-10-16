pragma Singleton
import QtQml
QtObject {
    property bool hasActivePlayer: false
    property bool isPlaying: false
    property string playerName: ""
    property string desktopEntry: ""
    property string trackTitle: ""
    property string trackArtist: ""
    property string albumArtUrl: ""
    property real position: 0
    property real trackLength: 0
    property bool canGoPrevious: false
    property bool canGoNext: false
    property var calls: []

    function playPause() { calls.push("playPause"); isPlaying = !isPlaying; }
    function previous() { calls.push("previous"); }
    function next() { calls.push("next"); }
    function setPosition(p) { calls.push("setPosition"); }
}
