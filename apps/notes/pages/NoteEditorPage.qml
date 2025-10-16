import QtQuick
import QtQuick.Controls
import MarathonOS.Shell

Page {
    id: editorPage
    
    property bool isNewNote: true
    property int noteId: -1
    property string initialTitle: ""
    property string initialContent: ""
    
    signal saveNote(string title, string content)
    signal deleteNote(int noteId)
    
    background: Rectangle {
        color: Colors.background
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
            color: Colors.surface
            z: 10
            
            Row {
                anchors.fill: parent
                anchors.leftMargin: Constants.spacingMedium
                anchors.rightMargin: Constants.spacingMedium
                spacing: Constants.spacingMedium
                
                Button {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Cancel"
                    variant: "secondary"
                    width: Constants.touchTargetLarge + Constants.spacingMedium
                    onClicked: {
                        HapticService.light()
                        navigationStack.pop()
                    }
                }
                
                Item { width: 1; height: 1; Layout.fillWidth: true }
                
                Button {
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
                
                Button {
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
                color: Colors.border
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
                
                Input {
                    id: titleInput
                    width: parent.width - parent.padding * 2
                    placeholderText: "Title"
                    font.pixelSize: Constants.fontSizeLarge
                    font.weight: Font.Bold
                }
                
                Rectangle {
                    width: parent.width - parent.padding * 2
                    height: Constants.borderWidthThin
                    color: Colors.border
                }
                
                TextArea {
                    id: contentInput
                    width: parent.width - parent.padding * 2
                    height: Math.max(Constants.screenHeight * 0.5, implicitHeight)
                    placeholderText: "Start typing..."
                    color: Colors.text
                    font.pixelSize: Constants.fontSizeMedium
                    wrapMode: TextArea.Wrap
                    background: Rectangle {
                        color: "transparent"
                    }
                }
            }
        }
    }
    
    Rectangle {
        id: deleteDialog
        anchors.centerIn: parent
        width: Math.min(Constants.screenWidth * 0.85, parent.width - Constants.spacingXLarge * 2)
        height: dialogContent.height + Constants.spacingXLarge * 2
        color: Colors.surface
        radius: Constants.borderRadiusLarge
        visible: false
        z: 1000
        
        function open() {
            visible = true
        }
        
        function close() {
            visible = false
        }
        
        Column {
            id: dialogContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Constants.spacingXLarge
            spacing: Constants.spacingLarge
            
            Text {
                width: parent.width - parent.anchors.margins * 2
                text: "Delete Note?"
                color: Colors.text
                font.pixelSize: Constants.fontSizeLarge
                font.weight: Font.Bold
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
            
            Text {
                width: parent.width - parent.anchors.margins * 2
                text: "This note will be permanently deleted."
                color: Colors.textSecondary
                font.pixelSize: Constants.fontSizeMedium
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
            
            Row {
                width: parent.width - parent.anchors.margins * 2
                spacing: Constants.spacingMedium
                
                Button {
                    width: (parent.width - Constants.spacingMedium) / 2
                    text: "Cancel"
                    variant: "secondary"
                    onClicked: {
                        deleteDialog.close()
                    }
                }
                
                Button {
                    width: (parent.width - Constants.spacingMedium) / 2
                    text: "Delete"
                    variant: "danger"
                    onClicked: {
                        editorPage.deleteNote(noteId)
                        deleteDialog.close()
                    }
                }
            }
        }
    }
    
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.7)
        visible: deleteDialog.visible
        z: 999
        
        MouseArea {
            anchors.fill: parent
            onClicked: {
                deleteDialog.close()
            }
        }
    }
}

