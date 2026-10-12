import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import ".."

TestCase {
    name: "NotesSilicaApp"
    when: windowShown

    Component {
        id: settingsStub
        QtObject {
            property var values: ({})
            function get(key, fallback) { return values[key] !== undefined ? values[key] : fallback; }
            function set(key, value) { values[key] = value; }
        }
    }
    Component {
        id: permissionsStub
        QtObject {
            property bool granted: true
            property int requests: 0
            signal permissionGranted(string appId, string permission)
            function hasPermission(appId, permission) { return granted; }
            function requestPermission(appId, permission) { requests++; }
        }
    }
    Component {
        id: appComponent
        NotesSilicaApp { width: 540; height: 1140 }
    }

    function makeApp(stored, granted) {
        const settings = createTemporaryObject(settingsStub, this);
        if (stored !== undefined)
            settings.values["notes-silica/data"] = stored;
        const permissions = createTemporaryObject(permissionsStub, this, { granted: granted });
        const app = createTemporaryObject(appComponent, this, { settings: settings, permissions: permissions });
        return { app: app, settings: settings, permissions: permissions };
    }

    function test_corruptDataStartsEmpty() {
        const t = makeApp("{not json", true);
        compare(t.app.notes.length, 0);
    }

    function test_loadsStoredNotes() {
        const t = makeApp(JSON.stringify([{ id: 3, title: "A", content: "", timestamp: 1 }]), true);
        compare(t.app.notes.length, 1);
        compare(t.app.notes[0].title, "A");
    }

    function test_saveWritesStorage() {
        const t = makeApp(undefined, true);
        t.app.save([{ id: 1, title: "X", content: "", timestamp: 1 }]);
        compare(JSON.parse(t.settings.values["notes-silica/data"])[0].title, "X");
    }

    function test_saveWaitsForPermission() {
        const t = makeApp(undefined, false);
        t.app.save([{ id: 1, title: "X", content: "", timestamp: 1 }]);
        compare(t.permissions.requests, 1);
        compare(t.settings.values["notes-silica/data"], undefined);
        t.permissions.granted = true;
        t.permissions.permissionGranted("notes-silica", "storage");
        compare(JSON.parse(t.settings.values["notes-silica/data"])[0].title, "X");
    }
}
