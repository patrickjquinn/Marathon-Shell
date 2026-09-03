import MarathonOS.Shell 1.0
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

// Marathon DS · LockMedia card — per screens-shell.jsx:188-240
// LockMedia().
//
// Composition (top → bottom):
//   - Row · 64 × 64 album-art bay (radius 4, gradient, vertical-
//     stripe pattern when no album art) + title (Subhead 15/600
//     primary) + artist (Footnote 13/400 secondary)
//   - Scrubber row · time-left (Eyebrow 11 / secondary / tnum) +
//     3 px track (whiteOverlay08, radius 2) with teal-gradient fill
//     + halo'd 10 × 10 teal-bright thumb + time-right
//   - Controls row · skip-back 42 (secondary) / play 56 (primary,
//     teal gradient + glow + black glyph) / skip-forward 42
//
// The card is bound to MPRIS2Controller — when no player is active
// (hasMedia=false) the card's visibility is the caller's concern
// (LockScreen swaps to LockMedia layout when hasMedia flips true).
Rectangle {
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

    // 14 outer padding per JSX. height tracks content + 14×2 vertical
    // padding + the scrubber/controls rows below.
    width: parent ? parent.width : 0
    implicitHeight: cardContent.implicitHeight + 28
    radius: MRadius.md           // 4 — DS default
    border.width: 1
    border.color: MColors.tealBorder

    // DS spec gradient — vertical, dark-teal-tinted card sits over the
    // wallpaper aurora without competing.
    gradient: Gradient {
        GradientStop {
            position: 0
            color: Qt.rgba(0, 89 / 255, 77 / 255, 0.25)
        }
        GradientStop {
            position: 1
            color: Qt.rgba(0, 89 / 255, 77 / 255, 0.10)
        }
    }

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
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.topMargin: 14
        spacing: 14

        // ── Header — album art + title/artist ────────────────
        Row {
            width: parent.width
            spacing: 14

            // 64 × 64 album art bay — radius 4 per DS, NOT squircle.
            Rectangle {
                id: albumBay
                width: 64
                height: 64
                radius: MRadius.md
                clip: true
                border.width: 1
                border.color: MColors.whiteOverlay08

                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop {
                        position: 0
                        color: "#1a4a3e"
                    }
                    GradientStop {
                        position: 1
                        color: "#0d2620"
                    }
                }

                // Real album art (if any) — fills the bay.
                Image {
                    anchors.fill: parent
                    source: mediaManager.albumArt
                    sourceSize: Qt.size(width, height)
                    fillMode: Image.PreserveAspectCrop
                    visible: source.toString().length > 0
                    asynchronous: true
                    cache: true
                }

                // Vertical-stripe pattern + music glyph — shown when
                // there's no album art (stylised "no art available").
                // Pattern matches the JSX's repeating-linear-gradient
                // (3 px transparent + 1 px teal-bright 15% alpha).
                Item {
                    anchors.fill: parent
                    visible: mediaManager.albumArt.length === 0

                    Row {
                        anchors.fill: parent
                        spacing: 3

                        Repeater {
                            // 4-px stride → 64 / 4 = 16 stripes
                            model: 16
                            delegate: Rectangle {
                                width: 1
                                height: parent.height
                                color: Qt.rgba(29 / 255, 233 / 255, 182 / 255, 0.15)
                            }
                        }
                    }

                    Icon {
                        anchors.centerIn: parent
                        name: "music"
                        size: 24
                        color: MColors.marathonTealBright
                    }
                }
            }

            // Title + artist — flex column, ellide on overflow.
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - albumBay.width - parent.spacing
                spacing: 4

                Text {
                    width: parent.width
                    text: mediaManager.trackTitle
                    color: MColors.textPrimary
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeSubhead
                    font.weight: MTypography.weightDemiBold
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: mediaManager.artist
                    color: MColors.textSecondary
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeFootnote
                    font.weight: MTypography.weightRegular
                    elide: Text.ElideRight
                    visible: text.length > 0
                }
            }
        }

        // ── Scrubber ────────────────────────────────────────
        Row {
            width: parent.width
            spacing: 10

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: mediaManager.formatTime(mediaManager.progress)
                color: MColors.textSecondary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeEyebrow
                font.weight: MTypography.weightMedium
                font.features: ({
                        "tnum": 1
                    })
            }

            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 2 * (timeLeftSize.width)   // bookended by tnum times
                height: 10

                // Track
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 3
                    radius: 2
                    color: MColors.whiteOverlay08
                }
                // Fill — teal-gradient at the progress fraction
                Rectangle {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(3, parent.width * mediaManager.progressFraction)
                    height: 3
                    radius: 2
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop {
                            position: 0
                            color: MColors.marathonTealBright
                        }
                        GradientStop {
                            position: 1
                            color: MColors.marathonTeal
                        }
                    }
                }
                // Thumb — 10 px circle, teal-bright, soft glow
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: Math.max(0, parent.width * mediaManager.progressFraction - width / 2)
                    width: 10
                    height: 10
                    radius: 5
                    color: MColors.marathonTealBright
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.3)
                    visible: mediaManager.duration > 0

                    // Outer glow halo
                    Rectangle {
                        anchors.centerIn: parent
                        width: 18
                        height: 18
                        radius: 9
                        color: MColors.tealHalo
                        z: -1
                    }
                }
                // Tap-to-seek
                MouseArea {
                    anchors.fill: parent
                    anchors.topMargin: -8
                    anchors.bottomMargin: -8
                    onClicked: mouse => {
                        if (!mediaManager.hasMedia || mediaManager.duration <= 0)
                            return;
                        const frac = Math.max(0, Math.min(1, mouse.x / width));
                        MPRIS2Controller.setPosition(frac * mediaManager.duration * 1e+06);
                        HapticManager.light();
                    }
                }
            }
            // Width-cache for the bookend times (so the track stretches
            // the available middle space).
            Text {
                id: timeLeftSize
                visible: false
                text: mediaManager.formatTime(mediaManager.duration)
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeEyebrow
                font.weight: MTypography.weightMedium
                font.features: ({
                        "tnum": 1
                    })
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: mediaManager.formatTime(mediaManager.duration)
                color: MColors.textSecondary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeEyebrow
                font.weight: MTypography.weightMedium
                font.features: ({
                        "tnum": 1
                    })
            }
        }

        // ── Controls — 42 / 56 / 42, gap 22, centered ────────
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 22

            MCircularIconButton {
                buttonSize: 42
                iconName: "skip-back"
                variant: "secondary"
                enabled: mediaManager.hasMedia && MPRIS2Controller && MPRIS2Controller.canGoPrevious
                onClicked: {
                    if (MPRIS2Controller) {
                        HapticManager.light();
                        MPRIS2Controller.previous();
                    }
                }
            }

            MCircularIconButton {
                buttonSize: 56
                iconName: mediaManager.isPlaying ? "pause" : "play"
                variant: "primary"
                enabled: mediaManager.hasMedia && MPRIS2Controller
                onClicked: {
                    if (MPRIS2Controller) {
                        HapticManager.medium();
                        MPRIS2Controller.playPause();
                    }
                }
            }

            MCircularIconButton {
                buttonSize: 42
                iconName: "skip-forward"
                variant: "secondary"
                enabled: mediaManager.hasMedia && MPRIS2Controller && MPRIS2Controller.canGoNext
                onClicked: {
                    if (MPRIS2Controller) {
                        HapticManager.light();
                        MPRIS2Controller.next();
                    }
                }
            }
        }
    }

    Behavior on height {
        NumberAnimation {
            duration: MMotion.normal
            easing.type: Easing.OutCubic
        }
    }
}
