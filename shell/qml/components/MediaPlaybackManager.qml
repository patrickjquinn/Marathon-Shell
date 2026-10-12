import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

// Lock-screen media controls, straight on the ambience as Sailfish
// shows them: art, title and artist, a highlight scrubber, ring buttons.
Item {
    id: mediaManager

    readonly property bool hasMedia: MPRIS2Controller ? MPRIS2Controller.hasActivePlayer : false
    readonly property bool isPlaying: MPRIS2Controller ? MPRIS2Controller.isPlaying : false
    readonly property string trackTitle: hasMedia ? (MPRIS2Controller.trackTitle || "Untitled") : ""
    readonly property string artist: hasMedia ? (MPRIS2Controller.trackArtist || "") : ""
    readonly property string albumArt: hasMedia ? (MPRIS2Controller.albumArtUrl || "") : ""
    readonly property real progress: hasMedia ? MPRIS2Controller.position / 1e+06 : 0
    readonly property real duration: hasMedia ? MPRIS2Controller.trackLength / 1e+06 : 0
    readonly property real progressFraction: duration > 0 ? Math.max(0, Math.min(1, progress / duration)) : 0

    function formatTime(seconds) {
        const total = Math.max(0, Math.floor(seconds));
        const m = Math.floor(total / 60);
        const s = total % 60;
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    width: parent ? parent.width : 0
    implicitHeight: cardContent.implicitHeight + Silica.Theme.paddingLarge * 2

    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (mediaManager.hasMedia && MPRIS2Controller) {
                const appId = MPRIS2Controller.desktopEntry;
                if (appId && appId !== "") {
                    HapticManager.light();
                    Logger.info("MediaPlayback", "Launching " + appId);
                    AppLaunchService.launchApp(appId);
                }
            }
        }
    }

    Column {
        id: cardContent

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Silica.Theme.paddingLarge
        spacing: Silica.Theme.paddingLarge

        Row {
            width: parent.width
            spacing: Silica.Theme.paddingMedium

            Rectangle {
                id: albumBay
                width: Silica.Theme.iconSizeLarge
                height: width
                radius: Silica.Theme.paddingSmall
                clip: true
                color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.1)

                Image {
                    anchors.fill: parent
                    source: mediaManager.albumArt
                    sourceSize: Qt.size(width, height)
                    fillMode: Image.PreserveAspectCrop
                    visible: source.toString().length > 0
                    asynchronous: true
                    cache: true
                }

                GlyphIcon {
                    anchors.centerIn: parent
                    name: "music"
                    size: Silica.Theme.iconSizeSmall
                    color: Silica.Theme.secondaryColor
                    visible: mediaManager.albumArt.length === 0
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - albumBay.width - parent.spacing

                Silica.Label {
                    width: parent.width
                    text: mediaManager.trackTitle
                    color: Silica.Theme.primaryColor
                    font.pixelSize: Silica.Theme.fontSizeMedium
                    truncationMode: Silica.TruncationMode.Fade
                }
                Silica.Label {
                    width: parent.width
                    text: mediaManager.artist
                    color: Silica.Theme.secondaryColor
                    font.pixelSize: Silica.Theme.fontSizeSmall
                    truncationMode: Silica.TruncationMode.Fade
                    visible: text.length > 0
                }
            }
        }

        Row {
            width: parent.width
            spacing: Silica.Theme.paddingMedium

            Silica.Label {
                id: elapsed
                anchors.verticalCenter: parent.verticalCenter
                text: mediaManager.formatTime(mediaManager.progress)
                color: Silica.Theme.secondaryColor
                font.pixelSize: Silica.Theme.fontSizeTiny
                font.features: ({
                        "tnum": 1
                    })
            }

            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - elapsed.width - total.width - parent.spacing * 2
                height: Silica.Theme.paddingLarge

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: Math.max(2, Math.round(Silica.Theme.paddingSmall / 2))
                    radius: height / 2
                    color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.2)

                    Rectangle {
                        width: parent.width * mediaManager.progressFraction
                        height: parent.height
                        radius: parent.radius
                        color: Silica.Theme.highlightColor
                    }
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.max(0, parent.width * mediaManager.progressFraction - width / 2)
                    width: Silica.Theme.paddingMedium
                    height: width
                    radius: width / 2
                    color: Silica.Theme.highlightColor
                    visible: mediaManager.duration > 0
                }
                MouseArea {
                    anchors.fill: parent
                    anchors.topMargin: -Silica.Theme.paddingMedium
                    anchors.bottomMargin: -Silica.Theme.paddingMedium
                    onClicked: mouse => {
                        if (!mediaManager.hasMedia || mediaManager.duration <= 0)
                            return;
                        const frac = Math.max(0, Math.min(1, mouse.x / width));
                        MPRIS2Controller.setPosition(frac * mediaManager.duration * 1e+06);
                        HapticManager.light();
                    }
                }
            }

            Silica.Label {
                id: total
                anchors.verticalCenter: parent.verticalCenter
                text: mediaManager.formatTime(mediaManager.duration)
                color: Silica.Theme.secondaryColor
                font.pixelSize: Silica.Theme.fontSizeTiny
                font.features: ({
                        "tnum": 1
                    })
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Silica.Theme.paddingLarge * 2

            MCircularIconButton {
                buttonSize: 48
                iconName: "skip-back"
                variant: "secondary"
                disabled: !(mediaManager.hasMedia && MPRIS2Controller && MPRIS2Controller.canGoPrevious)
                anchors.verticalCenter: parent.verticalCenter
                onClicked: {
                    MPRIS2Controller.previous();
                }
            }

            MCircularIconButton {
                buttonSize: 62
                iconName: mediaManager.isPlaying ? "pause" : "play"
                variant: "primary"
                disabled: !(mediaManager.hasMedia && MPRIS2Controller)
                onClicked: {
                    MPRIS2Controller.playPause();
                }
            }

            MCircularIconButton {
                buttonSize: 48
                iconName: "skip-forward"
                variant: "secondary"
                disabled: !(mediaManager.hasMedia && MPRIS2Controller && MPRIS2Controller.canGoNext)
                anchors.verticalCenter: parent.verticalCenter
                onClicked: {
                    MPRIS2Controller.next();
                }
            }
        }
    }
}
