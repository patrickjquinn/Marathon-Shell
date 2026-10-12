pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import MarathonOS.Shell
import Marathon.Platform 1.0
import Nemo.Configuration 1.0
import "Library.js" as Library
import "Playlists.js" as Playlists
import "pages"
import "cover"

ApplicationWindow {
    id: app

    // MusicLibraryManager is registered only for apps granted storage.
    property QtObject library: typeof MusicLibraryManager !== "undefined" ? MusicLibraryManager : null
    property var tracks: []
    property bool loaded: library === null
    readonly property bool scanning: library !== null && library.isScanning
    readonly property int artistCount: Library.artists(tracks).length
    readonly property int albumCount: Library.albums(tracks).length

    property QtObject playlistStore: ConfigurationValue {
        key: "/apps/music/playlists"
        defaultValue: "[]"
    }
    readonly property var playlists: Playlists.parse(playlistStore.value)
    function savePlaylists(next) {
        playlistStore.value = JSON.stringify(next);
    }

    property QtObject sessionStore: ConfigurationValue {
        key: "/apps/music/session"
        defaultValue: ""
    }
    // Keeps playback running while the app is in the background.
    property int _backgroundTask: 0
    function _holdBackground(hold) {
        if (hold && _backgroundTask === 0)
            _backgroundTask = Lifecycle.beginBackgroundTask("audio-playback", "playing music");
        else if (!hold && _backgroundTask !== 0) {
            Lifecycle.endBackgroundTask(_backgroundTask);
            _backgroundTask = 0;
        }
    }

    function saveSession() {
        if (player.currentTrack)
            sessionStore.value = JSON.stringify(player.snapshot());
    }
    function _savedSession() {
        try {
            return JSON.parse(sessionStore.value) || {};
        } catch (e) {
            return {};
        }
    }

    property Player player: Player {
        onFailed: track => Notices.show(qsTr("Can't play “%1”. The file may be missing or in an unsupported format.")
                                        .arg(track ? track.title : ""))
    }

    readonly property bool playerPageActive: pageStack.currentPage !== null && pageStack.currentPage.objectName === "playerPage"

    function reload() {
        if (library)
            library.loadTracksAsync();
    }

    function openPlayer() {
        if (!playerPageActive)
            pageStack.push(Qt.resolvedUrl("pages/PlayerPage.qml"), { music: app });
    }

    appId: "music"

    Component.onCompleted: {
        if (!library)
            return;
        reload();
        library.scanLibraryAsync();
    }

    Connections {
        target: app.player
        function onCurrentTrackChanged() {
            app.saveSession();
        }
        function onPlayingChanged() {
            app.saveSession();
            app._holdBackground(app.player.playing);
        }
    }

    Connections {
        target: Qt.application
        function onStateChanged() {
            if (Qt.application.state !== Qt.ApplicationActive)
                app.saveSession();
        }
    }

    Component.onDestruction: saveSession()

    Connections {
        target: app.library
        function onTracksLoaded(list) {
            app.tracks = list;
            if (!app.loaded && !app.player.currentTrack)
                app.player.restore(app._savedSession(), list);
            app.loaded = true;
        }
        function onLibraryChanged() {
            app.reload();
        }
    }

    NowPlayingPanel {
        id: panel
        objectName: "nowPlayingPanel"
        music: app
    }

    // Delayed: bound directly, the window's resize loops back into visibleSize.
    Binding {
        target: app
        property: "bottomMargin"
        value: panel.visibleSize
        delayed: true
    }

    Binding {
        target: panel
        property: "open"
        value: app.player.currentTrack !== null && !app.playerPageActive
    }

    cover: Component {
        MusicCover {
            track: app.player.currentTrack
            playing: app.player.playing
            progress: app.player.duration > 0 ? app.player.position / app.player.duration : 0
            onToggleRequested: app.player.toggle()
            onNextRequested: app.player.next()
        }
    }

    initialPage: Component {
        MainPage {
            music: app
        }
    }
}
