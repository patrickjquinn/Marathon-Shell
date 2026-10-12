import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Nemo.Configuration 1.0
import "NotesStore.js" as Store
import "pages"

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

    initialPage: Component {
        NotesPage {
            store: app
        }
    }
}
