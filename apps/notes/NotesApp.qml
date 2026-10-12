pragma ComponentBehavior: Bound
import MarathonApp.Notes
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick

MApp {
    id: notesApp

    property var notes: []
    property int nextId: 1
    property string sortMode: "newest"
    property var navStack: null

    function sortNotes() {
        if (sortMode === "newest")
            notes.sort(function (a, b) {
                return b.timestamp - a.timestamp;
            });
        else if (sortMode === "oldest")
            notes.sort(function (a, b) {
                return a.timestamp - b.timestamp;
            });
        else if (sortMode === "alphabetical")
            notes.sort(function (a, b) {
                return a.title.toLowerCase().localeCompare(b.title.toLowerCase());
            });
        notesChanged();
    }

    function loadNotes() {
        var savedNotes = SettingsManagerCpp.get("notes/data", "[]");
        try {
            notes = JSON.parse(savedNotes);
            if (notes.length > 0)
                nextId = Math.max(...notes.map(n => n.id)) + 1;

            sortNotes();
        } catch (e) {
            Logger.error("NotesApp", "Failed to load notes: " + e);
            notes = [];
        }
    }

    property bool savePending: false

    function saveNotes() {
        if (typeof PermissionManager !== "undefined" && !PermissionManager.hasPermission(appId, "storage")) {
            notesApp.savePending = true;
            PermissionManager.requestPermission(appId, "storage");
            return;
        }
        var data = JSON.stringify(notes);
        SettingsManagerCpp.set("notes/data", data);
        notesApp.savePending = false;
    }

    function createNote(title, content) {
        var note = {
            "id": nextId++,
            "title": title || "Untitled",
            "content": content || "",
            "timestamp": Date.now()
        };
        notes.push(note);
        notesChanged();
        saveNotes();
        return note;
    }

    function updateNote(id, title, content) {
        for (var i = 0; i < notes.length; i++) {
            if (notes[i].id === id) {
                notes[i].title = title;
                notes[i].content = content;
                notes[i].timestamp = Date.now();
                notesChanged();
                saveNotes();
                return true;
            }
        }
        return false;
    }

    function deleteNote(id) {
        for (var i = 0; i < notes.length; i++) {
            if (notes[i].id === id) {
                notes.splice(i, 1);
                notesChanged();
                saveNotes();
                return true;
            }
        }
        return false;
    }

    function getNote(id) {
        for (var i = 0; i < notes.length; i++) {
            if (notes[i].id === id)
                return notes[i];
        }
        return null;
    }

    function searchNotes(query) {
        if (!query || query.length === 0)
            return notes;

        var lowerQuery = query.toLowerCase();
        return notes.filter(function (note) {
            return note.title.toLowerCase().indexOf(lowerQuery) !== -1 || note.content.toLowerCase().indexOf(lowerQuery) !== -1;
        });
    }

    appId: "notes"
    appName: "Notes"
    appIcon: "assets/icon.svg"
    navigationDepth: navStack ? navStack.depth - 1 + (navStack.currentItem ? navStack.currentItem.backLayers || 0 : 0) : 0
    onBackPressed: {
        const page = navStack.currentItem;
        if (page && page.backLayers > 0)
            page.handleBack();
        else if (navStack.depth > 1)
            navStack.pop();
    }
    Component.onCompleted: {
        loadNotes();
    }

    Connections {
        function onPermissionGranted(grantedAppId, permission) {
            if (grantedAppId === notesApp.appId && permission === "storage" && notesApp.savePending)
                notesApp.saveNotes();
        }

        target: typeof PermissionManager !== "undefined" ? PermissionManager : null
    }

    content: Rectangle {
        anchors.fill: parent
        color: MColors.background

        MStackView {
            id: navigationStack

            anchors.fill: parent
            initialItem: notesListPage
            Component.onCompleted: notesApp.navStack = navigationStack
        }

        Component {
            id: notesListPage

            NotesListPage {
                app: notesApp
                onCreateNewNote: {
                    navigationStack.push(noteEditorPage, {
                        "isNewNote": true
                    });
                }
                onOpenNote: function (noteId) {
                    var note = notesApp.getNote(noteId);
                    if (note)
                        navigationStack.push(noteEditorPage, {
                            "isNewNote": false,
                            "noteId": noteId,
                            "initialTitle": note.title,
                            "initialContent": note.content
                        });
                }
            }
        }

        Component {
            id: noteEditorPage

            NoteEditorPage {
                app: notesApp
            }
        }
    }
}
