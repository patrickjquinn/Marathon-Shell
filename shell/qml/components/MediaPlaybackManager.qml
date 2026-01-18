import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

Rectangle {
    id: mediaManager

    readonly property bool hasMedia: MPRIS2Controller ? MPRIS2Controller.hasActivePlayer : false
    readonly property bool isPlaying: MPRIS2Controller ? MPRIS2Controller.isPlaying : false
    readonly property string trackTitle: MPRIS2Controller && MPRIS2Controller.hasActivePlayer ? (MPRIS2Controller.trackTitle || "Unknown Track") : "No media playing"
    readonly property string artist: MPRIS2Controller ? MPRIS2Controller.trackArtist : ""
    readonly property string albumArt: MPRIS2Controller ? MPRIS2Controller.albumArtUrl : ""
    readonly property real progress: MPRIS2Controller ? (MPRIS2Controller.position / 1e+06) : 0
    readonly property real duration: MPRIS2Controller ? (MPRIS2Controller.trackLength / 1e+06) : 0

    function formatTime(seconds) {
        var mins = Math.floor(seconds / 60);
        var secs = Math.floor(seconds % 60);
        return mins + ":" + (secs < 10 ? "0" : "") + secs;
    }

    width: parent.width
    height: contentColumn.implicitHeight + Constants.spacingMedium + Constants.spacingLarge
    visible: true
    radius: Constants.borderRadiusSmall
    border.width: Constants.borderWidthThin
    border.color: Qt.rgba(0, 191 / 255, 165 / 255, 0.3)
    Component.onCompleted: {
        if (MPRIS2Controller) {
            Logger.info("MediaPlaybackManager", "✓ Initialized with MPRIS2 integration");
            Logger.info("MediaPlaybackManager", "Monitoring for media players (Spotify, VLC, Firefox, etc.)");
        } else {
            Logger.warn("MediaPlaybackManager", "MPRIS2Controller not available");
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (mediaManager.hasMedia && MPRIS2Controller) {
                var appId = MPRIS2Controller.desktopEntry;
                if (appId && appId !== "") {
                    HapticManager.light();
                    Logger.info("MediaPlayback", "Launching app: " + appId);
                    AppLaunchService.launchApp(appId);
                } else {
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

        Row {
            width: parent.width
            spacing: Constants.spacingMedium

            Rectangle {
                width: Constants.touchTargetSmall
                height: Constants.touchTargetSmall
                radius: Constants.borderRadiusSmall
                color: mediaManager.albumArt !== "" ? "transparent" : MColors.elevated
                visible: mediaManager.hasMedia
                clip: true

                Image {
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

        Row {
            readonly property real buttonWidth: Constants.touchTargetMinimum

            anchors.horizontalCenter: parent.horizontalCenter
            visible: mediaManager.hasMedia
            spacing: Constants.spacingSmall

            MCircularIconButton {
                buttonSize: Constants.touchTargetMinimum
                iconName: (MPRIS2Controller && MPRIS2Controller.canSeek && MPRIS2Controller.trackLength > 20 * 60 * 1e+06) ? "rotate-ccw" : "skip-back"
                variant: "secondary"
                enabled: mediaManager.hasMedia && MPRIS2Controller && (MPRIS2Controller.canGoPrevious || (MPRIS2Controller.canSeek && MPRIS2Controller.trackLength > 20 * 60 * 1e+06))
                onClicked: {
                    if (MPRIS2Controller) {
                        MPRIS2Controller.previous();
                        Logger.info("MediaPlayback", "Previous track");
                    }
                }
            }

            MCircularIconButton {
                buttonSize: Constants.touchTargetMinimum
                iconName: mediaManager.isPlaying ? "pause" : "play"
                variant: "primary"
                enabled: mediaManager.hasMedia && MPRIS2Controller
                onClicked: {
                    if (MPRIS2Controller) {
                        MPRIS2Controller.playPause();
                        Logger.info("MediaPlayback", "Play/Pause");
                    }
                }
            }

            MCircularIconButton {
                buttonSize: Constants.touchTargetMinimum
                iconName: (MPRIS2Controller && MPRIS2Controller.canSeek && MPRIS2Controller.trackLength > 20 * 60 * 1e+06) ? "rotate-cw" : "skip-forward"
                variant: "secondary"
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

    gradient: Gradient {
        GradientStop {
            position: 0
            color: Qt.rgba(0, 191 / 255, 165 / 255, 0.15)
        }

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
