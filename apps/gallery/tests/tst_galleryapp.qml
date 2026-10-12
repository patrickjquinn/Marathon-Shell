import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
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
        GalleryApp { width: 720; height: 1440 }
    }

    function photo(id, album) {
        return { id: id, path: Qt.resolvedUrl("data/photo" + (id % 3 + 1) + ".png").toString(), thumbnailPath: "",
                 album: album, width: 48, height: 36, timestamp: new Date(2026, 0, id).getTime() };
    }

    function makeApp(photos) {
        MediaLibrary.photos = photos;
        MediaLibrary.albums = [{ id: "Trip", name: "Trip", photoCount: 2 }, { id: "Camera Roll", name: "Camera Roll", photoCount: 1 }];
        MediaLibrary.deleted = [];
        const app = createTemporaryObject(appComponent, testCase);
        tryVerify(function () { return app.photos.length === photos.length; });
        tryVerify(function () { return app.pageStack.currentPage !== null; });
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

    function test_openingAlbumShowsItsPhotos() {
        const app = makeApp(threePhotos());
        app.pageStack.currentPage.open({ kind: "album", albumId: "Trip", name: "Trip" });
        tryCompare(app.pageStack, "busy", false);
        const page = app.pageStack.currentPage;
        compare(page.title, "Trip");
        compare(page.photos.map(p => p.id), [1, 3]);
        tryCompare(findChild(page, "grid"), "count", 2);
    }

    function test_searchFiltersAllPhotos() {
        const app = makeApp(threePhotos());
        app.pageStack.currentPage.open({ kind: "all" });
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
        app.pageStack.currentPage.open({ kind: "all" });
        tryCompare(app.pageStack, "busy", false);
        const grid = findChild(app.pageStack.currentPage, "grid");
        tryCompare(grid, "count", 3);
        const second = grid.itemAtIndex(1);
        mouseClick(second);
        tryCompare(app.pageStack, "busy", false);
        const viewer = app.pageStack.currentPage;
        compare(viewer.currentIndex, 1);
        compare(viewer.photo.id, 2);
    }

    function test_deletingLastAlbumPhotoReturnsToMain() {
        const app = makeApp([photo(1, "Trip"), photo(2, "Camera Roll")]);
        app.pageStack.currentPage.open({ kind: "album", albumId: "Camera Roll", name: "Camera Roll" });
        tryCompare(app.pageStack, "busy", false);
        compare(app.pageStack.depth, 2);
        app.deletePhoto(2);
        compare(MediaLibrary.deleted, [2]);
        tryCompare(app.pageStack, "depth", 1);
    }
}
