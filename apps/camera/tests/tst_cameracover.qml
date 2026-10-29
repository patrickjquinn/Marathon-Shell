import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../cover"

TestCase {
    name: "CameraCover"
    when: windowShown
    visible: true
    width: 540
    height: 960

    Component {
        id: cover
        CameraCover {}
    }

    function test_placeholderWithoutPhoto() {
        const c = createTemporaryObject(cover, this);
        verify(findChild(c, "coverPlaceholder").visible);
        verify(!findChild(c, "coverImage").visible);
    }

    function test_showsLastPhoto() {
        const photo = Qt.resolvedUrl("data/photo.png").toString();
        const c = createTemporaryObject(cover, this, {
            photo: photo
        });
        verify(!findChild(c, "coverPlaceholder").visible);
        verify(findChild(c, "coverImage").visible);
        compare(String(findChild(c, "coverImage").source), photo);
    }

    function test_noCoverActions() {
        const c = createTemporaryObject(cover, this);
        compare(findChild(c, "captureAction"), null);
    }
}
