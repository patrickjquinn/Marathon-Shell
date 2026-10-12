import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../cover"

TestCase {
    id: testCase

    name: "GalleryCover"
    when: windowShown
    visible: true
    width: 540
    height: 960

    Component { id: cover; GalleryCover {} }

    function photo(id) {
        return { id: id, path: Qt.resolvedUrl("data/photo" + id + ".png").toString(), thumbnailPath: "" };
    }

    function test_placeholderWithoutPhotos() {
        const c = createTemporaryObject(cover, testCase, { photos: [] });
        verify(findChild(c, "coverPlaceholder").visible);
        verify(!findChild(c, "polaroid").visible);
    }

    function test_showsALibraryPhoto() {
        const ps = [photo(1), photo(2), photo(3)];
        const c = createTemporaryObject(cover, testCase, { photos: ps });
        verify(c.shownPhoto !== null);
        verify(ps.some(p => p.id === c.shownPhoto.id));
        verify(findChild(c, "polaroid").visible);
        verify(!findChild(c, "coverPlaceholder").visible, "no placeholder text behind the polaroid");
        compare(String(findChild(c, "coverImage").source), c.shownPhoto.path);
    }

    function test_openPhotoWins() {
        const c = createTemporaryObject(cover, testCase, { photos: [photo(1), photo(2)] });
        c.photo = photo(3);
        compare(c.shownPhoto.id, 3);
        c.photo = null;
        verify(c.shownPhoto.id !== 3);
    }

    function test_advancesOnlyWhileActive() {
        const c = createTemporaryObject(cover, testCase, { photos: [photo(1), photo(2)] });
        compare(c.status, Cover.Inactive);
        verify(!findChild(c, "advanceTimer").running);
        const before = c.shownPhoto.id;
        c.advance();
        verify(c.shownPhoto.id !== before);
    }

    function test_repicksWhenShownPhotoIsDeleted() {
        const c = createTemporaryObject(cover, testCase, { photos: [photo(1), photo(2)] });
        const gone = c.shownPhoto.id;
        c.photos = [photo(1), photo(2)].filter(p => p.id !== gone);
        verify(c.shownPhoto.id !== gone);
        c.photos = [];
        compare(c.shownPhoto, null);
    }
}
