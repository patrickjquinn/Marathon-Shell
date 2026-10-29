import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Sailfish.Share 1.0
import Marathon.Platform 1.0
import ".."

TestCase {
    id: testCase

    name: "PhotoViewerPage"
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

    function photo(id) {
        return {
            id: id,
            path: Qt.resolvedUrl("data/photo" + id + ".png").toString(),
            thumbnailPath: "",
            album: "Trip",
            width: 48,
            height: 36,
            timestamp: new Date(2026, 0, id).getTime()
        };
    }

    function openViewer(index) {
        MediaLibrary.photos = [photo(1), photo(2), photo(3)];
        MediaLibrary.deleted = [];
        const app = createTemporaryObject(appComponent, testCase);
        tryVerify(function () {
            return app.photos.length === 3 && app.pageStack.currentPage !== null;
        });
        app.pageStack.push(Qt.resolvedUrl("../pages/PhotoViewerPage.qml"), {
            store: app,
            photos: app.photos,
            currentIndex: index
        });
        tryCompare(app.pageStack, "busy", false);
        return {
            app: app,
            page: app.pageStack.currentPage
        };
    }

    function test_startsAtGivenPhoto() {
        const t = openViewer(2);
        compare(t.page.currentIndex, 2);
        compare(t.page.photo.id, 3);
        compare(t.app.viewerPhoto.id, 3);
    }

    function test_keysStepThroughPhotos() {
        const t = openViewer(0);
        tryVerify(function () {
            return t.page.activeFocus;
        });
        keyClick(Qt.Key_Right);
        compare(t.page.photo.id, 2);
        compare(t.app.viewerPhoto.id, 2);
        keyClick(Qt.Key_Left);
        keyClick(Qt.Key_Left);
        compare(t.page.photo.id, 3);
    }

    function test_swipeMovesToNextPhoto() {
        const t = openViewer(0);
        const view = findChild(t.page, "slideshow");
        mouseDrag(view, view.width * 0.8, view.height / 2, -view.width * 0.6, 0);
        tryCompare(view, "moving", false, 3000);
        compare(t.page.photo.id, 2);
    }

    function test_pullingDownOpensActions() {
        const t = openViewer(0);
        const menu = findChild(t.page, "menu");
        const x = t.page.width / 2;
        mousePress(t.page, x, 200);
        for (let y = 220; y <= 700; y += 40)
            mouseMove(t.page, x, y, 16);
        verify(menu.active);
        mouseRelease(t.page, x, 700);
        compare(t.page.photo.id, 1);
    }

    function test_tapTogglesOverlay() {
        const t = openViewer(0);
        verify(t.page.overlayShown);
        mouseClick(t.page, t.page.width / 2, t.page.height / 2);
        tryVerify(function () {
            return !t.page.overlayShown;
        }, 2000);
    }

    function test_deleteWaitsForRemorseThenRemoves() {
        const t = openViewer(1);
        findChild(t.page, "deleteAction").clicked();
        const remorse = findChild(t.page, "remorse");
        verify(remorse.pending);
        compare(MediaLibrary.deleted, []);
        remorse.trigger();
        compare(MediaLibrary.deleted, [2]);
        compare(t.page.photos.map(p => p.id), [1, 3]);
        compare(t.page.photo.id, 3);
        compare(t.app.photos.length, 2);
    }

    function test_cancelledDeleteKeepsPhoto() {
        const t = openViewer(0);
        findChild(t.page, "deleteAction").clicked();
        const remorse = findChild(t.page, "remorse");
        remorse.cancel();
        wait(50);
        compare(MediaLibrary.deleted, []);
        compare(t.page.photos.length, 3);
    }

    function test_deletingOnlyPhotoClosesViewer() {
        MediaLibrary.photos = [photo(1)];
        MediaLibrary.deleted = [];
        const app = createTemporaryObject(appComponent, testCase);
        tryVerify(function () {
            return app.photos.length === 1 && app.pageStack.currentPage !== null;
        });
        app.pageStack.push(Qt.resolvedUrl("../pages/PhotoViewerPage.qml"), {
            store: app,
            photos: app.photos,
            currentIndex: 0
        });
        tryCompare(app.pageStack, "busy", false);
        findChild(app.pageStack.currentPage, "deleteAction").clicked();
        findChild(app.pageStack.currentPage, "remorse").trigger();
        tryCompare(app.pageStack, "depth", 1);
    }

    function test_shareOnlyWithAShareService() {
        const t = openViewer(0);
        compare(findChild(t.page, "shareAction").visible, KeelShareService.available());
    }

    function test_detailsShowPhotoFacts() {
        const t = openViewer(0);
        findChild(t.page, "detailsAction").clicked();
        tryCompare(t.app.pageStack, "busy", false);
        const details = t.app.pageStack.currentPage;
        verify(findChild(details, "pathDetail").value.endsWith("/tests/data/photo1.png"));
        compare(findChild(details, "resolutionDetail").value, "48 × 36");
        verify(findChild(details, "dateDetail").visible);
        compare(t.app.viewerPhoto.id, 1);
    }
}
