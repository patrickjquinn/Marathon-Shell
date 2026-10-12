import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import ".."

TestCase {
    name: "PlaylistPages"
    when: windowShown
    visible: true
    width: 540; height: 1140

    Component { id: libraryStub; LibraryStub {} }
    Component { id: mediaStub; MediaStub {} }
    Component { id: playerComponent; Player {} }
    Component {
        id: storeStub
        QtObject { property var value: "[]" }
    }
    Component {
        id: appComponent
        MusicApp { width: 540; height: 1140 }
    }

    function makeApp(playlists) {
        const app = createTemporaryObject(appComponent, this, {
            library: createTemporaryObject(libraryStub, this),
            playlistStore: createTemporaryObject(storeStub, this, { value: JSON.stringify(playlists) }),
            sessionStore: createTemporaryObject(storeStub, this, { value: "" }),
            player: createTemporaryObject(playerComponent, this, { media: createTemporaryObject(mediaStub, this) })
        });
        tryVerify(() => app.pageStack.currentPage !== null && app.pageStack.currentPage.status === PageStatus.Active);
        tryVerify(() => app.loaded);
        return app;
    }

    function push(app, page, props) {
        const depth = app.pageStack.depth;
        app.pageStack.push(Qt.resolvedUrl("../pages/" + page), props);
        tryCompare(app.pageStack, "depth", depth + 1);
        tryCompare(app.pageStack, "busy", false);
        return app.pageStack.currentPage;
    }

    function test_playlistSongsFollowEdits() {
        const app = makeApp([{ id: 1, name: "Run", paths: ["file:///m/3.mp3", "file:///m/1.mp3"] }]);
        const page = push(app, "SongsPage.qml", { music: app, title: "Run", playlistId: 1 });
        const view = findChild(page, "songsView");
        compare(view.count, 2);
        tryVerify(() => view.itemAtIndex(0) !== null);
        compare(view.itemAtIndex(0).track.title, "Dawn");
        app.savePlaylists([{ id: 1, name: "Run", paths: ["file:///m/1.mp3"] }]);
        compare(view.count, 1);
    }

    function test_addToExistingPlaylist() {
        const app = makeApp([{ id: 1, name: "Run", paths: [] }]);
        const page = push(app, "AddToPlaylistPage.qml", { music: app, track: app.tracks[1] });
        const view = findChild(page, "addToPlaylistView");
        tryVerify(() => view.itemAtIndex(0) !== null);
        view.itemAtIndex(0).clicked(null);
        compare(app.playlists[0].paths, ["file:///m/2.mp3"]);
        tryCompare(app.pageStack, "depth", 1);
    }

    function test_newPlaylistDialog() {
        const app = makeApp([]);
        const dialog = push(app, "NewPlaylistDialog.qml", { music: app, track: app.tracks[0] });
        verify(!dialog.canAccept);
        findChild(dialog, "nameField").text = "  Chill ";
        verify(dialog.canAccept);
        dialog.accept();
        tryCompare(app.pageStack, "depth", 1);
        compare(app.playlists.length, 1);
        compare(app.playlists[0].name, "Chill");
        compare(app.playlists[0].paths, ["file:///m/1.mp3"]);
    }

    function test_playlistsPlaceholder() {
        const app = makeApp([]);
        const page = push(app, "PlaylistsPage.qml", { music: app });
        compare(findChild(page, "playlistsView").count, 0);
    }
}
