pragma ComponentBehavior: Bound

import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import MarathonOS.Shell
import Nemo.Configuration 1.0
import "Playlists.js" as Playlists
import "pages"
import "cover"

ApplicationWindow {
    id: app

    // MusicLibraryManager is registered only for apps granted storage.
    property QtObject library: typeof MusicLibraryManager !== "undefined" ? MusicLibraryManager : null
    property var tracks: []
    readonly property bool scanning: library !== null && library.isScanning

    property QtObject playlistStore: ConfigurationValue {
        key: "/apps/music/playlists"
        defaultValue: "[]"
    }
    readonly property var playlists: Playlists.parse(playlistStore.value)
    function savePlaylists(next) {
        playlistStore.value = JSON.stringify(next);
    }

    property Player player: Player {
        onFailed: track => Notices.show(qsTr("Can't play “%1”. The file may be missing or in an unsupported format.")
                                        .arg(track ? track.title : ""))
    }

    readonly property bool playerPageActive: pageStack.currentPage !== null && pageStack.currentPage.objectName === "playerPage"

    function reload() {
        tracks = library ? library.getAllTracks() : [];
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
        target: app.library
        function onScanComplete() {
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
