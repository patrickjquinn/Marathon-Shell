import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Modals
import MarathonUI.Theme
import QtQuick
import QtQuick.Controls

Page {
    id: editorPage

    required property var app
    property bool isNewNote: true
    property int noteId: -1
    property string initialTitle: ""
    property string initialContent: ""

    property string savedTitle: initialTitle
    property string savedContent: initialContent
    property bool discarded: false
    readonly property int backLayers: deleteDialog.showing ? 1 : 0

    function handleBack() {
        deleteDialog.hide();
    }

    function commit() {
        autosaveTimer.stop();
        if (discarded)
            return;
        const title = titleInput.text.trim();
        const content = contentInput.text;
        if (title === savedTitle && content === savedContent)
            return;
        if (isNewNote) {
            if (title === "" && content.trim() === "")
                return;
            noteId = app.createNote(title, content).id;
            isNewNote = false;
        } else {
            app.updateNote(noteId, title || "Untitled", content);
        }
        savedTitle = title;
        savedContent = content;
    }

    StackView.onDeactivating: commit()
    Component.onCompleted: {
        titleInput.text = initialTitle;
        contentInput.text = initialContent;
        if (isNewNote)
            titleInput.forceActiveFocus();
    }

    Timer {
        id: autosaveTimer

        interval: 800
        onTriggered: editorPage.commit()
    }

    Connections {
        function onAppPaused() {
            editorPage.commit();
        }

        target: editorPage.app
    }

    Column {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            width: parent.width
            height: Constants.actionBarHeight
            color: MColors.surface
            z: 10

            Row {
                anchors.fill: parent
                anchors.leftMargin: MSpacing.md
                anchors.rightMargin: MSpacing.md
                spacing: MSpacing.md

                Item {
                    width: parent.width - (Constants.touchTargetLarge + MSpacing.md) - (deleteBtn.visible ? Constants.touchTargetLarge + MSpacing.lg : 0) - parent.spacing * (deleteBtn.visible ? 2 : 1)
                    height: 1
                }

                MButton {
                    id: deleteBtn

                    anchors.verticalCenter: parent.verticalCenter
                    text: "Delete"
                    variant: "danger"
                    visible: !editorPage.isNewNote
                    width: Constants.touchTargetLarge + MSpacing.lg
                    onClicked: {
                        HapticService.medium();
                        deleteDialog.show();
                    }
                }

                MButton {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Done"
                    variant: "primary"
                    width: Constants.touchTargetLarge + MSpacing.md
                    onClicked: {
                        HapticService.light();
                        editorPage.StackView.view.pop();
                    }
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: Constants.borderWidthThin
                color: MColors.border
            }
        }

        Flickable {
            width: parent.width
            height: parent.height - Constants.actionBarHeight
            contentHeight: editorContent.height
            clip: true

            Column {
                id: editorContent

                width: parent.width
                padding: MSpacing.lg
                spacing: MSpacing.md

                Rectangle {
                    width: parent.width - parent.padding * 2
                    height: Constants.touchTargetMedium
                    radius: Constants.borderRadiusSharp
                    color: MColors.surface
                    border.width: Constants.borderWidthMedium
                    border.color: MColors.border
                    antialiasing: Constants.enableAntialiasing

                    TextInput {
                        id: titleInput

                        anchors.fill: parent
                        anchors.margins: MSpacing.md
                        color: MColors.text
                        font.pixelSize: MTypography.sizeLarge
                        font.weight: Font.Bold
                        verticalAlignment: TextInput.AlignVCenter
                        onTextChanged: autosaveTimer.restart()

                        Text {
                            anchors.fill: parent
                            text: "Title"
                            color: MColors.textSecondary
                            font.pixelSize: MTypography.sizeLarge
                            font.weight: Font.Bold
                            verticalAlignment: Text.AlignVCenter
                            visible: titleInput.text.length === 0
                        }
                    }
                }

                MTextArea {
                    id: contentInput

                    width: parent.width - parent.padding * 2
                    height: Math.max(Constants.screenHeight * 0.4, 300)
                    placeholderText: "Start typing..."
                    onTextChanged: autosaveTimer.restart()
                }
            }
        }
    }

    MConfirmDialog {
        id: deleteDialog

        title: "Delete this note?"
        message: "This note will be permanently deleted. This can't be undone."
        confirmText: "Delete note"
        cancelText: "Keep"
        destructive: true
        onCancelled: hide()
        onConfirmed: {
            editorPage.discarded = true;
            editorPage.app.deleteNote(editorPage.noteId);
            editorPage.StackView.view.pop();
        }
    }

    background: Rectangle {
        color: MColors.background
    }
}
