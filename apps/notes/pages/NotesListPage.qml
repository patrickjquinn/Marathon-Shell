import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme

Page {
    id: listPage

    signal createNewNote
    signal openNote(int noteId)

    background: Rectangle {
        color: MColors.background
    }

    MScrollView {
        id: scrollView
        anchors.fill: parent
        contentHeight: notesContent.height + 40

        Column {
            id: notesContent
            width: parent.width
            spacing: MSpacing.xl
            leftPadding: 24
            rightPadding: 24
            topPadding: 24
            bottomPadding: 24

            Text {
                text: "Notes"
                color: MColors.text
                font.pixelSize: MTypography.sizeXLarge
                font.weight: Font.Bold
                font.family: MTypography.fontFamily
            }

            Row {
                width: parent.width - 48
                spacing: MSpacing.sm

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Sort:"
                    font.pixelSize: MTypography.sizeSmall
                    color: MColors.textSecondary
                }

                Repeater {
                    model: [
                        {
                            label: "Newest",
                            value: "newest"
                        },
                        {
                            label: "Oldest",
                            value: "oldest"
                        },
                        {
                            label: "A-Z",
                            value: "alphabetical"
                        }
                    ]

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Constants.touchTargetMedium * 1.2
                        height: Constants.touchTargetMedium * 0.7
                        radius: Constants.borderRadiusSharp
                        color: notesApp.sortMode === modelData.value ? MColors.accent : MColors.surface
                        border.width: Constants.borderWidthThin
                        border.color: notesApp.sortMode === modelData.value ? MColors.accentDark : MColors.border

                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            font.pixelSize: MTypography.sizeXSmall
                            color: MColors.text
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                notesApp.sortMode = modelData.value;
                                notesApp.sortNotes();
                                HapticService.light();
                            }
                        }
                    }
                }
            }

            MSection {
                title: "Your Notes"
                subtitle: notesApp.notes.length + " note" + (notesApp.notes.length === 1 ? "" : "s")
                width: parent.width - 48
                visible: notesApp.notes.length > 0

                Column {
                    width: parent.width
                    spacing: MSpacing.sm

                    Repeater {
                        model: notesApp.notes

                        Rectangle {
                            width: parent.width
                            height: Constants.touchTargetLarge + MSpacing.lg
                            color: "transparent"

                            Rectangle {
                                id: deleteButton
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.margins: MSpacing.sm
                                width: Constants.touchTargetLarge
                                color: "#E74C3C"
                                radius: Constants.borderRadiusSharp
                                visible: noteItem.x < -20

                                Icon {
                                    anchors.centerIn: parent
                                    name: "trash"
                                    size: Constants.iconSizeMedium
                                    color: "white"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        notesApp.deleteNote(modelData.id);
                                    }
                                }
                            }

                            Rectangle {
                                id: noteItem
                                anchors.fill: parent
                                anchors.margins: MSpacing.sm
                                color: MColors.surface
                                radius: Constants.borderRadiusSharp
                                border.width: Constants.borderWidthThin
                                border.color: MColors.border

                                Behavior on x {
                                    NumberAnimation {
                                        duration: 200
                                        easing.type: Easing.OutQuad
                                    }
                                }

                                Row {
                                    anchors.fill: parent
                                    anchors.margins: MSpacing.md
                                    spacing: MSpacing.md

                                    Icon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: "file-text"
                                        size: Constants.iconSizeMedium
                                        color: MColors.accent
                                    }

                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - parent.children[0].width - parent.children[2].width - parent.spacing * 2
                                        spacing: MSpacing.xs

                                        Text {
                                            width: parent.width
                                            text: modelData.title || "Untitled"
                                            font.pixelSize: MTypography.sizeBody
                                            font.weight: Font.DemiBold
                                            color: MColors.text
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            width: parent.width
                                            text: modelData.content.substring(0, 100) + (modelData.content.length > 100 ? "..." : "")
                                            font.pixelSize: MTypography.sizeSmall
                                            color: MColors.textSecondary
                                            elide: Text.ElideRight
                                            wrapMode: Text.NoWrap
                                        }
                                    }

                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: MSpacing.xs

                                        Text {
                                            text: formatTimestamp(modelData.timestamp)
                                            font.pixelSize: MTypography.sizeXSmall
                                            color: MColors.textTertiary
                                            horizontalAlignment: Text.AlignRight
                                        }

                                        Icon {
                                            anchors.right: parent.right
                                            name: "chevron-right"
                                            size: Constants.iconSizeSmall
                                            color: MColors.textTertiary
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    property real startX: 0

                                    onPressed: {
                                        startX = mouse.x;
                                        noteItem.color = MColors.elevated;
                                        HapticService.light();
                                    }
                                    onReleased: {
                                        noteItem.color = MColors.surface;
                                        if (noteItem.x < -100) {
                                            notesApp.deleteNote(modelData.id);
                                        } else {
                                            noteItem.x = 0;
                                        }
                                    }
                                    onCanceled: {
                                        noteItem.color = MColors.surface;
                                        noteItem.x = 0;
                                    }
                                    onPositionChanged: {
                                        if (pressed) {
                                            var delta = mouse.x - startX;
                                            if (delta < 0) {
                                                noteItem.x = Math.max(delta, -120);
                                            }
                                        }
                                    }
                                    onClicked: {
                                        if (noteItem.x === 0) {
                                            openNote(modelData.id);
                                        } else {
                                            noteItem.x = 0;
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            MEmptyState {
                width: parent.width - 48
                height: 400
                visible: notesApp.notes.length === 0
                iconName: "file-text"
                iconSize: 96
                title: "No Notes Yet"
                message: "Tap the + button below to create your first note"
            }

            Item {
                height: 40
            }
        }
    }

    MIconButton {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: MSpacing.lg
        iconName: "plus"
        iconSize: 28
        variant: "primary"
        shape: "circular"
        onClicked: {
            listPage.createNewNote();
        }
    }

    function formatTimestamp(timestamp) {
        var date = new Date(timestamp);
        var now = new Date();
        var diff = now - date;

        if (diff < 60000) {
            return "Just now";
        } else if (diff < 3600000) {
            var mins = Math.floor(diff / 60000);
            return mins + "m ago";
        } else if (diff < 86400000) {
            var hours = Math.floor(diff / 3600000);
            return hours + "h ago";
        } else if (diff < 604800000) {
            var days = Math.floor(diff / 86400000);
            return days + "d ago";
        } else {
            return Qt.formatDate(date, "MMM d");
        }
    }
}
