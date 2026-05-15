import MarathonApp.Notes
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Navigation
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

// Marathon DS · Notes list (screens-apps-2.jsx:NotesApp).
//
// MTopBar with search + 36×36 teal+ compose. Optional "PINNED"
// section above "TODAY" — pinned cards get a star, teal eyebrow
// title, body preview, edited-at + word count meta. Regular rows
// use a 32×32 file-icon bay + title + snippet + #tag on the right.
// Bottom tabs: Notes · Folders · Tasks.
Page {
    id: listPage

    signal createNewNote
    signal openNote(int noteId)
    // Open a note and (later) reveal a specific task line. The line
    // hint is kept here for forward use; NoteEditorPage doesn't act
    // on it yet, but the wiring stays clean.
    signal openNoteAtLine(int noteId, int line)

    // The launch route lets external callers preselect a tab —
    // notes (default), folders, tasks. Pattern mirrors Phone's
    // /emergency route.
    readonly property string _initialTab: {
        if (typeof MARATHON_APP_ROUTE === "undefined")
            return "notes";
        if (MARATHON_APP_ROUTE === "/folders")
            return "folders";
        if (MARATHON_APP_ROUTE === "/tasks")
            return "tasks";
        return "notes";
    }
    property string selectedTab: _initialTab
    // Filters the Folders pane down to a single tag's notes when
    // non-empty. Cleared by the "All folders" back chip.
    property string folderFilter: ""

    // ── Derivation (Folders + Tasks) ────────────────────────
    // Folders are derived live from each note's `tag` field. No
    // separate persistence — notesApp.notes is the source of truth.
    // Both are property bindings (not functions) so QML tracks the
    // notesApp.notes dependency and re-evaluates when notes load
    // or change.
    readonly property var folderEntries: {
        const buckets = {};
        const all = notesApp.notes;
        for (let i = 0; i < all.length; i++) {
            const t = (all[i].tag && String(all[i].tag).length > 0) ? String(all[i].tag) : "untagged";
            if (!buckets[t])
                buckets[t] = 0;
            buckets[t]++;
        }
        const out = [];
        for (const k in buckets)
            out.push({
                "tag": k,
                "count": buckets[k]
            });
        out.sort((a, b) => {
            if (a.tag === "untagged")
                return 1;
            if (b.tag === "untagged")
                return -1;
            return a.tag.localeCompare(b.tag);
        });
        return out;
    }

    function notesInFolder(tag) {
        if (tag === "untagged")
            return notesApp.notes.filter(n => !n.tag || String(n.tag).length === 0);
        return notesApp.notes.filter(n => String(n.tag || "") === tag);
    }

    // Tasks are checkbox lines (`- [ ]` / `- [x]`) anywhere in a
    // note's content. Toggling rewrites the line in place and calls
    // notesApp.updateNote so the edit persists.
    readonly property var taskEntries: {
        const out = [];
        const re = /^\s*[-*]?\s*\[([ xX])\]\s*(.+)$/;
        const all = notesApp.notes;
        for (let i = 0; i < all.length; i++) {
            const n = all[i];
            if (!n.content)
                continue;
            const lines = String(n.content).split("\n");
            for (let j = 0; j < lines.length; j++) {
                const m = lines[j].match(re);
                if (!m)
                    continue;
                out.push({
                    "noteId": n.id,
                    "noteTitle": n.title || "Untitled",
                    "line": j,
                    "checked": m[1] !== " ",
                    "text": m[2].trim()
                });
            }
        }
        return out;
    }

    function toggleTask(noteId, lineIdx) {
        const note = notesApp.getNote(noteId);
        if (!note)
            return;
        const lines = String(note.content || "").split("\n");
        if (lineIdx < 0 || lineIdx >= lines.length)
            return;
        const re = /^(\s*[-*]?\s*\[)([ xX])(\]\s*.+)$/;
        const m = lines[lineIdx].match(re);
        if (!m)
            return;
        const flipped = (m[2] === " ") ? "x" : " ";
        lines[lineIdx] = m[1] + flipped + m[3];
        notesApp.updateNote(noteId, note.title, lines.join("\n"));
    }

    function formatTimestamp(timestamp) {
        const date = new Date(timestamp);
        const now = new Date();
        const diff = now - date;
        if (diff < 60000)
            return "Just now";
        if (diff < 3.6e+06)
            return Math.floor(diff / 60000) + "m";
        if (diff < 8.64e+07)
            return Math.floor(diff / 3.6e+06) + "h";
        if (diff < 6.048e+08)
            return Math.floor(diff / 8.64e+07) + "d";
        return Qt.formatDate(date, "MMM d");
    }
    function snippetOf(text) {
        if (!text)
            return "";
        const flat = text.replace(/\s+/g, " ").trim();
        return flat.length > 80 ? flat.substring(0, 80) + "…" : flat;
    }
    function pinnedNotes() {
        return notesApp.notes.filter(n => n.pinned === true);
    }
    function regularNotes() {
        return notesApp.notes.filter(n => n.pinned !== true);
    }

    background: Rectangle {
        color: MColors.background
    }

    Column {
        anchors.fill: parent
        spacing: 0

        // ── Header ───────────────────────────────────────────
        MTopBar {
            id: topBar
            width: parent.width
            title: "Notes"
            actions: [
                Icon {
                    name: "search"
                    size: 22
                    color: MColors.textSecondary
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -10
                        onClicked: HapticService.light()
                    }
                },
                Rectangle {
                    width: 36
                    height: 36
                    radius: MRadius.md
                    border.width: 1
                    border.color: MColors.tealBorder
                    gradient: Gradient {
                        GradientStop {
                            position: 0
                            color: MColors.marathonTealBright
                        }
                        GradientStop {
                            position: 1
                            color: MColors.marathonTealDark
                        }
                    }
                    Icon {
                        anchors.centerIn: parent
                        name: "plus"
                        size: 20
                        color: "#000000"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            HapticService.medium();
                            listPage.createNewNote();
                        }
                    }
                }
            ]
        }

        // ── Content swapper ─────────────────────────────────
        // Each pane fills the same area between the top bar and the
        // tab bar; visibility flips on `selectedTab`. Keeps the tab
        // bar's gesture surface stable while swapping content.
        Item {
            id: contentArea
            width: parent.width
            height: parent.height - topBar.height - tabBar.height

            ListView {
                id: listView
                anchors.fill: parent
                visible: listPage.selectedTab === "notes"
                clip: true
                spacing: 0
                model: notesApp.notes
                header: Column {
                    width: ListView.view.width
                    spacing: 0

                    // PINNED section
                    Item {
                        visible: listPage.pinnedNotes().length > 0
                        width: parent.width
                        height: visible ? 36 : 0

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 8
                            text: "PINNED"
                            color: MColors.textSecondary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeEyebrow
                            font.weight: Font.Bold
                            font.letterSpacing: MTypography.trackingEyebrow
                        }
                    }
                    Repeater {
                        model: listPage.pinnedNotes()
                        delegate: Item {
                            width: listView.width
                            height: 156
                            Rectangle {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                anchors.topMargin: 4
                                anchors.bottomMargin: 12
                                radius: MRadius.md
                                color: MColors.elev2
                                border.width: 1
                                border.color: MColors.whiteOverlay04

                                Column {
                                    anchors.fill: parent
                                    anchors.leftMargin: 16
                                    anchors.rightMargin: 16
                                    anchors.topMargin: 14
                                    spacing: 6

                                    Row {
                                        spacing: 8
                                        Icon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            name: "star"
                                            size: 14
                                            color: MColors.marathonTealBright
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: (modelData.title || "Untitled").toUpperCase()
                                            color: MColors.marathonTealBright
                                            font.family: MTypography.fontFamily
                                            font.pixelSize: MTypography.sizeEyebrow
                                            font.weight: Font.Bold
                                            font.letterSpacing: MTypography.trackingEyebrow
                                        }
                                    }
                                    Text {
                                        width: parent.width
                                        text: listPage.snippetOf(modelData.content)
                                        color: MColors.textPrimary
                                        font.family: MTypography.fontFamily
                                        font.pixelSize: MTypography.sizeFootnote
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 3
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        text: "edited " + listPage.formatTimestamp(modelData.timestamp) + " · " + (modelData.content ? modelData.content.split(/\s+/).length : 0) + " words"
                                        color: MColors.textTertiary
                                        font.family: MTypography.fontFamily
                                        font.pixelSize: MTypography.sizeEyebrow
                                        font.weight: Font.Medium
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        HapticService.light();
                                        listPage.openNote(modelData.id);
                                    }
                                }
                            }
                        }
                    }

                    // TODAY section header
                    Item {
                        width: parent.width
                        height: 36
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 8
                            text: "TODAY"
                            color: MColors.textSecondary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeEyebrow
                            font.weight: Font.Bold
                            font.letterSpacing: MTypography.trackingEyebrow
                        }
                    }
                }

                delegate: Item {
                    visible: !modelData.pinned
                    width: listView.width
                    height: visible ? 70 : 0

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        anchors.topMargin: 14
                        anchors.bottomMargin: 14
                        spacing: 12

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 32
                            height: 32
                            radius: MRadius.md
                            color: MColors.elev3
                            Icon {
                                anchors.centerIn: parent
                                name: "file-text"
                                size: 16
                                color: MColors.textSecondary
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 32 - 12 - tagText.width - parent.spacing * 2
                            spacing: 2
                            Text {
                                width: parent.width
                                text: modelData.title || "Untitled"
                                color: MColors.textPrimary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeSubhead
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: listPage.snippetOf(modelData.content)
                                color: MColors.textSecondary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeFootnote
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }

                        Text {
                            id: tagText
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.tag ? "#" + modelData.tag : ""
                            color: MColors.marathonTealBright
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeFootnote
                            font.weight: Font.Medium
                            visible: text.length > 0
                        }
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.leftMargin: 16 + 32 + 12
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        height: 1
                        color: MColors.whiteOverlay04
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            HapticService.light();
                            listPage.openNote(modelData.id);
                        }
                    }
                }

                MEmptyState {
                    anchors.centerIn: parent
                    visible: notesApp.notes.length === 0
                    width: parent.width - 48
                    iconName: "file-text"
                    iconSize: 64
                    title: "No Notes Yet"
                    message: "Tap the + in the header to write your first note"
                }
            }

            // ── Folders pane ────────────────────────────────────
            // Two states: bucket list (folder rows) or filtered notes
            // for the selected folder. Selection lives on
            // listPage.folderFilter.
            Item {
                id: foldersPane
                anchors.fill: parent
                visible: listPage.selectedTab === "folders"

                // Folder list — outer view.
                ListView {
                    anchors.fill: parent
                    visible: listPage.folderFilter === ""
                    clip: true
                    spacing: 0
                    model: listPage.folderEntries
                    header: Item {
                        width: ListView.view.width
                        height: 36
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 8
                            text: "FOLDERS"
                            color: MColors.textSecondary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeEyebrow
                            font.weight: Font.Bold
                            font.letterSpacing: MTypography.trackingEyebrow
                        }
                    }
                    delegate: Item {
                        width: ListView.view.width
                        height: 64

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            anchors.topMargin: 12
                            anchors.bottomMargin: 12
                            spacing: 12

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 40
                                height: 40
                                radius: MRadius.md
                                color: MColors.elev3
                                border.width: 1
                                border.color: MColors.whiteOverlay08
                                Icon {
                                    anchors.centerIn: parent
                                    name: modelData.tag === "untagged" ? "file-text" : "archive"
                                    size: 18
                                    color: modelData.tag === "untagged" ? MColors.textTertiary : MColors.marathonTealBright
                                }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 40 - 12 - countText.width - chev.width - parent.spacing * 3
                                spacing: 2
                                Text {
                                    text: modelData.tag === "untagged" ? "Untagged" : "#" + modelData.tag
                                    color: MColors.textPrimary
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: MTypography.sizeSubhead
                                    font.weight: Font.Medium
                                }
                                Text {
                                    text: modelData.count + (modelData.count === 1 ? " note" : " notes")
                                    color: MColors.textSecondary
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: MTypography.sizeFootnote
                                }
                            }

                            Text {
                                id: countText
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.count
                                color: MColors.textTertiary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeFootnote
                                font.weight: Font.Medium
                            }

                            Icon {
                                id: chev
                                anchors.verticalCenter: parent.verticalCenter
                                name: "chevron-right"
                                size: 16
                                color: MColors.textTertiary
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.leftMargin: 16 + 40 + 12
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            height: 1
                            color: MColors.whiteOverlay04
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                HapticService.light();
                                listPage.folderFilter = modelData.tag;
                            }
                        }
                    }

                    MEmptyState {
                        anchors.centerIn: parent
                        visible: listPage.folderEntries.length === 0
                        width: parent.width - 48
                        iconName: "archive"
                        iconSize: 64
                        title: "No Folders Yet"
                        message: "Add #tags to your notes to group them into folders"
                    }
                }

                // Filtered notes — inner view when a folder is selected.
                Item {
                    anchors.fill: parent
                    visible: listPage.folderFilter !== ""

                    // Back chip + folder title header.
                    Rectangle {
                        id: folderHeader
                        width: parent.width
                        height: 44
                        color: "transparent"

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 16
                            spacing: 8

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: backLabel.implicitWidth + 36
                                height: 28
                                radius: 14
                                color: MColors.elev2
                                border.width: 1
                                border.color: MColors.whiteOverlay08

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Icon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: "chevron-left"
                                        size: 14
                                        color: MColors.textSecondary
                                    }
                                    Text {
                                        id: backLabel
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Folders"
                                        color: MColors.textSecondary
                                        font.family: MTypography.fontFamily
                                        font.pixelSize: MTypography.sizeFootnote
                                        font.weight: Font.Medium
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        HapticService.light();
                                        listPage.folderFilter = "";
                                    }
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: listPage.folderFilter === "untagged" ? "Untagged" : "#" + listPage.folderFilter
                                color: MColors.marathonTealBright
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeFootnote
                                font.weight: Font.Bold
                                font.letterSpacing: MTypography.trackingEyebrow
                            }
                        }
                    }

                    ListView {
                        width: parent.width
                        anchors.top: folderHeader.bottom
                        anchors.bottom: parent.bottom
                        clip: true
                        spacing: 0
                        model: listPage.folderFilter === "" ? [] : listPage.notesInFolder(listPage.folderFilter)
                        delegate: Item {
                            width: ListView.view.width
                            height: 70

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                anchors.topMargin: 14
                                anchors.bottomMargin: 14
                                spacing: 12

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 32
                                    height: 32
                                    radius: MRadius.md
                                    color: MColors.elev3
                                    Icon {
                                        anchors.centerIn: parent
                                        name: "file-text"
                                        size: 16
                                        color: MColors.textSecondary
                                    }
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 32 - 12 - parent.spacing
                                    spacing: 2
                                    Text {
                                        width: parent.width
                                        text: modelData.title || "Untitled"
                                        color: MColors.textPrimary
                                        font.family: MTypography.fontFamily
                                        font.pixelSize: MTypography.sizeSubhead
                                        font.weight: Font.Medium
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: parent.width
                                        text: listPage.snippetOf(modelData.content)
                                        color: MColors.textSecondary
                                        font.family: MTypography.fontFamily
                                        font.pixelSize: MTypography.sizeFootnote
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }
                                }
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.leftMargin: 16 + 32 + 12
                                anchors.right: parent.right
                                anchors.rightMargin: 16
                                height: 1
                                color: MColors.whiteOverlay04
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    HapticService.light();
                                    listPage.openNote(modelData.id);
                                }
                            }
                        }
                    }
                }
            }

            // ── Tasks pane ──────────────────────────────────────
            // Tasks are checkbox lines parsed from note content.
            // Toggling rewrites the line in place via
            // listPage.toggleTask, then notesApp.updateNote persists
            // the edit and refreshes notesApp.notes — which retriggers
            // taskEntries() on next read.
            Item {
                id: tasksPane
                anchors.fill: parent
                visible: listPage.selectedTab === "tasks"

                ListView {
                    anchors.fill: parent
                    clip: true
                    spacing: 0
                    model: listPage.taskEntries
                    header: Item {
                        width: ListView.view.width
                        height: 36
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 8
                            text: "TASKS"
                            color: MColors.textSecondary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeEyebrow
                            font.weight: Font.Bold
                            font.letterSpacing: MTypography.trackingEyebrow
                        }
                    }
                    delegate: Item {
                        width: ListView.view.width
                        height: 64

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            anchors.topMargin: 12
                            anchors.bottomMargin: 12
                            spacing: 12

                            // Checkbox — tap zone is its own MouseArea so
                            // the row-tap (which opens the note) isn't
                            // triggered when toggling.
                            Rectangle {
                                id: checkbox
                                anchors.verticalCenter: parent.verticalCenter
                                width: 24
                                height: 24
                                radius: 6
                                color: modelData.checked ? MColors.marathonTealBright : "transparent"
                                border.width: 1.5
                                border.color: modelData.checked ? MColors.marathonTealBright : MColors.textTertiary
                                Icon {
                                    anchors.centerIn: parent
                                    visible: modelData.checked
                                    name: "check"
                                    size: 14
                                    color: "#000000"
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -8
                                    onClicked: {
                                        HapticService.light();
                                        listPage.toggleTask(modelData.noteId, modelData.line);
                                    }
                                }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 24 - 12 - parent.spacing
                                spacing: 2
                                Text {
                                    width: parent.width
                                    text: modelData.text
                                    color: modelData.checked ? MColors.textTertiary : MColors.textPrimary
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: MTypography.sizeSubhead
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                    font.strikeout: modelData.checked
                                }
                                Text {
                                    width: parent.width
                                    text: modelData.noteTitle
                                    color: MColors.textSecondary
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: MTypography.sizeFootnote
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.leftMargin: 16 + 24 + 12
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            height: 1
                            color: MColors.whiteOverlay04
                        }

                        // Row tap (outside the checkbox) opens the
                        // parent note for editing.
                        MouseArea {
                            anchors.fill: parent
                            anchors.leftMargin: 16 + 24 + 8
                            onClicked: {
                                HapticService.light();
                                listPage.openNote(modelData.noteId);
                            }
                        }
                    }

                    MEmptyState {
                        anchors.centerIn: parent
                        visible: listPage.taskEntries.length === 0
                        width: parent.width - 48
                        iconName: "check"
                        iconSize: 64
                        title: "No Tasks Yet"
                        message: "Add a checkbox line like '- [ ] thing to do' inside any note"
                    }
                }
            }
        }

        MTabBar {
            id: tabBar
            width: parent.width
            activeTab: listPage.selectedTab === "notes" ? 0 : listPage.selectedTab === "folders" ? 1 : 2
            tabs: [
                {
                    "label": "Notes",
                    "icon": "file-text"
                },
                {
                    "label": "Folders",
                    "icon": "archive"
                },
                {
                    "label": "Tasks",
                    "icon": "check"
                }
            ]
            onTabSelected: index => {
                HapticService.light();
                listPage.selectedTab = ["notes", "folders", "tasks"][index];
            }
        }
    }
}
