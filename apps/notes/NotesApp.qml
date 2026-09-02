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
                nextId = Math.max(notes.map(n => {
                    return n.id;
                })) + 1;

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
    Component.onCompleted: {
        loadNotes();
    }

    Connections {
        function onPermissionGranted(grantedAppId, permission) {
            if (grantedAppId === appId && permission === "storage" && notesApp.savePending)
                notesApp.saveNotes();
        }

        target: typeof PermissionManager !== "undefined" ? PermissionManager : null
    }

    content: Rectangle {
        anchors.fill: parent
        color: MColors.background

        MStackView {
            id: navigationStack

            property var backConnection: null

            anchors.fill: parent
            initialItem: notesListPage
            onDepthChanged: {
                notesApp.navigationDepth = depth - 1;
            }
            Component.onCompleted: {
                notesApp.navigationDepth = depth - 1;
                backConnection = notesApp.backPressed.connect(function () {
                    if (depth > 1)
                        pop();
                });
            }
            Component.onDestruction: {
                if (backConnection)
                    notesApp.backPressed.disconnect(backConnection);
            }
        }

        Component {
            id: notesListPage

            NotesListPage {
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
                onSaveNote: function (title, content) {
                    if (isNewNote)
                        notesApp.createNote(title, content);
                    else
                        notesApp.updateNote(noteId, title, content);
                    navigationStack.pop();
                }
                onDeleteNote: function (id) {
                    notesApp.deleteNote(id);
                    navigationStack.pop();
                }
            }
        }
    }
}
