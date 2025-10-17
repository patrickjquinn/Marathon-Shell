import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Theme

Item {
    id: noteItem
    height: Constants.touchTargetLarge + Constants.spacingLarge
    
    property int noteId: -1
    property string noteTitle: ""
    property string noteContent: ""
    property real noteTimestamp: 0
    
    signal clicked()
    
    function formatTimestamp(timestamp) {
        var date = new Date(timestamp)
        var now = new Date()
        var diff = now - date
        
        if (diff < 60000) {
            return "Just now"
        } else if (diff < 3600000) {
            var mins = Math.floor(diff / 60000)
            return mins + (mins === 1 ? " min ago" : " mins ago")
        } else if (diff < 86400000) {
            var hours = Math.floor(diff / 3600000)
            return hours + (hours === 1 ? " hour ago" : " hours ago")
        } else if (diff < 604800000) {
            var days = Math.floor(diff / 86400000)
            return days + (days === 1 ? " day ago" : " days ago")
        } else {
            return Qt.formatDate(date, "MMM d, yyyy")
        }
    }
    
    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: Constants.spacingLarge
        anchors.rightMargin: Constants.spacingLarge
        color: "transparent"
        
        Rectangle {
            anchors.fill: parent
            color: mouseArea.pressed ? MColors.surface2 : "transparent"
            radius: Constants.borderRadiusSharp
            
            Behavior on color {
                ColorAnimation { duration: 150 }
            }
        }
        
        Column {
            anchors.fill: parent
            anchors.margins: Constants.spacingMedium
            spacing: Constants.spacingXSmall
            
            Row {
                width: parent.width
                spacing: Constants.spacingSmall
                
                Text {
                    text: noteTitle || "Untitled"
                    color: MColors.text
                    font.pixelSize: Constants.fontSizeMedium
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    width: parent.width - timestampText.width - parent.spacing
                }
                
                Text {
                    id: timestampText
                    text: formatTimestamp(noteTimestamp)
                    color: MColors.textSecondary
                    font.pixelSize: Constants.fontSizeSmall
                    anchors.baseline: parent.children[0].baseline
                }
            }
            
            Text {
                width: parent.width
                text: noteContent.substring(0, 100) + (noteContent.length > 100 ? "..." : "")
                    color: MColors.textSecondary
                font.pixelSize: Constants.fontSizeSmall
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.WordWrap
            }
        }
        
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Constants.spacingMedium
            anchors.rightMargin: Constants.spacingMedium
            height: Constants.borderWidthThin
            color: MColors.border
        }
        
        MouseArea {
            id: mouseArea
            anchors.fill: parent
            onClicked: {
                noteItem.clicked()
            }
        }
    }
}

