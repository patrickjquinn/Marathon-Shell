import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import "../components"

Page {
    id: listPage
    
    signal createNewNote()
    signal openNote(int noteId)
    
    background: Rectangle {
        color: Colors.background
    }
    
    Column {
        anchors.fill: parent
        spacing: 0
        
        Rectangle {
            width: parent.width
            height: Constants.statusBarHeight + Constants.spacingLarge
            color: Colors.surface
            
            Column {
                anchors.fill: parent
                anchors.margins: Constants.spacingLarge
                spacing: Constants.spacingMedium
                
                Item {
                    width: parent.width
                    height: Constants.fontSizeXXLarge + Constants.spacingMedium
                    
                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Notes"
                        color: Colors.text
                        font.pixelSize: Constants.fontSizeXXLarge
                        font.weight: Font.Bold
                    }
                    
                    Button {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "New"
                        variant: "primary"
                        width: Constants.touchTargetLarge + Constants.spacingMedium
                        onClicked: {
                            HapticService.light()
                            listPage.createNewNote()
                        }
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
        
        Item {
            width: parent.width
            height: parent.height - Constants.statusBarHeight - Constants.spacingLarge
            
            ListView {
                id: notesList
                anchors.fill: parent
                anchors.topMargin: Constants.spacingMedium
                clip: true
                model: notesApp.notes
                spacing: 0
                
                delegate: NoteItem {
                    width: notesList.width
                    noteId: modelData.id
                    noteTitle: modelData.title
                    noteContent: modelData.content
                    noteTimestamp: modelData.timestamp
                    
                    onClicked: {
                        HapticService.light()
                        listPage.openNote(noteId)
                    }
                }
                
                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(parent.width * 0.8, Constants.screenWidth * 0.6)
                    height: emptyColumn.height
                    color: "transparent"
                    visible: notesList.count === 0
                    
                    Column {
                        id: emptyColumn
                        anchors.centerIn: parent
                        spacing: Constants.spacingLarge
                        
                        Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: "file-text"
                            size: Constants.iconSizeXLarge * 2
                            color: Colors.textSecondary
                            opacity: 0.5
                        }
                        
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "No notes yet"
                            color: Colors.textSecondary
                            font.pixelSize: Constants.fontSizeLarge
                            font.weight: Font.Medium
                        }
                        
                        Text {
                            width: parent.width
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Tap the New button to create your first note"
                            color: Colors.textSecondary
                            font.pixelSize: Constants.fontSizeMedium
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }
    }
}

