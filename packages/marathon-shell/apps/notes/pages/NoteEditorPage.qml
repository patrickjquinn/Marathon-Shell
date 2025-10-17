import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Core
import MarathonUI.Modals
import MarathonUI.Theme

Page {
    id: editorPage
    
    property bool isNewNote: true
    property int noteId: -1
    property string initialTitle: ""
    property string initialContent: ""
    
    signal saveNote(string title, string content)
    signal deleteNote(int noteId)
    
    background: Rectangle {
        color: MColors.background
    }
    
    Component.onCompleted: {
        titleInput.text = initialTitle
        contentInput.text = initialContent
        if (isNewNote) {
            titleInput.forceActiveFocus()
        }
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
                anchors.leftMargin: Constants.spacingMedium
                anchors.rightMargin: Constants.spacingMedium
                spacing: Constants.spacingMedium
                
                MButton {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Cancel"
                    variant: "secondary"
                    width: Constants.touchTargetLarge + Constants.spacingMedium
                    onClicked: {
                        HapticService.light()
                        navigationStack.pop()
                    }
                }
                
                Item {
                    width: parent.width - (Constants.touchTargetLarge + Constants.spacingMedium) * 2 - (deleteBtn.visible ? Constants.touchTargetLarge + Constants.spacingLarge : 0) - parent.spacing * (deleteBtn.visible ? 3 : 2)
                    height: 1
                }
                
                MButton {
                    id: deleteBtn
                    anchors.verticalCenter: parent.verticalCenter
                    text: !isNewNote ? "Delete" : ""
                    variant: "danger"
                    visible: !isNewNote
                    width: Constants.touchTargetLarge + Constants.spacingLarge
                    onClicked: {
                        HapticService.medium()
                        deleteDialog.open()
                    }
                }
                
                MButton {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Save"
                    variant: "primary"
                    width: Constants.touchTargetLarge + Constants.spacingMedium
                    onClicked: {
                        HapticService.light()
                        var title = titleInput.text.trim() || "Untitled"
                        var content = contentInput.text
                        editorPage.saveNote(title, content)
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
                padding: Constants.spacingLarge
                spacing: Constants.spacingMedium
                
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
                        anchors.margins: Constants.spacingMedium
                        color: MColors.text
                        font.pixelSize: Constants.fontSizeLarge
                        font.weight: Font.Bold
                        verticalAlignment: TextInput.AlignVCenter
                        
                        Text {
                            anchors.fill: parent
                            text: "Title"
                            color: MColors.textSecondary
                            font.pixelSize: Constants.fontSizeLarge
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
                    text: initialContent
                    maxLength: 10000
                    showCharCount: true
                }
            }
        }
    }
    
    MConfirmDialog {
        id: deleteDialog
        title: "Delete Note?"
        message: "This note will be permanently deleted."
        confirmText: "Delete"
        cancelText: "Cancel"
        
        function open() {
            show()
        }
        
        function close() {
            hide()
        }
        
        onAccepted: {
            editorPage.deleteNote(noteId)
        }
    }
}

