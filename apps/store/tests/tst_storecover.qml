import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../cover"

TestCase {
    id: testCase

    name: "StoreCover"
    when: windowShown
    visible: true
    width: 300
    height: 480

    Component {
        id: backendComponent
        TestBackend {}
    }
    Component {
        id: coverComponent
        StoreCover {
            width: 300
            height: 480
        }
    }

    function makeCover() {
        const store = createTemporaryObject(backendComponent, testCase);
        return createTemporaryObject(coverComponent, testCase, { store: store });
    }

    function test_idle() {
        const cover = makeCover();
        compare(cover.mode, "idle");
        verify(findChild(cover, "coverPlaceholder").visible);
    }

    function test_updatesAvailable() {
        const cover = makeCover();
        cover.store.pendingUpdates = [{ "app_id": "org.example.A" }, { "app_id": "org.example.B" }];
        compare(cover.mode, "updates");
        verify(!findChild(cover, "coverPlaceholder").visible);
        compare(findChild(cover, "coverHeadline").value, "2");
        compare(findChild(cover, "coverHeadline").label, "updates available");
        findChild(cover, "updateAllAction").triggered();
        compare(cover.store.opened, ["marathon-store://update-all/x"]);
    }

    function test_installInProgress() {
        const cover = makeCover();
        const cache = {};
        cache["org.gnome.Maps"] = { "name": "Maps" };
        cover.store.appstreamCache = cache;
        cover.store.installApp("org.gnome.Maps");
        compare(cover.mode, "job");
        compare(findChild(cover, "coverHeadline").value, "Waiting");
        compare(findChild(cover, "coverHeadline").label, "Maps");
        const jobs = {};
        jobs["org.gnome.Maps"] = { "state": "installing", "percent": 42, "ts": 1 };
        cover.store.jobs = jobs;
        compare(findChild(cover, "coverHeadline").value, "42%");
    }

    function test_cancelFromCover() {
        const cover = makeCover();
        cover.store.installApp("org.gnome.Maps");
        findChild(cover, "cancelAction").triggered();
        compare(cover.store.opened[1], "marathon-store://cancel/org.gnome.Maps");
        compare(findChild(cover, "coverHeadline").value, "Cancelling");
    }
}
