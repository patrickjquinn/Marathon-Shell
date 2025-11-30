import QtQuick
import QtQuick.Layouts
import QtMultimedia
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Theme
import MarathonUI.Navigation

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
        // Initialize with empty playlist first (instant load)
        playlist = [];

        // Defer heavy operations to avoid blocking app launch
        Qt.callLater(function () {
            if (typeof MusicLibraryManager !== 'undefined') {
                // Get cached tracks first (fast)
                playlist = MusicLibraryManager.getAllTracks();
                if (playlist.length > 0) {
                    currentTrack = playlist[0];
                }
                // Then scan in background (slow, non-blocking)
                MusicLibraryManager.scanLibrary();
            }
        });
    }

    Connections {
        target: typeof MusicLibraryManager !== 'undefined' ? MusicLibraryManager : null
        function onScanComplete(trackCount) {
            Logger.info("Music", "Library scan complete: " + trackCount + " tracks");
            playlist = MusicLibraryManager.getAllTracks();
            if (playlist.length > 0 && !currentTrack) {
                currentTrack = playlist[0];
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
                var newPos = position / 1000;
                if (!isNaN(newPos) && isFinite(newPos)) {
                    currentTrack.position = newPos;
                }
            }
        }

        onDurationChanged: {
            if (currentTrack && duration > 0) {
                var newDur = duration / 1000;
                if (!isNaN(newDur) && isFinite(newDur)) {
                    currentTrack.duration = newDur;
                }
            }
        }

        onPlaybackStateChanged: {
            if (playbackState === MediaPlayer.StoppedState && currentTrack) {
                playNext();
            }
        }

        onErrorOccurred: function (error, errorString) {
            Logger.error("Music", "Playback error: " + errorString);
        }
    }

    function playTrack(track) {
        if (!track)
            return;
        currentTrack = track;
        currentTrack.position = 0;
        audioPlayer.source = track.path;
        audioPlayer.play();
        Logger.info("Music", "Playing: " + track.title + " by " + track.artist);
    }

    function playNext() {
        if (playlist.length === 0)
            return;
        var currentIndex = -1;
        for (var i = 0; i < playlist.length; i++) {
            if (playlist[i].id === currentTrack.id) {
                currentIndex = i;
                break;
            }
        }

        var nextIndex;
        if (shuffle) {
            // True random shuffle - exclude current track
            do {
                nextIndex = Math.floor(Math.random() * playlist.length);
            } while (nextIndex === currentIndex && playlist.length > 1)
        } else {
            nextIndex = (currentIndex + 1) % playlist.length;
        }

        if (repeatMode === "off" && nextIndex <= currentIndex && !shuffle) {
            audioPlayer.stop();
            return;
        }

        if (repeatMode === "single") {
            playTrack(currentTrack);
        } else {
            playTrack(playlist[nextIndex]);
        }
    }

    function playPrevious() {
        if (playlist.length === 0)
            return;
        var currentIndex = -1;
        for (var i = 0; i < playlist.length; i++) {
            if (playlist[i].id === currentTrack.id) {
                currentIndex = i;
                break;
            }
        }

        var prevIndex = (currentIndex - 1 + playlist.length) % playlist.length;
        playTrack(playlist[prevIndex]);
    }

    function formatTime(seconds) {
        var mins = Math.floor(seconds / 60);
        var secs = Math.floor(seconds % 60);
        return mins + ":" + (secs < 10 ? "0" : "") + secs;
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
                        anchors.margins: MSpacing.xl
                        anchors.bottomMargin: Constants.navBarHeight + MSpacing.xl  // Account for system nav bar
                        spacing: MSpacing.lg

                        Item {
                            height: MSpacing.lg
                        }

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
                                color: MColors.marathonTeal
                            }

                            RotationAnimation on rotation {
                                from: 0
                                to: 360
                                duration: 10000
                                loops: Animation.Infinite
                                running: isPlaying
                            }
                        }

                        Item {
                            height: MSpacing.md
                        }

                        Column {
                            width: parent.width
                            spacing: MSpacing.sm

                            MLabel {
                                width: parent.width
                                text: currentTrack ? currentTrack.title : "No Track"
                                variant: "primary"
                                font.pixelSize: MTypography.sizeXLarge
                                font.weight: Font.Bold
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }

                            MLabel {
                                width: parent.width
                                text: currentTrack ? currentTrack.artist : "Select a track"
                                variant: "secondary"
                                font.pixelSize: MTypography.sizeLarge
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }

                            MLabel {
                                width: parent.width
                                text: currentTrack ? currentTrack.album : ""
                                variant: "tertiary"
                                font.pixelSize: MTypography.sizeBody
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                        }

                        Item {
                            height: MSpacing.md
                        }

                        Column {
                            width: parent.width
                            spacing: MSpacing.sm

                            MSlider {
                                width: parent.width
                                from: 0
                                to: (currentTrack && currentTrack.duration) ? currentTrack.duration : 100
                                value: (currentTrack && currentTrack.position) ? currentTrack.position : 0
                                onMoved: {
                                    if (currentTrack && currentTrack.duration) {
                                        audioPlayer.position = value * 1000;
                                    }
                                }
                            }

                            Row {
                                width: parent.width

                                MLabel {
                                    text: formatTime(currentTrack ? currentTrack.position : 0)
                                    variant: "secondary"
                                    font.pixelSize: MTypography.sizeSmall
                                }

                                Item {
                                    width: parent.width - parent.children[0].width - parent.children[2].width
                                    height: 1
                                }

                                MLabel {
                                    text: formatTime(currentTrack ? currentTrack.duration : 0)
                                    variant: "secondary"
                                    font.pixelSize: MTypography.sizeSmall
                                }
                            }
                        }

                        Item {
                            height: MSpacing.md
                        }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: MSpacing.lg

                            MIconButton {
                                anchors.verticalCenter: parent.verticalCenter
                                iconName: "shuffle"
                                iconSize: Constants.iconSizeMedium
                                variant: shuffle ? "primary" : "secondary"
                                onClicked: {
                                    HapticService.light();
                                    shuffle = !shuffle;
                                }
                            }

                            MIconButton {
                                anchors.verticalCenter: parent.verticalCenter
                                iconName: "skip-back"
                                iconSize: Constants.iconSizeMedium
                                variant: "secondary"
                                onClicked: {
                                    HapticService.light();
                                    playPrevious();
                                }
                            }

                            MCircularIconButton {
                                anchors.verticalCenter: parent.verticalCenter
                                iconName: isPlaying ? "pause" : "play"
                                iconSize: Constants.iconSizeLarge
                                buttonSize: Constants.touchTargetLarge
                                variant: "primary"
                                onClicked: {
                                    HapticService.medium();
                                    if (isPlaying) {
                                        audioPlayer.pause();
                                    } else {
                                        if (currentTrack && audioPlayer.playbackState === MediaPlayer.StoppedState) {
                                            audioPlayer.source = currentTrack.path;
                                        }
                                        audioPlayer.play();
                                    }
                                }
                            }

                            MIconButton {
                                anchors.verticalCenter: parent.verticalCenter
                                iconName: "skip-forward"
                                iconSize: Constants.iconSizeMedium
                                variant: "secondary"
                                onClicked: {
                                    HapticService.light();
                                    playNext();
                                }
                            }

                            MIconButton {
                                anchors.verticalCenter: parent.verticalCenter
                                iconName: repeatMode === "one" ? "repeat-1" : "repeat"
                                iconSize: Constants.iconSizeMedium
                                variant: repeatMode !== "off" ? "primary" : "secondary"
                                onClicked: {
                                    HapticService.light();
                                    if (repeatMode === "off") {
                                        repeatMode = "all";
                                    } else if (repeatMode === "all") {
                                        repeatMode = "one";
                                    } else {
                                        repeatMode = "off";
                                    }
                                }
                            }
                        }
                    }
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    topMargin: MSpacing.md

                    model: playlist

                    delegate: Item {
                        width: ListView.view.width
                        height: Constants.touchTargetLarge + MSpacing.sm

                        MCard {
                            anchors.fill: parent
                            anchors.margins: MSpacing.md
                            anchors.topMargin: 0
                            interactive: true
                            elevation: index === 0 ? 2 : 1

                            Row {
                                anchors.fill: parent
                                spacing: MSpacing.md

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Constants.iconSizeLarge + MSpacing.md
                                    height: Constants.iconSizeLarge + MSpacing.md
                                    radius: Constants.borderRadiusSharp
                                    color: MColors.elevated
                                    border.width: Constants.borderWidthThin
                                    border.color: MColors.border
                                    antialiasing: Constants.enableAntialiasing

                                    Icon {
                                        anchors.centerIn: parent
                                        name: "music-2"
                                        size: Constants.iconSizeMedium
                                        color: MColors.marathonTeal
                                    }
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - parent.spacing * 3 - Constants.iconSizeLarge - MSpacing.md - 40
                                    spacing: MSpacing.xs

                                    MLabel {
                                        width: parent.width
                                        text: modelData.title
                                        variant: index === 0 ? "accent" : "primary"
                                        font.pixelSize: MTypography.sizeBody
                                        font.weight: index === 0 ? Font.Bold : Font.DemiBold
                                        elide: Text.ElideRight
                                    }

                                    Row {
                                        spacing: MSpacing.sm

                                        MLabel {
                                            text: modelData.artist
                                            variant: "secondary"
                                            font.pixelSize: MTypography.sizeSmall
                                        }

                                        MLabel {
                                            text: "•"
                                            variant: "secondary"
                                            font.pixelSize: MTypography.sizeSmall
                                        }

                                        MLabel {
                                            text: formatTime(modelData.duration)
                                            variant: "secondary"
                                            font.pixelSize: MTypography.sizeSmall
                                        }
                                    }
                                }

                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: index === 0 && isPlaying ? "pause" : "play"
                                    size: Constants.iconSizeMedium
                                    color: index === 0 ? MColors.marathonTeal : MColors.textTertiary
                                }
                            }

                            onClicked: {
                                HapticService.light();
                                playTrack(modelData);
                            }
                        }
                    }

                    MEmptyState {
                        anchors.fill: parent
                        visible: playlist.length === 0
                        iconName: "music-2"
                        iconSize: 96
                        title: "No Music Yet"
                        message: "Your music library is empty. Add some music files to get started!"
                    }
                }
            }

            MTabBar {
                id: tabBar
                width: parent.width
                activeTab: parent.currentView

                tabs: [
                    {
                        label: "Now Playing",
                        icon: "disc"
                    },
                    {
                        label: "Library",
                        icon: "library"
                    }
                ]

                onTabSelected: index => {
                    HapticService.light();
                    tabBar.parent.currentView = index;
                }
            }
        }
    }
}
