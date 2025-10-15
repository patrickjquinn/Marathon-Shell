import QtQuick
import QtQuick.Controls
import MarathonOS.Shell

// Media Playback Manager
// Shows currently playing media with playback controls
Rectangle {
    id: mediaManager
    
    width: parent.width
    height: isPlaying ? 120 : 0
    visible: height > 0
    radius: 4
    color: Qt.rgba(255, 255, 255, 0.04)
    border.width: 1
    border.color: Qt.rgba(255, 255, 255, 0.08)
    
    // TODO: Wire up to D-Bus MPRIS interface on Linux
    // For now, scaffolding with placeholder state
    property bool isPlaying: false
    property string trackTitle: "No media playing"
    property string artist: ""
    property string albumArt: ""
    property real progress: 0.0
    property real duration: 0.0
    
    Behavior on height {
        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
    }
    
    Column {
        anchors.fill: parent
        anchors.margins: 16
        spacing: Constants.spacingMedium
        
        // Title and artist
        Row {
            width: parent.width
            spacing: Constants.spacingMedium
            
            // Album art thumbnail
            Rectangle {
                width: 48
                height: 48
                radius: 3
                color: Qt.rgba(255, 255, 255, 0.08)
                visible: mediaManager.albumArt !== ""
                
                Image {
                    anchors.fill: parent
                    source: mediaManager.albumArt
                    fillMode: Image.PreserveAspectCrop
                    visible: source !== ""
                }
            }
            
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                width: parent.width - (mediaManager.albumArt !== "" ? 60 : 0)
                
                Text {
                    text: mediaManager.trackTitle
                    color: Colors.text
                    font.pixelSize: Typography.sizeBody
                    font.weight: Font.Medium
                    font.family: Typography.fontFamily
                    elide: Text.ElideRight
                    width: parent.width
                }
                
                Text {
                    text: mediaManager.artist
                    color: Colors.textSecondary
                    font.pixelSize: Typography.sizeSmall
                    font.family: Typography.fontFamily
                    elide: Text.ElideRight
                    width: parent.width
                    visible: text !== ""
                }
            }
        }
        
        // Playback controls
        Row {
            width: parent.width
            height: 40
            
            // Previous button
            Rectangle {
                width: 40
                height: 40
                radius: 3
                color: prevMouseArea.pressed ? Qt.rgba(255, 255, 255, 0.12) : Qt.rgba(255, 255, 255, 0.06)
                
                Behavior on color {
                    ColorAnimation { duration: 150 }
                }
                
                Icon {
                    name: "chevron-down"
                    size: Constants.iconSizeSmall
                    color: Colors.text
                    rotation: 90
                    anchors.centerIn: parent
                }
                
                MouseArea {
                    id: prevMouseArea
                    anchors.fill: parent
                    onClicked: {
                        HapticService.light()
                        // TODO: Send D-Bus Previous command
                        Logger.info("MediaPlayback", "Previous track")
                    }
                }
            }
            
            Item { width: 8; height: 1 }
            
            // Play/Pause button
            Rectangle {
                width: 48
                height: 40
                radius: 3
                color: playMouseArea.pressed ? Qt.rgba(20, 184, 166, 0.3) : Qt.rgba(20, 184, 166, 0.2)
                
                Behavior on color {
                    ColorAnimation { duration: 150 }
                }
                
                Text {
                    text: mediaManager.isPlaying ? "⏸" : "▶"
                    color: Qt.rgba(20, 184, 166, 1.0)
                    font.pixelSize: Constants.fontSizeXLarge
                    anchors.centerIn: parent
                }
                
                MouseArea {
                    id: playMouseArea
                    anchors.fill: parent
                    onClicked: {
                        HapticService.medium()
                        mediaManager.isPlaying = !mediaManager.isPlaying
                        // TODO: Send D-Bus PlayPause command
                        Logger.info("MediaPlayback", "Play/Pause")
                    }
                }
            }
            
            Item { width: 8; height: 1 }
            
            // Next button
            Rectangle {
                width: 40
                height: 40
                radius: 3
                color: nextMouseArea.pressed ? Qt.rgba(255, 255, 255, 0.12) : Qt.rgba(255, 255, 255, 0.06)
                
                Behavior on color {
                    ColorAnimation { duration: 150 }
                }
                
                Icon {
                    name: "chevron-down"
                    size: Constants.iconSizeSmall
                    color: Colors.text
                    rotation: -90
                    anchors.centerIn: parent
                }
                
                MouseArea {
                    id: nextMouseArea
                    anchors.fill: parent
                    onClicked: {
                        HapticService.light()
                        // TODO: Send D-Bus Next command
                        Logger.info("MediaPlayback", "Next track")
                    }
                }
            }
            
            // Spacer
            Item {
                width: parent.width - 184 // Fixed width calculation (3 buttons + spacers)
                height: 1
            }
            
            // Time display
            Text {
                text: formatTime(mediaManager.progress) + " / " + formatTime(mediaManager.duration)
                color: Colors.textSecondary
                font.pixelSize: Typography.sizeSmall
                font.family: Typography.fontFamily
                anchors.verticalCenter: parent.verticalCenter
                visible: mediaManager.duration > 0
            }
        }
    }
    
    // Format time helper
    function formatTime(seconds) {
        var mins = Math.floor(seconds / 60)
        var secs = Math.floor(seconds % 60)
        return mins + ":" + (secs < 10 ? "0" : "") + secs
    }
    
    Component.onCompleted: {
        Logger.info("MediaPlaybackManager", "Initialized (D-Bus MPRIS integration pending)")
    }
}

