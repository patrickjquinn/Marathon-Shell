pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import Nemo.Configuration 1.0
import Sailfish.Share 1.0
import "NotesStore.js" as Store
import "pages"
import "cover"

ApplicationWindow {
    id: app

    property var store: ConfigurationValue {
        key: "/apps/notes/data"
        defaultValue: "[]"
    }
    property var imported: ConfigurationValue {
        key: "/apps/notes/legacyImported"
        defaultValue: false
    }
    // The MarathonUI app kept its notes in the shell's settings store.
    property var legacySettings: typeof Settings !== "undefined" ? Settings : null
    property var permissions: typeof Permissions !== "undefined" ? Permissions : null
    readonly property var notes: Store.parse(store.value)
    property string route: typeof MARATHON_APP_ROUTE !== "undefined" ? MARATHON_APP_ROUTE : ""

    function save(next) {
        store.value = JSON.stringify(next);
    }

    // Asking without the storage grant would prompt for it, and without it
    // the old app could not have saved anything.
    function importLegacy() {
        if (imported.value || !legacySettings || !permissions || !permissions.hasPermission(appId, "storage"))
            return;
        const old = Store.parse(legacySettings.get("notes/data", "[]"));
        if (old.length > 0)
            save(Store.merge(notes, old));
        imported.value = true;
    }

    // From the share sheet: a new note, opened.
    function receiveShare(resources) {
        const text = Store.sharedText(resources);
        if (text === "")
            return;
        const next = Store.create(notes, text, Date.now());
        save(next);
        activate();
        pageStack.push(Qt.resolvedUrl("pages/NoteEditorPage.qml"), { store: app, noteId: next[0].id });
    }

    function newNote() {
        pageStack.push(Qt.resolvedUrl("pages/NoteEditorPage.qml"), { store: app, noteId: -1 });
    }

    appId: "notes"
    onApplicationActiveChanged: {
        const page = pageStack.currentPage as NoteEditorPage;
        if (!applicationActive && page && page.commit)
            page.commit();
    }
    Component.onCompleted: {
        importLegacy();
        if (route === "/folders" || route === "/tasks")
            pageStack.push(Qt.resolvedUrl(route === "/folders" ? "pages/FoldersPage.qml" : "pages/TasksPage.qml"), { store: app }, PageStackAction.Immediate);
    }

    NotesActions {
        store: app
    }

    ShareProvider {
        method: "text"
        capabilities: ["text/plain", "text/x-url"]
        onTriggered: resources => app.receiveShare(resources)
    }

    cover: Component {
        NotesCover {
            notes: Store.sorted(app.notes)
            onNewNoteRequested: {
                app.activate();
                app.newNote();
            }
        }
    }

    initialPage: Component {
        NotesPage {
            store: app
        }
    }
}
