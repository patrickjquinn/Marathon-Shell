import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme

Page {
    id: listPage
    
    signal createNewNote()
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
            spacing: Constants.spacingXLarge
            leftPadding: 24
            rightPadding: 24
            topPadding: 24
            bottomPadding: 24
            
            Text {
                text: "Notes"
                color: MColors.text
                font.pixelSize: Constants.fontSizeXLarge
                font.weight: Font.Bold
                font.family: MTypography.fontFamily
            }
            
            Section {
                title: "Your Notes"
                subtitle: notesApp.notes.length === 0 ? "No notes yet. Tap the + button to create one." : notesApp.notes.length + " note" + (notesApp.notes.length === 1 ? "" : "s")
                width: parent.width - 48
                
                Repeater {
                    model: notesApp.notes
                    
                    SettingsListItem {
                        title: modelData.title || "Untitled"
                        subtitle: modelData.content.substring(0, 100) + (modelData.content.length > 100 ? "..." : "")
                        iconName: "file-text"
                        showChevron: true
                        value: formatTimestamp(modelData.timestamp)
                        onSettingClicked: {
                            openNote(modelData.id)
                        }
                    }
                }
            }
            
            Item { height: 40 }
        }
    }
    
    MIconButton {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Constants.spacingLarge
        icon: "plus"
        size: Constants.touchTargetLarge
        variant: "primary"
        shape: "circular"
        onClicked: {
            listPage.createNewNote()
        }
    }
    
    function formatTimestamp(timestamp) {
        var date = new Date(timestamp)
        var now = new Date()
        var diff = now - date
        
        if (diff < 60000) {
            return "Just now"
        } else if (diff < 3600000) {
            var mins = Math.floor(diff / 60000)
            return mins + "m ago"
        } else if (diff < 86400000) {
            var hours = Math.floor(diff / 3600000)
            return hours + "h ago"
        } else if (diff < 604800000) {
            var days = Math.floor(diff / 86400000)
            return days + "d ago"
        } else {
            return Qt.formatDate(date, "MMM d")
        }
    }
}
