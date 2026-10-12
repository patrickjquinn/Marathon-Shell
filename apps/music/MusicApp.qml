pragma ComponentBehavior: Bound

import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Feedback
import MarathonUI.Navigation
import MarathonUI.Theme
import QtMultimedia
import QtQuick
import QtQuick.Layouts

MApp {
    id: musicApp

    property var playbackErrorBarRef: null

    property var currentTrack: null
    property bool isPlaying: audioPlayer.playbackState === MediaPlayer.PlayingState
    property bool shuffle: false
    property string repeatMode: "off"
    property var playlist
    readonly property bool libraryAvailable: typeof MusicLibraryManager !== 'undefined'
    readonly property bool scanning: libraryAvailable && MusicLibraryManager.isScanning

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

                MusicLibraryManager.scanLibraryAsync();
            }
        });
    }

    Connections {
        function onScanComplete(trackCount) {
            Logger.info("Music", "Library scan complete: " + trackCount + " tracks");
            if (typeof MusicLibraryManager !== 'undefined') {
                musicApp.playlist = MusicLibraryManager.getAllTracks();
                if (musicApp.playlist.length > 0 && !musicApp.currentTrack)
                    musicApp.currentTrack = musicApp.playlist[0];
            }
        }

        target: typeof MusicLibraryManager !== 'undefined' ? MusicLibraryManager : null
    }

    MediaPlayer {
        id: audioPlayer

        onPositionChanged: {
            if (musicApp.currentTrack && musicApp.currentTrack.duration) {
                var newPos = position / 1000;
                if (!isNaN(newPos) && isFinite(newPos))
                    musicApp.currentTrack.position = newPos;
            }
        }
        onDurationChanged: {
            if (musicApp.currentTrack && duration > 0) {
                var newDur = duration / 1000;
                if (!isNaN(newDur) && isFinite(newDur))
                    musicApp.currentTrack.duration = newDur;
            }
        }
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.EndOfMedia && musicApp.currentTrack)
                musicApp.playNext();
        }
        onErrorOccurred: function (error, errorString) {
            Logger.error("Music", "Playback error: " + errorString);
            const title = musicApp.currentTrack ? "\u201C" + musicApp.currentTrack.title + "\u201D" : "this track";
            if (musicApp.playbackErrorBarRef)
                musicApp.playbackErrorBarRef.show("Can't play " + title + ". The file may be missing or in an unsupported format.", "Next");
        }

        audioOutput: AudioOutput {
            id: audioOutput
        }
    }

    content: Rectangle {
        id: musicRoot
        anchors.fill: parent
        color: MColors.background

        Column {
            property int currentView: 0

            anchors.fill: parent
            spacing: 0

            StackLayout {
                // Size from the content root, NOT parent.width: the parent is
                // a Column positioner and `width: parent.width` there forms a
                // circular dependency that resolves to 0, collapsing the whole
                // Now Playing view (album bay especially).
                width: musicRoot.width
                height: musicRoot.height - tabBar.height
                currentIndex: parent.currentView

                // Marathon DS · Music Now Playing (screens-shell.jsx:MusicNowPlaying).
                //
                // Top eyebrow row · square album bay with stripe-pattern
                // placeholder · 32/Bold title + artist·album subtitle ·
                // halo'd teal scrubber + tnum times · 5-button transport
                // (shuffle · prev · big play circle · next · heart).
                Rectangle {
                    id: nowPlayingFrame
                    // StackLayout children default to implicit size (0 for a
                    // Rectangle) unless they opt into filling — without this
                    // the whole Now Playing view laid out against width 0,
                    // collapsing the album bay.
                    Layout.fillWidth: true
                    Layout.fillHeight: true
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
                        // 8 px clears the app's top edge but the app fills the
                        // full screen including the area under the shell's
                        // 56-px status bar — "PLAYING FROM" was rendering
                        // half-under the clock. Push the column below the
                        // status-bar safe-area inset.
                        anchors.topMargin: Constants.safeAreaTop + 8
                        spacing: 14

                        // ── Eyebrow row — PLAYING FROM ──
                        Item {
                            width: parent.width
                            height: 40

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
                                    text: musicApp.currentTrack && musicApp.currentTrack.album ? musicApp.currentTrack.album : "Library"
                                    color: MColors.textPrimary
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: MTypography.sizeSubhead
                                    font.weight: Font.Medium
                                }
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
                            // NO anchors.horizontalCenter here: combined with
                            // width: parent.width inside a Column it conflicts
                            // and collapses the bay to implicit (glyph) size.
                            // width: parent.width alone fills the column.
                            width: parent.width
                            height: width
                            radius: MRadius.md
                            border.width: 1
                            border.color: MColors.tealBorder
                            gradient: Gradient {
                                GradientStop {
                                    position: 0
                                    color: Qt.rgba(0, 140 / 255, 122 / 255, 1.0)
                                }
                                GradientStop {
                                    position: 1
                                    color: Qt.rgba(6 / 255, 30 / 255, 27 / 255, 1.0)
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
                                        required property int index

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
                                text: musicApp.currentTrack ? musicApp.currentTrack.title : "No Track"
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
                                    if (!musicApp.currentTrack)
                                        return "Select a track";
                                    const a = musicApp.currentTrack.artist || "";
                                    const b = musicApp.currentTrack.album || "";
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
                                to: (musicApp.currentTrack && musicApp.currentTrack.duration) ? musicApp.currentTrack.duration : 100
                                value: (musicApp.currentTrack && musicApp.currentTrack.position) ? musicApp.currentTrack.position : 0
                                onMoved: {
                                    if (musicApp.currentTrack && musicApp.currentTrack.duration)
                                        audioPlayer.position = value * 1000;
                                }
                            }

                            Item {
                                width: parent.width
                                height: 16

                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: musicApp.formatTime(musicApp.currentTrack ? musicApp.currentTrack.position : 0)
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
                                    text: musicApp.formatTime(musicApp.currentTrack ? musicApp.currentTrack.duration : 0)
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

                    // ── Transport row — shuffle · prev · play · next ──
                    // Anchored to bottom of the parent Rectangle so the
                    // controls hug the nav bar instead of stacking under
                    // the scrubber (used to leave ~500 px of dead space
                    // between the transport row and the bottom tab bar).
                    Row {
                        id: nowPlayingTransport
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Constants.navBarHeight + 36
                        spacing: 18

                        // Shuffle — accent icon, no bay.
                        Item {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Constants.touchTargetMinimum
                            height: Constants.touchTargetMinimum
                            Accessible.role: Accessible.CheckBox
                            Accessible.name: "Shuffle"
                            Accessible.checkable: true
                            Accessible.checked: musicApp.shuffle
                            Accessible.onPressAction: musicApp.shuffle = !musicApp.shuffle
                            Icon {
                                anchors.centerIn: parent
                                name: "shuffle"
                                size: 20
                                color: musicApp.shuffle ? MColors.marathonTealBright : MColors.textTertiary
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    HapticService.light();
                                    musicApp.shuffle = !musicApp.shuffle;
                                }
                            }
                        }

                        // Previous — dark circle.
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Constants.touchTargetMinimum
                            height: Constants.touchTargetMinimum
                            radius: width / 2
                            enabled: musicApp.currentTrack !== null
                            opacity: enabled ? 1 : 0.4
                            Accessible.role: Accessible.Button
                            Accessible.name: "Previous track"
                            Accessible.onPressAction: musicApp.playPrevious()
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
                                    musicApp.playPrevious();
                                }
                            }
                            Behavior on color {
                                ColorAnimation {
                                    duration: MMotion.micro
                                }
                            }
                        }

                        // Play / pause — 64 teal-gradient with halo.
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 64
                            height: 64
                            radius: width / 2
                            enabled: musicApp.currentTrack !== null
                            opacity: enabled ? 1 : 0.4
                            Accessible.role: Accessible.Button
                            Accessible.name: musicApp.isPlaying ? "Pause" : "Play"
                            Accessible.onPressAction: playArea.togglePlayback()
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

                            // Play/pause icon morph — was a hard
                            // name swap which flickered through the
                            // glyph atlas reload. Crossfade between
                            // two stacked Icons via state-driven
                            // opacity keeps the visual continuous.
                            Item {
                                anchors.centerIn: parent
                                width: 26
                                height: 26
                                Icon {
                                    anchors.centerIn: parent
                                    name: "pause"
                                    size: 26
                                    color: MColors.textOnAccent
                                    opacity: musicApp.isPlaying ? 1 : 0
                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: MMotion.durationFor("tap")
                                        }
                                    }
                                }
                                Icon {
                                    anchors.centerIn: parent
                                    name: "play"
                                    size: 26
                                    color: MColors.textOnAccent
                                    opacity: musicApp.isPlaying ? 0 : 1
                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: MMotion.durationFor("tap")
                                        }
                                    }
                                }
                            }

                            scale: playArea.pressed ? 0.94 : 1.0
                            // Spring-driven press feedback per the M3 Expressive
                            // motion ladder — replaces OutBack overshoot with
                            // tunable physics on the "tap" role.
                            Behavior on scale {
                                SpringAnimation {
                                    spring: MMotion.stiffnessSpatialFor("tap")
                                    damping: MMotion.dampingSpatialFor("tap")
                                    epsilon: MMotion.epsilon
                                }
                            }

                            MouseArea {
                                id: playArea
                                anchors.fill: parent
                                function togglePlayback() {
                                    if (musicApp.isPlaying) {
                                        audioPlayer.pause();
                                    } else {
                                        if (musicApp.currentTrack && audioPlayer.playbackState === MediaPlayer.StoppedState)
                                            audioPlayer.source = musicApp.currentTrack.path;
                                        audioPlayer.play();
                                    }
                                }

                                onClicked: {
                                    HapticService.medium();
                                    togglePlayback();
                                }
                            }
                        }

                        // Next — dark circle.
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Constants.touchTargetMinimum
                            height: Constants.touchTargetMinimum
                            radius: width / 2
                            enabled: musicApp.currentTrack !== null
                            opacity: enabled ? 1 : 0.4
                            Accessible.role: Accessible.Button
                            Accessible.name: "Next track"
                            Accessible.onPressAction: musicApp.playNext()
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
                                    musicApp.playNext();
                                }
                            }
                            Behavior on color {
                                ColorAnimation {
                                    duration: MMotion.micro
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
                    model: musicApp.playlist

                    Column {
                        anchors.centerIn: parent
                        spacing: MSpacing.md
                        visible: musicApp.scanning && musicApp.playlist.length === 0

                        MActivityIndicator {
                            anchors.horizontalCenter: parent.horizontalCenter
                            running: parent.visible
                        }

                        MLabel {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Looking for music\u2026"
                            variant: "secondary"
                        }
                    }

                    MEmptyState {
                        anchors.fill: parent
                        visible: !musicApp.scanning && musicApp.playlist.length === 0
                        iconName: "music-2"
                        iconSize: 96
                        title: musicApp.libraryAvailable ? "No music yet" : "Music library unavailable"
                        message: musicApp.libraryAvailable ? "Copy audio files (MP3, FLAC, OGG and more) into the Music folder in your home folder (~/Music). They'll appear here automatically." : "Music couldn't connect to the music library, so your songs can't be listed."
                    }

                    delegate: Item {
                        id: trackRow

                        required property var modelData
                        readonly property bool isCurrent: musicApp.currentTrack !== null && modelData.id === musicApp.currentTrack.id

                        width: ListView.view.width
                        height: Constants.touchTargetLarge + MSpacing.sm

                        MCard {
                            Accessible.role: Accessible.Button
                            Accessible.name: trackRow.modelData.title + ", " + trackRow.modelData.artist
                            Accessible.onPressAction: musicApp.playTrack(trackRow.modelData)
                            anchors.fill: parent
                            anchors.margins: MSpacing.md
                            anchors.topMargin: 0
                            interactive: true
                            elevation: trackRow.isCurrent ? 2 : 1
                            onClicked: {
                                HapticService.light();
                                musicApp.playTrack(trackRow.modelData);
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
                                        text: trackRow.modelData.title
                                        variant: trackRow.isCurrent ? "accent" : "primary"
                                        font.pixelSize: MTypography.sizeBody
                                        font.weight: trackRow.isCurrent ? Font.Bold : Font.DemiBold
                                        elide: Text.ElideRight
                                    }

                                    Row {
                                        spacing: MSpacing.sm

                                        MLabel {
                                            text: trackRow.modelData.artist
                                            variant: "secondary"
                                            font.pixelSize: MTypography.sizeSmall
                                        }

                                        MLabel {
                                            text: "•"
                                            variant: "secondary"
                                            font.pixelSize: MTypography.sizeSmall
                                        }

                                        MLabel {
                                            text: musicApp.formatTime(trackRow.modelData.duration)
                                            variant: "secondary"
                                            font.pixelSize: MTypography.sizeSmall
                                        }
                                    }
                                }

                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: trackRow.isCurrent && musicApp.isPlaying ? "pause" : "play"
                                    size: Constants.iconSizeMedium
                                    color: trackRow.isCurrent ? MColors.marathonTeal : MColors.textTertiary
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

        MSnackbar {
            id: playbackErrorBar
            Component.onCompleted: musicApp.playbackErrorBarRef = playbackErrorBar

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: MSpacing.md
            anchors.bottomMargin: tabBar.height + MSpacing.md
            timeout: 8000
            onActionTriggered: musicApp.playNext()
        }
    }
}
