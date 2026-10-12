import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Nemo.Configuration 1.0
import "NotesStore.js" as Store
import "pages"
import "cover"

ApplicationWindow {
    id: app
    appId: "notes-silica"

    property QtObject store: ConfigurationValue {
        key: "/apps/notes-silica/data"
        defaultValue: "[]"
    }
    property var notes: Store.parse(store.value)

    function save(next) {
        notes = next;
        store.value = JSON.stringify(next);
    }

    cover: Component {
        NotesCover {
            notes: app.notes
            onNewNoteRequested: {
                app.activate();
                app.pageStack.push(Qt.resolvedUrl("pages/NoteEditorPage.qml"), { store: app, noteId: -1 });
            }
        }
    }

    initialPage: Component {
        NotesPage {
            store: app
        }
    }
}
