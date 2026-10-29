import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import Keel.Actions 1.0
import ".."

TestCase {
    id: testCase

    name: "GalleryApp"
    when: windowShown
    visible: true
    width: 720
    height: 1440

    Component {
        id: appComponent
        GalleryApp {
            width: 720
            height: 1440
        }
    }

    function photo(id, album) {
        return {
            id: id,
            path: Qt.resolvedUrl("data/photo" + (id % 3 + 1) + ".png").toString(),
            thumbnailPath: "",
            album: album,
            width: 48,
            height: 36,
            timestamp: new Date(2026, 0, id).getTime()
        };
    }

    function video(id) {
        return {
            id: id,
            path: "file:///videos/VID_" + id + ".mp4",
            thumbnailPath: "",
            timestamp: new Date(2026, 0, id).getTime()
        };
    }

    function makeApp(photos, videos) {
        MediaLibrary.photos = photos;
        MediaLibrary.videos = videos || [];
        MediaLibrary.albums = [
            {
                id: "Trip",
                name: "Trip",
                photoCount: 2
            },
            {
                id: "Camera Roll",
                name: "Camera Roll",
                photoCount: 1
            }
        ];
        MediaLibrary.deleted = [];
        const app = createTemporaryObject(appComponent, testCase);
        tryVerify(function () {
            return app.photos.length === photos.length;
        });
        tryVerify(function () {
            return app.pageStack.currentPage !== null;
        });
        return app;
    }

    function threePhotos() {
        return [photo(1, "Trip"), photo(2, "Camera Roll"), photo(3, "Trip")];
    }

    function test_scansAndLoadsOnStart() {
        const scans = MediaLibrary.scans;
        const app = makeApp(threePhotos());
        compare(MediaLibrary.scans, scans + 1);
        compare(app.photos.length, 3);
    }

    function test_refreshesWhenLibraryChanges() {
        const app = makeApp(threePhotos());
        MediaLibrary.photos = [photo(7, "Trip")];
        MediaLibrary.libraryChanged();
        compare(app.photos.length, 1);
        MediaLibrary.photos = threePhotos();
        MediaLibrary.scanComplete(3, 0);
        compare(app.photos.length, 3);
    }

    function test_mainPageListsPhotosAndAlbums() {
        const app = makeApp(threePhotos());
        const list = findChild(app.pageStack.currentPage, "collections");
        tryCompare(list, "count", 3);
        verify(!findChild(app.pageStack.currentPage, "placeholder").enabled);
    }

    function test_mainPagePlaceholderWhenEmpty() {
        const app = makeApp([]);
        const list = findChild(app.pageStack.currentPage, "collections");
        compare(list.count, 0);
        verify(findChild(app.pageStack.currentPage, "placeholder").enabled);
    }

    function test_scanningShowsBusyNotEmpty() {
        MediaLibrary.isScanning = true;
        const app = makeApp([]);
        verify(findChild(app.pageStack.currentPage, "busyLabel").running);
        verify(!findChild(app.pageStack.currentPage, "placeholder").enabled);
        MediaLibrary.isScanning = false;
        verify(!findChild(app.pageStack.currentPage, "busyLabel").running);
        verify(findChild(app.pageStack.currentPage, "placeholder").enabled);
    }

    function test_rowsLeadWithTheItemCount() {
        const app = makeApp(threePhotos(), [video(2)]);
        const list = findChild(app.pageStack.currentPage, "collections");
        tryCompare(list, "count", 4);
        tryVerify(() => list.itemAtIndex(1) !== null);
        compare(findChild(list.itemAtIndex(0), "rowCount").text, "4");
        compare(findChild(list.itemAtIndex(1), "rowCount").text, "1");
    }

    function test_openingAlbumShowsItsPhotos() {
        const app = makeApp(threePhotos());
        app.pageStack.currentPage.open({
            kind: "album",
            albumId: "Trip",
            name: "Trip"
        });
        tryCompare(app.pageStack, "busy", false);
        const page = app.pageStack.currentPage;
        compare(page.title, "Trip");
        compare(page.photos.map(p => p.id), [1, 3]);
        tryCompare(findChild(page, "grid"), "count", 2);
    }

    function test_searchFiltersAllPhotos() {
        const app = makeApp(threePhotos());
        app.pageStack.currentPage.open({
            kind: "all"
        });
        tryCompare(app.pageStack, "busy", false);
        const page = app.pageStack.currentPage;
        findChild(page, "searchAction").clicked();
        verify(page.searching);
        const field = findChild(page, "searchField");
        verify(field.visible);
        field.text = "camera";
        compare(page.shown.map(p => p.id), [2]);
        tryCompare(findChild(page, "grid"), "count", 1);
        findChild(page, "searchAction").clicked();
        compare(page.shown.length, 3);
    }

    function test_tappingThumbnailOpensViewerAtIt() {
        const app = makeApp(threePhotos());
        app.pageStack.currentPage.open({
            kind: "all"
        });
        tryCompare(app.pageStack, "busy", false);
        const grid = findChild(app.pageStack.currentPage, "grid");
        tryCompare(grid, "count", 3);
        const second = grid.itemAtIndex(1);
        mouseClick(second);
        tryCompare(app.pageStack, "busy", false);
        const viewer = app.pageStack.currentPage;
        compare(viewer.currentIndex, 1);
        compare(viewer.photo.id, 2);
        compare(app.viewerPhoto.id, 2);
    }

    function test_showActionOpensViewer() {
        const app = makeApp(threePhotos());
        tryCompare(app.pageStack, "busy", false);
        const call = KeelActions.invoke("photos.show", {
            id: 3
        });
        verify(call.succeeded, call.errorMessage);
        tryCompare(app.pageStack, "busy", false);
        compare(app.pageStack.depth, 2);
        compare(app.viewerPhoto.id, 3);
    }

    function test_closingViewerClearsCoverPhoto() {
        const app = makeApp(threePhotos());
        app.pageStack.push(Qt.resolvedUrl("../pages/PhotoViewerPage.qml"), {
            store: app,
            photos: app.photos,
            currentIndex: 0
        });
        tryCompare(app.pageStack, "busy", false);
        compare(app.viewerPhoto.id, 1);
        app.pageStack.pop();
        tryCompare(app.pageStack, "busy", false);
        tryCompare(app, "viewerPhoto", null);
    }

    function test_deletingLastAlbumPhotoReturnsToMain() {
        const app = makeApp([photo(1, "Trip"), photo(2, "Camera Roll")]);
        app.pageStack.currentPage.open({
            kind: "album",
            albumId: "Camera Roll",
            name: "Camera Roll"
        });
        tryCompare(app.pageStack, "busy", false);
        compare(app.pageStack.depth, 2);
        app.deletePhoto(2);
        compare(MediaLibrary.deleted, [2]);
        tryCompare(app.pageStack, "depth", 1);
    }

    function openGrid(app, kind) {
        app.pageStack.currentPage.open({
            kind: kind
        });
        tryCompare(app.pageStack, "busy", false);
        return app.pageStack.currentPage;
    }

    function test_mainPageHasAVideosRow() {
        const app = makeApp(threePhotos(), [video(2)]);
        const list = findChild(app.pageStack.currentPage, "collections");
        tryCompare(list, "count", 4);
        compare(app.pageStack.currentPage.rowDetail(list.model[0]), "3 photos · 1 video");
        compare(app.pageStack.currentPage.rowTitle(list.model[1]), "Videos");
        compare(app.pageStack.currentPage.rowDetail(list.model[1]), "1 video");
    }

    function test_photosGridIncludesVideosNewestFirst() {
        const app = makeApp(threePhotos(), [video(2)]);
        const page = openGrid(app, "all");
        compare(page.shown.map(m => m.id), [3, 2, 2, 1]);
        verify(findChild(page, "grid"));
        tryCompare(findChild(page, "grid"), "count", 4);
    }

    function test_videosGridShowsOnlyVideos() {
        const app = makeApp(threePhotos(), [video(4), video(5)]);
        const page = openGrid(app, "videos");
        compare(page.shown.map(m => m.id), [4, 5]);
    }

    function test_tappingAVideoPlaysIt() {
        const app = makeApp(threePhotos(), [video(9)]);
        const grid = findChild(openGrid(app, "all"), "grid");
        tryCompare(grid, "count", 4);
        mouseClick(grid.itemAtIndex(0));
        tryCompare(app.pageStack, "busy", false);
        const player = app.pageStack.currentPage;
        compare(player.video.id, 9);
        compare(String(findChild(player, "player").source), "file:///videos/VID_9.mp4");
        verify(findChild(player, "playButton").visible);
        verify(findChild(player, "positionSlider").visible);
    }

    function test_longPressDeletesWithRemorse() {
        const app = makeApp(threePhotos());
        const grid = findChild(openGrid(app, "all"), "grid");
        tryCompare(grid, "count", 3);
        tryVerify(() => grid.itemAtIndex(0) !== null);
        const item = grid.itemAtIndex(0);
        const id = grid.model[0].id;
        item.openMenu();
        tryVerify(() => findChild(item, "deleteAction") !== null);
        findChild(item, "deleteAction").clicked();
        item.closeMenu();
        compare(MediaLibrary.deleted, [], "nothing deleted during the countdown");
        tryCompare(MediaLibrary, "deleted", [id], 8000);
        tryCompare(grid, "count", 2);
    }

    function test_videoThumbnailsAreMarked() {
        const withThumb = video(9);
        withThumb.thumbnailPath = Qt.resolvedUrl("data/photo1.png").toString();
        const app = makeApp(threePhotos(), [withThumb, video(2)]);
        const grid = findChild(openGrid(app, "videos"), "grid");
        tryCompare(grid, "count", 2);
        tryVerify(() => grid.itemAtIndex(1) !== null);
        verify(findChild(grid.itemAtIndex(0), "videoMark").visible);
        verify(!findChild(grid.itemAtIndex(1), "videoMark").visible, "Keel already shows a video icon without a thumbnail");
    }

    function test_tappingAPhotoBesideVideosOpensThatPhoto() {
        const app = makeApp(threePhotos(), [video(9)]);
        const grid = findChild(openGrid(app, "all"), "grid");
        tryCompare(grid, "count", 4);
        mouseClick(grid.itemAtIndex(2));
        tryCompare(app.pageStack, "busy", false);
        const viewer = app.pageStack.currentPage;
        compare(viewer.photos.length, 3);
        compare(viewer.photo.id, 2);
    }

    function test_deletingAVideoFromThePlayer() {
        const app = makeApp(threePhotos(), [video(9)]);
        app.pageStack.push(Qt.resolvedUrl("../pages/VideoPlayerPage.qml"), {
            store: app,
            video: app.videos[0]
        });
        tryCompare(app.pageStack, "busy", false);
        const player = app.pageStack.currentPage;
        findChild(player, "deleteAction").clicked();
        findChild(player, "remorse").trigger();
        compare(MediaLibrary.deleted, [9]);
        tryCompare(app.pageStack, "depth", 1);
        compare(app.videos.length, 0);
    }

    function test_playerPlaysAndPauses() {
        const app = makeApp(threePhotos());
        const clip = {
            id: 1,
            path: Qt.resolvedUrl("data/clip.mp4").toString(),
            timestamp: 0
        };
        app.pageStack.push(Qt.resolvedUrl("../pages/VideoPlayerPage.qml"), {
            store: app,
            video: clip
        });
        tryCompare(app.pageStack, "busy", false);
        const page = app.pageStack.currentPage;
        mouseClick(findChild(page, "playButton"));
        tryVerify(function () {
            return page.playing;
        }, 5000);
        tryVerify(function () {
            return findChild(page, "player").position > 0;
        }, 5000);
        compare(findChild(page, "player").duration, 2000);
        mouseClick(findChild(page, "playButton"));
        tryVerify(function () {
            return !page.playing;
        });
    }
}
