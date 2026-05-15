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

    property string selectedTab: "notes"

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

        ListView {
            id: listView
            width: parent.width
            height: parent.height - topBar.height - tabBar.height
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
                        anchors.leftMargin: 20
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
                        anchors.leftMargin: 20
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
