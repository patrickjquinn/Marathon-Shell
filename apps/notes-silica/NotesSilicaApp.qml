import QtQuick
import Sailfish.Silica 1.0
import "NotesStore.js" as Store
import "pages"

SilicaApp {
    id: app
    appId: "notes-silica"

    property var settings: typeof SettingsManagerCpp !== "undefined" ? SettingsManagerCpp : null
    property var permissions: typeof PermissionManager !== "undefined" ? PermissionManager : null
    property var notes: []
    property bool savePending: false

    function load() {
        notes = settings ? Store.parse(settings.get("notes-silica/data", "[]")) : [];
    }

    function save(next) {
        notes = next;
        if (permissions && !permissions.hasPermission(appId, "storage")) {
            savePending = true;
            permissions.requestPermission(appId, "storage");
            return;
        }
        if (settings)
            settings.set("notes-silica/data", JSON.stringify(notes));
        savePending = false;
    }

    Connections {
        target: app.permissions
        ignoreUnknownSignals: true
        function onPermissionGranted(grantedAppId, permission) {
            if (grantedAppId === app.appId && permission === "storage" && app.savePending)
                app.save(app.notes);
        }
    }

    Component.onCompleted: load()

    initialPage: Component {
        NotesPage {
            store: app
        }
    }
}
