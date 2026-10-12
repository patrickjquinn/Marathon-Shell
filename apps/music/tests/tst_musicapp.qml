import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import ".."

TestCase {
    name: "MusicApp"
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

    function makeApp(library) {
        const props = {
            playlistStore: createTemporaryObject(storeStub, this),
            player: createTemporaryObject(playerComponent, this, { media: createTemporaryObject(mediaStub, this) })
        };
        if (library !== null)
            props.library = library === undefined ? createTemporaryObject(libraryStub, this) : library;
        else
            props.library = null;
        const app = createTemporaryObject(appComponent, this, props);
        tryVerify(() => app.pageStack.currentPage !== null && app.pageStack.currentPage.status === PageStatus.Active);
        return app;
    }

    function mainView(app) {
        return findChild(app.pageStack.currentPage, "mainView");
    }

    function panel(app) {
        return findChild(app, "nowPlayingPanel");
    }

    function test_loadsLibraryAndScans() {
        const app = makeApp();
        compare(app.tracks.length, 3);
        compare(app.library.scans, 1);
        app.library.tracks = app.library.tracks.slice(0, 1);
        app.library.scanComplete(1);
        compare(app.tracks.length, 1);
    }

    function test_categoriesWithCounts() {
        const app = makeApp();
        const categories = findChild(app.pageStack.currentPage, "categories");
        compare(categories.count, 4);
        compare(categories.itemAt(0).modelData.count, 2, "artists");
        compare(categories.itemAt(1).modelData.count, 2, "albums");
        compare(categories.itemAt(2).modelData.count, 3, "songs");
        compare(categories.itemAt(3).modelData.count, 0, "playlists");
    }

    function test_categoryOpensList() {
        const app = makeApp();
        const categories = findChild(app.pageStack.currentPage, "categories");
        categories.itemAt(0).clicked(null);
        tryCompare(app.pageStack, "depth", 2);
        compare(app.pageStack.currentPage.music, app);
        compare(findChild(app.pageStack.currentPage, "pageHeader").title, "Artists");
    }

    function test_unavailableLibrary() {
        const app = makeApp(null);
        compare(app.tracks.length, 0);
        const placeholder = findChild(app.pageStack.currentPage, "placeholder");
        verify(placeholder.enabled);
        compare(placeholder.text, "Music library unavailable");
    }

    function test_emptyLibrary() {
        const library = createTemporaryObject(libraryStub, this, { tracks: [] });
        const app = makeApp(library);
        const placeholder = findChild(app.pageStack.currentPage, "placeholder");
        verify(placeholder.enabled);
        compare(placeholder.text, "No music yet");
        compare(findChild(app.pageStack.currentPage, "categories").count, 0);
    }

    function test_searchListsMatchingSongs() {
        const app = makeApp();
        const page = app.pageStack.currentPage;
        findChild(page, "searchField").text = "bo";
        compare(mainView(app).count, 2);
        compare(findChild(page, "categories").count, 0);
        findChild(page, "searchField").text = "zzz";
        compare(mainView(app).count, 0);
        verify(findChild(page, "placeholder").enabled);
        compare(findChild(page, "placeholder").text, "No matches");
    }

    function test_tappingASongPlaysTheResults() {
        const app = makeApp();
        findChild(app.pageStack.currentPage, "searchField").text = "bo";
        const view = mainView(app);
        tryVerify(() => view.itemAtIndex(1) !== null);
        view.itemAtIndex(1).clicked(null);
        compare(app.player.currentTrack.title, "Dawn");
        compare(app.player.queue.length, 2);
        verify(app.player.playing);
    }

    function test_panelHiddenUntilSomethingPlays() {
        const app = makeApp();
        verify(!panel(app).open);
        app.player.playTracks(app.tracks, 0);
        verify(panel(app).open);
    }

    function test_panelControls() {
        const app = makeApp();
        app.player.playTracks(app.tracks, 0);
        const p = panel(app);
        findChild(p, "panelPlayPause").clicked(null);
        verify(!app.player.playing);
        findChild(p, "panelPlayPause").clicked(null);
        verify(app.player.playing);
        findChild(p, "panelNext").clicked(null);
        compare(app.player.currentTrack.title, "Cold");
        findChild(p, "panelPrevious").clicked(null);
        compare(app.player.currentTrack.title, "Blue");
    }

    function test_panelSliderSeeks() {
        const app = makeApp();
        app.player.playTracks(app.tracks, 0);
        const slider = findChild(panel(app), "panelSlider");
        compare(slider.maximumValue, 200000);
        app.player.media.position = 50000;
        compare(slider.value, 50000);
        slider.forceActiveFocus();
        keyClick(Qt.Key_Right);
        compare(app.player.media.position, 60000);
        app.player.media.position = 61000;
        compare(slider.value, 61000, "playback alone does not seek");
        compare(app.player.media.position, 61000);
    }

    function test_playerSliderSeeks() {
        const app = makeApp();
        app.player.playTracks(app.tracks, 0);
        app.openPlayer();
        tryCompare(app.pageStack, "depth", 2);
        tryCompare(app.pageStack, "busy", false);
        const slider = findChild(app.pageStack.currentPage, "playerSlider");
        slider.value = 100000;
        compare(app.player.media.position, 100000);
    }

    function test_panelOpensPlayerAndHidesThere() {
        const app = makeApp();
        app.player.playTracks(app.tracks, 1);
        findChild(app, "panelDetails").clicked(null);
        tryCompare(app.pageStack, "depth", 2);
        compare(app.pageStack.currentPage.objectName, "playerPage");
        verify(!panel(app).open);
        compare(findChild(app.pageStack.currentPage, "playerTitle").text, "Cold");
        app.openPlayer();
        compare(app.pageStack.depth, 2, "no second player page");
        app.pageStack.pop();
        tryCompare(app.pageStack, "depth", 1);
        tryVerify(() => panel(app).open);
    }

    function test_playerPageControls() {
        const app = makeApp();
        app.player.playTracks(app.tracks, 0);
        app.openPlayer();
        tryCompare(app.pageStack, "depth", 2);
        const page = app.pageStack.currentPage;
        findChild(page, "nextButton").clicked(null);
        compare(app.player.currentTrack.title, "Cold");
        findChild(page, "previousButton").clicked(null);
        compare(app.player.currentTrack.title, "Blue");
        findChild(page, "playPauseButton").clicked(null);
        verify(!app.player.playing);
        findChild(page, "shuffleButton").clicked(null);
        verify(app.player.shuffle);
        findChild(page, "repeatButton").clicked(null);
        compare(app.player.repeatMode, "all");
    }

    function test_playbackErrorKeepsTrack() {
        const app = makeApp();
        app.player.playTracks(app.tracks, 0);
        app.player.media.errorOccurred(1, "unsupported");
        compare(app.player.currentTrack.title, "Blue");
    }

    function test_playlistsPersist() {
        const app = makeApp();
        app.savePlaylists([{ id: 1, name: "Run", paths: ["file:///m/2.mp3"] }]);
        compare(JSON.parse(app.playlistStore.value)[0].name, "Run");
        compare(app.playlists.length, 1);
        compare(findChild(app.pageStack.currentPage, "categories").itemAt(3).modelData.count, 1);
    }

    function test_corruptPlaylistsStartEmpty() {
        const app = makeApp();
        app.playlistStore.value = "{bad";
        compare(app.playlists.length, 0);
    }
}
