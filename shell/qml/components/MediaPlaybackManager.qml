import QtQuick
import MarathonOS.Shell

// Media Playback Manager
// Shows currently playing media with playback controls
// ALWAYS VISIBLE - shows "No media" state when nothing playing
Rectangle {
    id: mediaManager
    
    width: parent.width
    height: hasMedia ? 120 : 80  // Show collapsed state when no media
    visible: true  // Always visible
    radius: Constants.borderRadiusSmall
    color: Qt.rgba(255, 255, 255, 0.04)
    border.width: Constants.borderWidthThin
    border.color: MColors.borderOuter
    
    // MPRIS2 Integration - Real media player control
    readonly property bool hasMedia: MPRIS2Controller ? MPRIS2Controller.hasActivePlayer : false
    readonly property bool isPlaying: MPRIS2Controller ? MPRIS2Controller.isPlaying : false
    readonly property string trackTitle: MPRIS2Controller && MPRIS2Controller.hasActivePlayer ? (MPRIS2Controller.trackTitle || "Unknown Track") : "No media playing"
    readonly property string artist: MPRIS2Controller ? MPRIS2Controller.trackArtist : ""
    readonly property string albumArt: MPRIS2Controller ? MPRIS2Controller.albumArtUrl : ""
    readonly property real progress: MPRIS2Controller ? (MPRIS2Controller.position / 1000000.0) : 0.0  // Convert microseconds to seconds
    readonly property real duration: MPRIS2Controller ? (MPRIS2Controller.trackLength / 1000000.0) : 0.0  // Convert microseconds to seconds
    
    Behavior on height {
        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
    }
    
    Column {
        anchors.fill: parent
        anchors.margins: Constants.spacingMedium
        spacing: Constants.spacingSmall
        
        // Title and artist
        Row {
            width: parent.width
            spacing: Constants.spacingMedium
            
            // Album art thumbnail or music icon
            Rectangle {
                width: Constants.touchTargetSmall
                height: Constants.touchTargetSmall
                radius: Constants.borderRadiusSmall
                color: mediaManager.albumArt !== "" ? "transparent" : MColors.surface2
                visible: mediaManager.hasMedia
                clip: true  // CRITICAL: Clip child Image to rounded corners
                
                Image {
                    anchors.fill: parent
                    source: mediaManager.albumArt
                    fillMode: Image.PreserveAspectCrop
                    visible: source !== ""
                    // Note: Image doesn't have radius property - parent Rectangle clips it
                }
                
                Icon {
                    name: "music"
                    size: Constants.iconSizeMedium
                    color: MColors.textSecondary
                    anchors.centerIn: parent
                    visible: mediaManager.albumArt === ""
                }
            }
            
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Constants.spacingXSmall
                width: parent.width - (mediaManager.hasMedia ? (Constants.touchTargetSmall + Constants.spacingMedium) : 0)
                
                Text {
                    text: mediaManager.trackTitle
                    color: mediaManager.hasMedia ? MColors.text : MColors.textSecondary
                    font.pixelSize: Constants.fontSizeMedium
                    font.weight: Font.Medium
                    font.family: Typography.fontFamily
                    elide: Text.ElideRight
                    width: parent.width
                }
                
                Text {
                    text: mediaManager.artist || (mediaManager.hasMedia ? "Unknown artist" : "Play music to see controls")
                    color: MColors.textSecondary
                    font.pixelSize: Constants.fontSizeSmall
                    font.family: Typography.fontFamily
                    elide: Text.ElideRight
                    width: parent.width
                }
            }
        }
        
        // Playback controls
        Row {
            width: parent.width
            height: Constants.touchTargetMinimum
            visible: mediaManager.hasMedia
            
            readonly property real buttonWidth: Constants.touchTargetMinimum
            readonly property real spacing: Constants.spacingSmall
            readonly property real totalButtonsWidth: (buttonWidth * 3) + (spacing * 4)  // 3 buttons + 4 spacers
            
            // Previous button
            Rectangle {
                width: parent.buttonWidth
                height: parent.buttonWidth
                radius: Constants.borderRadiusSmall
                color: prevMouseArea.pressed ? MColors.surface2 : MColors.surface
                
                Behavior on color {
                    ColorAnimation { duration: Constants.animationFast }
                }
                
                Icon {
                    name: "skip-back"
                    size: Constants.iconSizeSmall
                    color: MColors.text
                    anchors.centerIn: parent
                }
                
                MouseArea {
                    id: prevMouseArea
                    anchors.fill: parent
                    enabled: mediaManager.hasMedia && MPRIS2Controller && MPRIS2Controller.canGoPrevious
                    onClicked: {
                        HapticService.light()
                        if (MPRIS2Controller) {
                            MPRIS2Controller.previous()
                            Logger.info("MediaPlayback", "Previous track")
                        }
                    }
                }
            }
            
            Item { width: parent.spacing; height: 1 }
            
            // Play/Pause button
            Rectangle {
                width: parent.buttonWidth
                height: parent.buttonWidth
                radius: Constants.borderRadiusSmall
                color: playMouseArea.pressed ? MColors.accentBright : MColors.accent
                
                Behavior on color {
                    ColorAnimation { duration: Constants.animationFast }
                }
                
                Icon {
                    name: mediaManager.isPlaying ? "pause" : "play"
                    size: Constants.iconSizeSmall
                    color: "#FFFFFF"
                    anchors.centerIn: parent
                }
                
                MouseArea {
                    id: playMouseArea
                    anchors.fill: parent
                    enabled: mediaManager.hasMedia && MPRIS2Controller && (MPRIS2Controller.canPlay || MPRIS2Controller.canPause)
                    onClicked: {
                        HapticService.medium()
                        if (MPRIS2Controller) {
                            MPRIS2Controller.playPause()
                            Logger.info("MediaPlayback", "Play/Pause")
                        }
                    }
                }
            }
            
            Item { width: parent.spacing; height: 1 }
            
            // Next button
            Rectangle {
                width: parent.buttonWidth
                height: parent.buttonWidth
                radius: Constants.borderRadiusSmall
                color: nextMouseArea.pressed ? MColors.surface2 : MColors.surface
                
                Behavior on color {
                    ColorAnimation { duration: Constants.animationFast }
                }
                
                Icon {
                    name: "skip-forward"
                    size: Constants.iconSizeSmall
                    color: MColors.text
                    anchors.centerIn: parent
                }
                
                MouseArea {
                    id: nextMouseArea
                    anchors.fill: parent
                    enabled: mediaManager.hasMedia && MPRIS2Controller && MPRIS2Controller.canGoNext
                    onClicked: {
                        HapticService.light()
                        if (MPRIS2Controller) {
                            MPRIS2Controller.next()
                            Logger.info("MediaPlayback", "Next track")
                        }
                    }
                }
            }
            
            // Spacer (calculated properly now!)
            Item {
                width: parent.width - parent.totalButtonsWidth
                height: 1
            }
            
            // Time display
            Text {
                text: formatTime(mediaManager.progress) + " / " + formatTime(mediaManager.duration)
                color: MColors.textSecondary
                font.pixelSize: Constants.fontSizeSmall
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
        if (MPRIS2Controller) {
            Logger.info("MediaPlaybackManager", "✓ Initialized with MPRIS2 integration")
            Logger.info("MediaPlaybackManager", "Monitoring for media players (Spotify, VLC, Firefox, etc.)")
        } else {
            Logger.warn("MediaPlaybackManager", "MPRIS2Controller not available")
        }
    }
}

