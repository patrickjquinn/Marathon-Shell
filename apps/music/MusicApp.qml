import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Navigation
import MarathonUI.Theme
import QtMultimedia
import QtQuick
import QtQuick.Layouts

MApp {
    id: musicApp

    property var currentTrack: null
    property bool isPlaying: audioPlayer.playbackState === MediaPlayer.PlayingState
    property bool shuffle: false
    property string repeatMode: "off"
    property var playlist

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
        if (repeatMode === "single")
            playTrack(currentTrack);
        else
            playTrack(playlist[nextIndex]);
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

    appId: "music"
    appName: "Music"
    appIcon: "assets/icon.svg"
    Component.onCompleted: {
        playlist = [];
        Qt.callLater(function () {
            if (typeof MusicLibraryManager !== 'undefined') {
                playlist = MusicLibraryManager.getAllTracks();
                if (playlist.length > 0)
                    currentTrack = playlist[0];

                MusicLibraryManager.scanLibrary();
            }
        });
    }

    Connections {
        function onScanComplete(trackCount) {
            Logger.info("Music", "Library scan complete: " + trackCount + " tracks");
            if (typeof MusicLibraryManager !== 'undefined') {
                playlist = MusicLibraryManager.getAllTracks();
                if (playlist.length > 0 && !currentTrack)
                    currentTrack = playlist[0];
            }
        }

        target: typeof MusicLibraryManager !== 'undefined' ? MusicLibraryManager : null
    }

    MediaPlayer {
        id: audioPlayer

        onPositionChanged: {
            if (currentTrack && currentTrack.duration) {
                var newPos = position / 1000;
                if (!isNaN(newPos) && isFinite(newPos))
                    currentTrack.position = newPos;
            }
        }
        onDurationChanged: {
            if (currentTrack && duration > 0) {
                var newDur = duration / 1000;
                if (!isNaN(newDur) && isFinite(newDur))
                    currentTrack.duration = newDur;
            }
        }
        onPlaybackStateChanged: {
            if (playbackState === MediaPlayer.StoppedState && currentTrack)
                playNext();
        }
        onErrorOccurred: function (error, errorString) {
            Logger.error("Music", "Playback error: " + errorString);
        }

        audioOutput: AudioOutput {
            id: audioOutput
        }
    }

    content: Rectangle {
        anchors.fill: parent
        color: MColors.background

        Column {
            property int currentView: 0

            anchors.fill: parent
            spacing: 0

            StackLayout {
                width: parent.width
                height: parent.height - tabBar.height
                currentIndex: parent.currentView

                // Marathon DS · Music Now Playing (screens-shell.jsx:MusicNowPlaying).
                //
                // Top eyebrow row · square album bay with stripe-pattern
                // placeholder · 32/Bold title + artist·album subtitle ·
                // halo'd teal scrubber + tnum times · 5-button transport
                // (shuffle · prev · big play circle · next · heart).
                Rectangle {
                    id: nowPlayingFrame
                    color: MColors.background

                    // Top column: eyebrow, album bay, track info, scrubber.
                    // Packs from the top. Transport row is anchored to the
                    // bottom separately so the empty vertical space sits in
                    // the middle as breathing room, NOT as dead space under
                    // the controls (iOS / BB10 Music both anchor playback
                    // controls to the bottom for this reason).
                    Column {
                        id: nowPlayingTopColumn
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        anchors.topMargin: 8
                        spacing: 14

                        // ── Eyebrow row — chevron + PLAYING FROM + more ──
                        Item {
                            width: parent.width
                            height: 40

                            Icon {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                name: "chevron-down"
                                size: 22
                                color: MColors.textSecondary
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: 1
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "PLAYING FROM"
                                    color: MColors.textSecondary
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: MTypography.sizeEyebrow
                                    font.weight: Font.Bold
                                    font.letterSpacing: MTypography.trackingEyebrow
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: currentTrack && currentTrack.album ? currentTrack.album : "Library"
                                    color: MColors.textPrimary
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: MTypography.sizeSubhead
                                    font.weight: Font.Medium
                                }
                            }

                            Icon {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                name: "ellipsis-vertical"
                                size: 22
                                color: MColors.textSecondary
                            }
                        }

                        // ── Album bay — square, gradient + stripe pattern ──
                        // Cap-was-320 left the lower half of the Now Playing
                        // surface as dead space below the transport row on
                        // tall canvases (720×1440 reserved ~500 px for
                        // nothing). Iterate to the full surface width so
                        // the album-art square fills the upper viewport
                        // the same way iOS Music does, and the transport
                        // row sits at a natural distance below the scrubber.
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width
                            height: width
                            radius: MRadius.md
                            border.width: 1
                            border.color: MColors.tealBorder
                            gradient: Gradient {
                                GradientStop {
                                    position: 0
                                    color: Qt.rgba(0, 89 / 255, 77 / 255, 0.65)
                                }
                                GradientStop {
                                    position: 1
                                    color: Qt.rgba(4 / 255, 4 / 255, 4 / 255, 0.85)
                                }
                            }
                            clip: true

                            // Vertical-stripe texture per JSX: ~16 thin teal
                            // strokes spaced across the bay, low-alpha.
                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 14
                                spacing: (width - 28 - 16) / 15
                                Repeater {
                                    model: 16
                                    Rectangle {
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: 1
                                        color: MColors.marathonTealBright
                                        opacity: 0.18 + (index % 3) * 0.06
                                    }
                                }
                            }

                            // Centred wave glyph — replaces the rotating
                            // music note. Per the JSX album-bay glyph (an
                            // 80 px teal-bright tilde wave).
                            Text {
                                anchors.centerIn: parent
                                text: "∿"
                                color: MColors.marathonTealBright
                                font.family: MTypography.fontFamily
                                font.pixelSize: 96
                                font.weight: Font.Light
                            }
                        }

                        // ── Title + artist · album ────────────────────
                        Column {
                            width: parent.width
                            spacing: 2

                            Text {
                                width: parent.width
                                text: currentTrack ? currentTrack.title : "No Track"
                                color: MColors.textPrimary
                                font.family: MTypography.fontFamily
                                font.pixelSize: 28
                                font.weight: Font.Bold
                                font.letterSpacing: -0.4
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: {
                                    if (!currentTrack)
                                        return "Select a track";
                                    const a = currentTrack.artist || "";
                                    const b = currentTrack.album || "";
                                    return (a && b) ? a + " · " + b : (a || b);
                                }
                                color: MColors.textSecondary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeSubhead
                                font.weight: Font.Normal
                                elide: Text.ElideRight
                            }
                        }

                        // ── Scrubber + tnum timestamps ─────────────────
                        Column {
                            width: parent.width
                            spacing: 6

                            MSlider {
                                width: parent.width
                                from: 0
                                to: (currentTrack && currentTrack.duration) ? currentTrack.duration : 100
                                value: (currentTrack && currentTrack.position) ? currentTrack.position : 0
                                onMoved: {
                                    if (currentTrack && currentTrack.duration)
                                        audioPlayer.position = value * 1000;
                                }
                            }

                            Item {
                                width: parent.width
                                height: 16

                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: formatTime(currentTrack ? currentTrack.position : 0)
                                    color: MColors.textSecondary
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: MTypography.sizeFootnote
                                    font.features: ({
                                            "tnum": 1
                                        })
                                }
                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: formatTime(currentTrack ? currentTrack.duration : 0)
                                    color: MColors.textSecondary
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: MTypography.sizeFootnote
                                    font.features: ({
                                            "tnum": 1
                                        })
                                }
                            }
                        }
                    }

                    // ── Transport row — shuffle · prev · play · next · heart ──
                    // Anchored to bottom of the parent Rectangle so the
                    // controls hug the nav bar instead of stacking under
                    // the scrubber (used to leave ~500 px of dead space
                    // between the heart button and the bottom tab bar).
                    Row {
                        id: nowPlayingTransport
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Constants.navBarHeight + 36
                        spacing: 18

                        // Shuffle — accent icon, no bay.
                        Item {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 32
                            height: 32
                            Icon {
                                anchors.centerIn: parent
                                name: "shuffle"
                                size: 20
                                color: shuffle ? MColors.marathonTealBright : MColors.textTertiary
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    HapticService.light();
                                    shuffle = !shuffle;
                                }
                            }
                        }

                        // Previous — 42 dark circle.
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 42
                            height: 42
                            radius: width / 2
                            color: prevArea.pressed ? MColors.bb10Card : MColors.elev2
                            border.width: 1
                            border.color: MColors.whiteOverlay04
                            Icon {
                                anchors.centerIn: parent
                                name: "skip-back"
                                size: 18
                                color: MColors.textPrimary
                            }
                            MouseArea {
                                id: prevArea
                                anchors.fill: parent
                                onClicked: {
                                    HapticService.light();
                                    playPrevious();
                                }
                            }
                            Behavior on color {
                                ColorAnimation {
                                    duration: 80
                                }
                            }
                        }

                        // Play / pause — 64 teal-gradient with halo.
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 64
                            height: 64
                            radius: width / 2
                            border.width: 1
                            border.color: MColors.tealBorder
                            gradient: Gradient {
                                GradientStop {
                                    position: 0
                                    color: MColors.marathonTealBright
                                }
                                GradientStop {
                                    position: 1
                                    color: MColors.marathonTealDark
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 1
                                radius: width / 2
                                color: "transparent"
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.3)
                            }

                            Icon {
                                anchors.centerIn: parent
                                name: isPlaying ? "pause" : "play"
                                size: 26
                                color: "#000000"
                            }

                            scale: playArea.pressed ? 0.94 : 1.0
                            Behavior on scale {
                                NumberAnimation {
                                    duration: 120
                                    easing.type: Easing.OutBack
                                }
                            }

                            MouseArea {
                                id: playArea
                                anchors.fill: parent
                                onClicked: {
                                    HapticService.medium();
                                    if (isPlaying) {
                                        audioPlayer.pause();
                                    } else {
                                        if (currentTrack && audioPlayer.playbackState === MediaPlayer.StoppedState)
                                            audioPlayer.source = currentTrack.path;
                                        audioPlayer.play();
                                    }
                                }
                            }
                        }

                        // Next — 42 dark circle.
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 42
                            height: 42
                            radius: width / 2
                            color: nextArea.pressed ? MColors.bb10Card : MColors.elev2
                            border.width: 1
                            border.color: MColors.whiteOverlay04
                            Icon {
                                anchors.centerIn: parent
                                name: "skip-forward"
                                size: 18
                                color: MColors.textPrimary
                            }
                            MouseArea {
                                id: nextArea
                                anchors.fill: parent
                                onClicked: {
                                    HapticService.light();
                                    playNext();
                                }
                            }
                            Behavior on color {
                                ColorAnimation {
                                    duration: 80
                                }
                            }
                        }

                        // Heart — accent icon, no bay. JSX puts heart
                        // here in place of repeat; repeat stays
                        // available via a long-press of the scrubber
                        // (TBD).
                        Item {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 32
                            height: 32
                            Icon {
                                anchors.centerIn: parent
                                name: currentTrack && currentTrack.favorited ? "heart" : "heart"
                                size: 20
                                color: (currentTrack && currentTrack.favorited) ? MColors.marathonTealBright : MColors.textTertiary
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: HapticService.light()
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

                    MEmptyState {
                        anchors.fill: parent
                        visible: playlist.length === 0
                        iconName: "music-2"
                        iconSize: 96
                        title: "No Music Yet"
                        message: "Your music library is empty. Add some music files to get started!"
                    }

                    delegate: Item {
                        width: ListView.view.width
                        height: Constants.touchTargetLarge + MSpacing.sm

                        MCard {
                            anchors.fill: parent
                            anchors.margins: MSpacing.md
                            anchors.topMargin: 0
                            interactive: true
                            elevation: index === 0 ? 2 : 1
                            onClicked: {
                                HapticService.light();
                                playTrack(modelData);
                            }

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
                        }
                    }
                }
            }

            MTabBar {
                id: tabBar

                width: parent.width
                activeTab: parent.currentView
                tabs: [
                    {
                        "label": "Now Playing",
                        "icon": "disc"
                    },
                    {
                        "label": "Library",
                        "icon": "music-notes"
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
