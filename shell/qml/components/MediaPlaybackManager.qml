import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

// Media Playback Manager
// Shows currently playing media with playback controls
// ALWAYS VISIBLE - shows "No media" state when nothing playing
Rectangle {
    id: mediaManager

    // MPRIS2 Integration - Real media player control
    readonly property bool hasMedia: MPRIS2Controller ? MPRIS2Controller.hasActivePlayer : false
    readonly property bool isPlaying: MPRIS2Controller ? MPRIS2Controller.isPlaying : false
    readonly property string trackTitle: MPRIS2Controller && MPRIS2Controller.hasActivePlayer ? (MPRIS2Controller.trackTitle || "Unknown Track") : "No media playing"
    readonly property string artist: MPRIS2Controller ? MPRIS2Controller.trackArtist : ""
    readonly property string albumArt: MPRIS2Controller ? MPRIS2Controller.albumArtUrl : ""
    readonly property real progress: MPRIS2Controller ? (MPRIS2Controller.position / 1e+06) : 0 // Convert microseconds to seconds
    readonly property real duration: MPRIS2Controller ? (MPRIS2Controller.trackLength / 1e+06) : 0 // Convert microseconds to seconds

    // Format time helper
    function formatTime(seconds) {
        var mins = Math.floor(seconds / 60);
        var secs = Math.floor(seconds % 60);
        return mins + ":" + (secs < 10 ? "0" : "") + secs;
    }

    width: parent.width
    height: contentColumn.implicitHeight + Constants.spacingMedium + Constants.spacingLarge
    visible: true // Always visible
    radius: Constants.borderRadiusSmall
    border.width: Constants.borderWidthThin
    border.color: Qt.rgba(0, 191 / 255, 165 / 255, 0.3) // MColors.marathonTealBorder approx
    Component.onCompleted: {
        if (MPRIS2Controller) {
            Logger.info("MediaPlaybackManager", "✓ Initialized with MPRIS2 integration");
            Logger.info("MediaPlaybackManager", "Monitoring for media players (Spotify, VLC, Firefox, etc.)");
        } else {
            Logger.warn("MediaPlaybackManager", "MPRIS2Controller not available");
        }
    }

    // Tap to launch app
    MouseArea {
        // Z-index 0 is default, children (Column) are on top by default in QML order?
        // No, children declared later are on top. Column is declared AFTER this if I put it here.
        // Wait, I am inserting this BEFORE Column (line 33).
        // So this MouseArea is BEHIND the Column.
        // Buttons in Column will capture clicks first.

        anchors.fill: parent
        onClicked: {
            if (mediaManager.hasMedia && MPRIS2Controller) {
                var appId = MPRIS2Controller.desktopEntry;
                if (appId && appId !== "") {
                    HapticService.light();
                    Logger.info("MediaPlayback", "Launching app: " + appId);
                    AppLaunchService.launchApp(appId);
                } else {
                    // DesktopEntry is optional in MPRIS; don't spam warnings if missing.
                    Logger.debug("MediaPlayback", "No desktop entry found for player");
                }
            }
        }
    }

    Column {
        id: contentColumn

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
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
                color: mediaManager.albumArt !== "" ? "transparent" : MColors.elevated
                visible: mediaManager.hasMedia
                clip: true // CRITICAL: Clip child Image to rounded corners

                Image {
                    // Note: Image doesn't have radius property - parent Rectangle clips it

                    anchors.fill: parent
                    source: mediaManager.albumArt
                    fillMode: Image.PreserveAspectCrop
                    visible: source !== ""
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
                    font.family: MTypography.fontFamily
                    elide: Text.ElideRight
                    width: parent.width
                }

                Text {
                    text: mediaManager.artist || (mediaManager.hasMedia ? "Unknown artist" : "Play music to see controls")
                    color: MColors.textSecondary
                    font.pixelSize: Constants.fontSizeSmall
                    font.family: MTypography.fontFamily
                    elide: Text.ElideRight
                    width: parent.width
                }
            }
        }

        // Playback controls
        Row {
            readonly property real buttonWidth: Constants.touchTargetMinimum

            anchors.horizontalCenter: parent.horizontalCenter
            // height: Constants.touchTargetMinimum // REMOVED: Let Row expand to fit buttons (including glow)
            visible: mediaManager.hasMedia
            spacing: Constants.spacingSmall

            // Previous button
            MCircularIconButton {
                buttonSize: Constants.touchTargetMinimum
                // Smart Skip: Use rotate-ccw (10s back) for long tracks, otherwise skip-back
                iconName: (MPRIS2Controller && MPRIS2Controller.canSeek && MPRIS2Controller.trackLength > 20 * 60 * 1e+06) ? "rotate-ccw" : "skip-back"
                variant: "secondary"
                // Smart Skip: Enable if we can go previous OR if it's a long track we can seek in
                enabled: mediaManager.hasMedia && MPRIS2Controller && (MPRIS2Controller.canGoPrevious || (MPRIS2Controller.canSeek && MPRIS2Controller.trackLength > 20 * 60 * 1e+06))
                onClicked: {
                    if (MPRIS2Controller) {
                        MPRIS2Controller.previous();
                        Logger.info("MediaPlayback", "Previous track");
                    }
                }
            }

            // Play/Pause button
            MCircularIconButton {
                buttonSize: Constants.touchTargetMinimum
                iconName: mediaManager.isPlaying ? "pause" : "play"
                variant: "primary"
                // Some players incorrectly report CanPlay/CanPause; PlayPause is still valid.
                // Keep the control usable whenever we have an active player.
                enabled: mediaManager.hasMedia && MPRIS2Controller
                onClicked: {
                    if (MPRIS2Controller) {
                        MPRIS2Controller.playPause();
                        Logger.info("MediaPlayback", "Play/Pause");
                    }
                }
            }

            // Next button
            MCircularIconButton {
                buttonSize: Constants.touchTargetMinimum
                // Smart Skip: Use rotate-cw (30s forward) for long tracks, otherwise skip-forward
                iconName: (MPRIS2Controller && MPRIS2Controller.canSeek && MPRIS2Controller.trackLength > 20 * 60 * 1e+06) ? "rotate-cw" : "skip-forward"
                variant: "secondary"
                // Smart Skip: Enable if we can go next OR if it's a long track we can seek in
                enabled: mediaManager.hasMedia && MPRIS2Controller && (MPRIS2Controller.canGoNext || (MPRIS2Controller.canSeek && MPRIS2Controller.trackLength > 20 * 60 * 1e+06))
                onClicked: {
                    if (MPRIS2Controller) {
                        MPRIS2Controller.next();
                        Logger.info("MediaPlayback", "Next track");
                    }
                }
            }
        }
    }

    // Dark teal gradient background
    gradient: Gradient {
        GradientStop {
            position: 0
            color: Qt.rgba(0, 191 / 255, 165 / 255, 0.15)
        }

        // MColors.marathonTealGlowTop approx
        GradientStop {
            position: 1
            color: Qt.rgba(0, 0, 0, 0.2)
        }
    }

    Behavior on height {
        NumberAnimation {
            duration: 250
            easing.type: Easing.OutCubic
        }
    }
}
