import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Theme

MApp {
    id: musicApp
    appId: "music"
    appName: "Music"
    appIcon: "assets/icon.svg"
    
    property var currentTrack: null
    property bool isPlaying: audioPlayer.playbackState === MediaPlayer.PlayingState
    property bool shuffle: false
    property string repeatMode: "off"
    property var playlist  // No initial binding - set by library scan
    
    Component.onCompleted: {
        // Initialize playlist
        if (typeof MusicLibraryManager !== 'undefined') {
            playlist = MusicLibraryManager.getAllTracks()
            MusicLibraryManager.scanLibrary()
        } else {
            playlist = []  // Fallback to empty
        }
    }
    
    Connections {
        target: typeof MusicLibraryManager !== 'undefined' ? MusicLibraryManager : null
        function onScanComplete(trackCount) {
            Logger.info("Music", "Library scan complete: " + trackCount + " tracks")
            playlist = MusicLibraryManager.getAllTracks()
            if (playlist.length > 0 && !currentTrack) {
                currentTrack = playlist[0]
            }
        }
    }
    
    MediaPlayer {
        id: audioPlayer
        audioOutput: AudioOutput {
            id: audioOutput
        }
        
        onPositionChanged: {
            if (currentTrack && currentTrack.duration) {
                var newPos = position / 1000
                if (!isNaN(newPos) && isFinite(newPos)) {
                    currentTrack.position = newPos
                }
            }
        }
        
        onDurationChanged: {
            if (currentTrack && duration > 0) {
                var newDur = duration / 1000
                if (!isNaN(newDur) && isFinite(newDur)) {
                    currentTrack.duration = newDur
                }
            }
        }
        
        onPlaybackStateChanged: {
            if (playbackState === MediaPlayer.StoppedState && currentTrack) {
                playNext()
            }
        }
        
        onErrorOccurred: function(error, errorString) {
            Logger.error("Music", "Playback error: " + errorString)
        }
    }
    
    function playTrack(track) {
        if (!track) return
        
        currentTrack = track
        currentTrack.position = 0
        audioPlayer.source = track.path
        audioPlayer.play()
        Logger.info("Music", "Playing: " + track.title + " by " + track.artist)
    }
    
        function playNext() {
            if (playlist.length === 0) return

            var currentIndex = -1
            for (var i = 0; i < playlist.length; i++) {
                if (playlist[i].id === currentTrack.id) {
                    currentIndex = i
                    break
                }
            }

            var nextIndex
            if (shuffle) {
                // True random shuffle - exclude current track
                do {
                    nextIndex = Math.floor(Math.random() * playlist.length)
                } while (nextIndex === currentIndex && playlist.length > 1)
            } else {
                nextIndex = (currentIndex + 1) % playlist.length
            }

            if (repeatMode === "off" && nextIndex <= currentIndex && !shuffle) {
                audioPlayer.stop()
                return
            }
            
            if (repeatMode === "single") {
                playTrack(currentTrack)
            } else {
                playTrack(playlist[nextIndex])
            }
        }
    
    function playPrevious() {
        if (playlist.length === 0) return
        
        var currentIndex = -1
        for (var i = 0; i < playlist.length; i++) {
            if (playlist[i].id === currentTrack.id) {
                currentIndex = i
                break
            }
        }
        
        var prevIndex = (currentIndex - 1 + playlist.length) % playlist.length
        playTrack(playlist[prevIndex])
    }
    
    function formatTime(seconds) {
        var mins = Math.floor(seconds / 60)
        var secs = Math.floor(seconds % 60)
        return mins + ":" + (secs < 10 ? "0" : "") + secs
    }
    
    content: Rectangle {
        anchors.fill: parent
        color: MColors.background
        
        Column {
            anchors.fill: parent
            spacing: 0
            
            property int currentView: 0
            
            StackLayout {
                width: parent.width
                height: parent.height - tabBar.height
                currentIndex: parent.currentView
                
                Rectangle {
                    color: MColors.background
                    
                    Column {
                        anchors.fill: parent
                        anchors.margins: Constants.spacingXLarge
                        spacing: Constants.spacingLarge
                        
                        Item { height: Constants.spacingLarge }
                        
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.min(parent.width, parent.height * 0.5)
                            height: width
                            radius: Constants.borderRadiusSharp
                            color: MColors.surface
                            border.width: Constants.borderWidthThick
                            border.color: MColors.border
                            antialiasing: Constants.enableAntialiasing
                            
                            Icon {
                                anchors.centerIn: parent
                                name: "music-2"
                                size: Constants.iconSizeXLarge * 2
                                color: MColors.accent
                            }
                            
                            RotationAnimation on rotation {
                                from: 0
                                to: 360
                                duration: 10000
                                loops: Animation.Infinite
                                running: isPlaying
                            }
                        }
                        
                        Item { height: Constants.spacingMedium }
                        
                        Column {
                            width: parent.width
                            spacing: Constants.spacingSmall
                            
                            Text {
                                width: parent.width
                                text: currentTrack ? currentTrack.title : "No Track"
                                font.pixelSize: Constants.fontSizeXLarge
                                font.weight: Font.Bold
                                color: MColors.text
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                            
                            Text {
                                width: parent.width
                                text: currentTrack ? currentTrack.artist : "Select a track"
                                font.pixelSize: Constants.fontSizeLarge
                                color: MColors.textSecondary
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                            
                            Text {
                                width: parent.width
                                text: currentTrack ? currentTrack.album : ""
                                font.pixelSize: Constants.fontSizeMedium
                                color: MColors.textTertiary
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                        }
                        
                        Item { height: Constants.spacingMedium }
                        
                           Column {
                               width: parent.width
                               spacing: Constants.spacingSmall

                               MSlider {
                                   width: parent.width
                                   from: 0
                                   to: (currentTrack && currentTrack.duration) ? currentTrack.duration : 100
                                   value: (currentTrack && currentTrack.position) ? currentTrack.position : 0
                                   onMoved: {
                                       if (currentTrack && currentTrack.duration) {
                                           audioPlayer.position = value * 1000
                                       }
                                   }
                               }

                               Row {
                                   width: parent.width

                                   Text {
                                       text: formatTime(currentTrack ? currentTrack.position : 0)
                                       font.pixelSize: Constants.fontSizeSmall
                                       color: MColors.textSecondary
                                   }

                                   Item {
                                       width: parent.width - parent.children[0].width - parent.children[2].width
                                       height: 1
                                   }

                                   Text {
                                       text: formatTime(currentTrack ? currentTrack.duration : 0)
                                       font.pixelSize: Constants.fontSizeSmall
                                       color: MColors.textSecondary
                                   }
                               }
                           }
                        
                        Item { height: Constants.spacingMedium }
                        
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: Constants.spacingLarge
                            
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Constants.touchTargetMedium
                                height: Constants.touchTargetMedium
                                radius: Constants.borderRadiusSharp
                                color: shuffle ? MColors.accent : "transparent"
                                border.width: Constants.borderWidthThin
                                border.color: shuffle ? MColors.accentDark : MColors.border
                                antialiasing: Constants.enableAntialiasing
                                
                                Icon {
                                    anchors.centerIn: parent
                                    name: "shuffle"
                                    size: Constants.iconSizeMedium
                                    color: MColors.text
                                }
                                
                                MouseArea {
                                    anchors.fill: parent
                                    onPressed: {
                                        HapticService.light()
                                    }
                                    onClicked: {
                                        shuffle = !shuffle
                                    }
                                }
                            }
                            
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Constants.touchTargetMedium
                                height: Constants.touchTargetMedium
                                radius: Constants.borderRadiusSharp
                                color: "transparent"
                                border.width: Constants.borderWidthThin
                                border.color: MColors.border
                                antialiasing: Constants.enableAntialiasing
                                
                                Icon {
                                    anchors.centerIn: parent
                                    name: "skip-back"
                                    size: Constants.iconSizeMedium
                                    color: MColors.text
                                }
                                
                                MouseArea {
                                    anchors.fill: parent
                                    onPressed: {
                                        parent.color = MColors.surface
                                        HapticService.light()
                                    }
                                    onReleased: {
                                        parent.color = "transparent"
                                    }
                                    onCanceled: {
                                        parent.color = "transparent"
                                    }
                                    onClicked: {
                                        console.log("Previous track")
                                    }
                                }
                            }
                            
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Constants.touchTargetLarge
                                height: Constants.touchTargetLarge
                                radius: width / 2
                                color: MColors.accent
                                border.width: Constants.borderWidthMedium
                                border.color: MColors.accentDark
                                antialiasing: true
                                
                                Icon {
                                    anchors.centerIn: parent
                                    name: isPlaying ? "pause" : "play"
                                    size: Constants.iconSizeLarge
                                    color: MColors.text
                                }
                                
                                MouseArea {
                                    anchors.fill: parent
                                    onPressed: {
                                        parent.scale = 0.9
                                        HapticService.medium()
                                    }
                                    onReleased: {
                                        parent.scale = 1.0
                                    }
                                    onCanceled: {
                                        parent.scale = 1.0
                                    }
                                    onClicked: {
                                        if (isPlaying) {
                                            audioPlayer.pause()
                                        } else {
                                            if (currentTrack && audioPlayer.playbackState === MediaPlayer.StoppedState) {
                                                audioPlayer.source = currentTrack.path
                                            }
                                            audioPlayer.play()
                                        }
                                    }
                                }
                                
                                Behavior on scale {
                                    NumberAnimation { duration: 100 }
                                }
                            }
                            
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Constants.touchTargetMedium
                                height: Constants.touchTargetMedium
                                radius: Constants.borderRadiusSharp
                                color: "transparent"
                                border.width: Constants.borderWidthThin
                                border.color: MColors.border
                                antialiasing: Constants.enableAntialiasing
                                
                                Icon {
                                    anchors.centerIn: parent
                                    name: "skip-forward"
                                    size: Constants.iconSizeMedium
                                    color: MColors.text
                                }
                                
                                MouseArea {
                                    anchors.fill: parent
                                    onPressed: {
                                        parent.color = MColors.surface
                                        HapticService.light()
                                    }
                                    onReleased: {
                                        parent.color = "transparent"
                                    }
                                    onCanceled: {
                                        parent.color = "transparent"
                                    }
                                    onClicked: {
                                        console.log("Next track")
                                    }
                                }
                            }
                            
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Constants.touchTargetMedium
                                height: Constants.touchTargetMedium
                                radius: Constants.borderRadiusSharp
                                color: repeatMode !== "off" ? MColors.accent : "transparent"
                                border.width: Constants.borderWidthThin
                                border.color: repeatMode !== "off" ? MColors.accentDark : MColors.border
                                antialiasing: Constants.enableAntialiasing
                                
                                Icon {
                                    anchors.centerIn: parent
                                    name: repeatMode === "one" ? "repeat-1" : "repeat"
                                    size: Constants.iconSizeMedium
                                    color: MColors.text
                                }
                                
                                MouseArea {
                                    anchors.fill: parent
                                    onPressed: {
                                        HapticService.light()
                                    }
                                    onClicked: {
                                        if (repeatMode === "off") {
                                            repeatMode = "all"
                                        } else if (repeatMode === "all") {
                                            repeatMode = "one"
                                        } else {
                                            repeatMode = "off"
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                ListView {
                    width: parent.width
                    height: parent.height
                    clip: true
                    topMargin: Constants.spacingMedium
                    
                    model: playlist
                    
                    delegate: Rectangle {
                        width: ListView.view.width
                        height: Constants.touchTargetLarge + Constants.spacingSmall
                        color: "transparent"
                        
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: Constants.spacingMedium
                            anchors.topMargin: 0
                            color: MColors.surface
                            radius: Constants.borderRadiusSharp
                            border.width: Constants.borderWidthThin
                            border.color: index === 0 ? MColors.accent : MColors.border
                            antialiasing: Constants.enableAntialiasing
                            
                            Row {
                                anchors.fill: parent
                                anchors.margins: Constants.spacingMedium
                                spacing: Constants.spacingMedium
                                
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Constants.iconSizeLarge + Constants.spacingMedium
                                    height: Constants.iconSizeLarge + Constants.spacingMedium
                                    radius: Constants.borderRadiusSharp
                                    color: MColors.surface2
                                    border.width: Constants.borderWidthThin
                                    border.color: MColors.border
                                    antialiasing: Constants.enableAntialiasing
                                    
                                    Icon {
                                        anchors.centerIn: parent
                                        name: "music-2"
                                        size: Constants.iconSizeMedium
                                        color: MColors.accent
                                    }
                                }
                                
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - parent.spacing * 3 - Constants.iconSizeLarge - Constants.spacingMedium - 40
                                    spacing: Constants.spacingXSmall
                                    
                                    Text {
                                        width: parent.width
                                        text: modelData.title
                                        font.pixelSize: Constants.fontSizeMedium
                                        font.weight: index === 0 ? Font.Bold : Font.DemiBold
                                        color: index === 0 ? MColors.accent : MColors.text
                                        elide: Text.ElideRight
                                    }
                                    
                                    Row {
                                        spacing: Constants.spacingSmall
                                        
                                        Text {
                                            text: modelData.artist
                                            font.pixelSize: Constants.fontSizeSmall
                                            color: MColors.textSecondary
                                        }
                                        
                                        Text {
                                            text: "•"
                                            font.pixelSize: Constants.fontSizeSmall
                                            color: MColors.textSecondary
                                        }
                                        
                                        Text {
                                            text: formatTime(modelData.duration)
                                            font.pixelSize: Constants.fontSizeSmall
                                            color: MColors.textSecondary
                                        }
                                    }
                                }
                                
                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: index === 0 && isPlaying ? "pause" : "play"
                                    size: Constants.iconSizeMedium
                                    color: index === 0 ? MColors.accent : MColors.textTertiary
                                }
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                onPressed: {
                                    parent.color = MColors.surface2
                                    HapticService.light()
                                }
                                onReleased: {
                                    parent.color = MColors.surface
                                }
                                onCanceled: {
                                    parent.color = MColors.surface
                                }
                                onClicked: {
                                    console.log("Play track:", modelData.title)
                                }
                            }
                        }
                    }
                }
            }
            
            Rectangle {
                id: tabBar
                width: parent.width
                height: Constants.actionBarHeight
                color: MColors.surface
                
                Rectangle {
                    anchors.top: parent.top
                    width: parent.width
                    height: Constants.borderWidthThin
                    color: MColors.border
                }
                
                Row {
                    anchors.fill: parent
                    spacing: 0
                    
                    Repeater {
                        model: [
                            { icon: "disc", label: "Now Playing" },
                            { icon: "library", label: "Library" }
                        ]
                        
                        Rectangle {
                            width: tabBar.width / 2
                            height: tabBar.height
                            color: "transparent"
                            
                            Rectangle {
                                anchors.top: parent.top
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width * 0.8
                                height: Constants.borderWidthThick
                                color: MColors.accent
                                opacity: tabBar.parent.currentView === index ? 1.0 : 0.0
                                
                                Behavior on opacity {
                                    NumberAnimation { duration: Constants.animationFast }
                                }
                            }
                            
                            Column {
                                anchors.centerIn: parent
                                spacing: Constants.spacingXSmall
                                
                                Icon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    name: modelData.icon
                                    size: Constants.iconSizeMedium
                                    color: tabBar.parent.currentView === index ? MColors.accent : MColors.textSecondary
                                    
                                    Behavior on color {
                                        ColorAnimation { duration: Constants.animationFast }
                                    }
                                }
                                
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.label
                                    font.pixelSize: Constants.fontSizeXSmall
                                    color: tabBar.parent.currentView === index ? MColors.accent : MColors.textSecondary
                                    font.weight: tabBar.parent.currentView === index ? Font.DemiBold : Font.Normal
                                    
                                    Behavior on color {
                                        ColorAnimation { duration: Constants.animationFast }
                                    }
                                }
                            }
                            
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    HapticService.light()
                                    tabBar.parent.currentView = index
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
