import QtQml

QtObject {
    property bool active
    property bool playing
    property bool shuffle
    property string repeatMode
    property bool canGoNext
    property bool canGoPrevious
    property int trackId
    property string title
    property string artist
    property string album
    property string artUrl
    property real length
    property real position

    signal raiseRequested
    signal playRequested
    signal pauseRequested
    signal playPauseRequested
    signal stopRequested
    signal nextRequested
    signal previousRequested
    signal seekRequested(real position)
    signal shuffleRequested(bool shuffle)
    signal repeatModeRequested(string mode)
}
