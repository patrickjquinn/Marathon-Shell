import MarathonOS.Shell 1.0
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Effects
import MarathonUI.Theme
import QtQuick

// Marathon DS · Active Frames home (BB10 lineage).
//
// This IS the home screen AND the task switcher — one surface, two
// modes. The bottom dock's centre indicator visualises which mode
// you're in; the gesture (pinch / long-press / dock tap) switches.
//
// Layout, top to bottom:
//   • StatusBar    — top:0, h:28           (rendered by parent shell)
//   • MNowBar      — top:28, left/right:12, h:36
//   • Greeting     — top:78, left/right:20 (home mode only)
//   • MFramesView  — top:168 (home) / top:44 (switcher), bottom:88
//   • Pinned dock  — bottom:88, left/right:16  (home mode only)
//   • MDock chrome — bottom:0 (rendered by parent shell)
Item {
    id: root

    // Mode: "home" = curated widgets + greeting + pinned dock.
    //        "switcher" = live snapshots, no greeting, no pinned dock.
    property string mode: "home"

    signal frameActivated(string appId)
    signal frameClosed(string appId)
    signal pinnedAppLaunched(string appId)

    // ── Now Bar ──────────────────────────────────────────────
    // Surfaces the active MPRIS2 player as a 36 px live-activity
    // strip. Hidden when nothing is playing — empty/idle state per
    // the brief; the design doesn't show a fake feed.
    MNowBar {
        id: nowBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        visible: MPRIS2Controller && MPRIS2Controller.hasActivePlayer
        variant: "music"
        iconName: "music"
        label: MPRIS2Controller && MPRIS2Controller.trackTitle ? MPRIS2Controller.trackTitle : ""
        sublabel: MPRIS2Controller && MPRIS2Controller.trackArtist ? MPRIS2Controller.trackArtist : ""
        playing: MPRIS2Controller ? MPRIS2Controller.isPlaying : false
    }

    // ── Greeting block (home mode) ───────────────────────────
    Column {
        id: greeting
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: nowBar.bottom
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.topMargin: 14
        spacing: 4
        visible: root.mode === "home"

        // "FRIDAY · DECEMBER 5" — JSX uses a middle dot, not comma. Build
        // from formatDate parts so the separator is reliable across locales.
        Text {
            text: Qt.formatDateTime(new Date(), "dddd · MMMM d").toUpperCase()
            color: MColors.textSecondary
            font.family: MTypography.fontFamily
            font.pixelSize: MTypography.sizeEyebrow
            font.weight: MTypography.weightBold
            font.letterSpacing: MTypography.trackingEyebrow
        }
        Text {
            text: greetingFor(SystemStatusStore.timeString, SettingsManagerCpp.deviceName || "Avery")
            color: MColors.textPrimary
            font.family: MTypography.fontFamily
            font.pixelSize: 26
            font.weight: MTypography.weightExtraLight   // 200 per DS Title 1
            font.letterSpacing: -0.6
        }
    }

    // Parse hour out of "HH:MM AM/PM" or "HH:MM" — derives a 0-23
    // hour for the greeting. The store has no exposed `hour` property,
    // and adding one would touch C++ for two callsites; this parse is
    // local and harmless.
    function greetingFor(timeStr, who) {
        if (!timeStr)
            return "Hello, " + who;
        const m = /^(\d+):/.exec(timeStr);
        if (!m)
            return "Hello, " + who;
        let h = parseInt(m[1], 10);
        if (/PM/i.test(timeStr) && h !== 12)
            h += 12;
        if (/AM/i.test(timeStr) && h === 12)
            h = 0;
        var part;
        if (isNaN(h))
            part = "Hello";
        else if (h < 5)
            part = "Still up";
        else if (h < 12)
            part = "Good morning";
        else if (h < 17)
            part = "Good afternoon";
        else if (h < 22)
            part = "Good evening";
        else
            part = "Good night";
        return part + ", " + who;
    }

    // ── Active Frames grid ───────────────────────────────────
    MFramesView {
        id: framesView
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: root.mode === "home" ? greeting.bottom : nowBar.bottom
        anchors.bottom: pinnedDock.top
        anchors.topMargin: root.mode === "home" ? 14 : 8
        anchors.bottomMargin: 16
        mode: root.mode
        frames: root.sampleFrames
        onFrameActivated: function (appId) {
            root.frameActivated(appId);
        }
        onFrameClosed: function (appId) {
            root.frameClosed(appId);
        }
    }

    // ── Pinned dock row (home mode only) ─────────────────────
    Row {
        id: pinnedDock
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 80      // above MDock chrome
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 12
        visible: root.mode === "home"

        Repeater {
            model: [
                {
                    appId: "phone",
                    name: "Phone",
                    icon: "phone",
                    teal: true
                },
                {
                    appId: "messages",
                    name: "Messages",
                    icon: "message",
                    teal: false
                },
                {
                    appId: "mail",
                    name: "Mail",
                    icon: "mail",
                    teal: false
                },
                {
                    appId: "browser",
                    name: "Browser",
                    icon: "globe",
                    teal: false
                }
            ]
            delegate: Column {
                required property var modelData
                width: (pinnedDock.width - pinnedDock.spacing * 3) / 4
                spacing: 6

                Rectangle {
                    width: 56
                    height: 56
                    radius: MRadius.squircle
                    anchors.horizontalCenter: parent.horizontalCenter
                    gradient: Gradient {
                        GradientStop {
                            position: 0
                            color: modelData.teal ? MColors.marathonTealBright : MColors.bb10Card
                        }
                        GradientStop {
                            position: 1
                            color: modelData.teal ? MColors.marathonTealDark : MColors.bb10Black
                        }
                    }
                    border.width: 1
                    border.color: modelData.teal ? MColors.tealBorder : MColors.whiteOverlay08

                    Icon {
                        anchors.centerIn: parent
                        name: modelData.icon
                        color: modelData.teal ? "#000000" : MColors.marathonTealBright
                        size: 26
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.pinnedAppLaunched(modelData.appId)
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.name
                    color: MColors.textPrimary
                    font.family: MTypography.fontFamily
                    font.pixelSize: 11
                    font.weight: MTypography.weightMedium
                }
            }
        }
    }

    // ── Sample frames (TEMPORARY — wires into real app feeds later) ──
    //
    // Each entry: { appId, iconName, appName, badge, iconTint, widget, preview }
    // The widget Component is rendered in home mode; preview in switcher mode.
    // Once apps register their own widgets via a LiveFrameProvider C++
    // interface this static model goes away.
    readonly property var sampleFrames: [
        {
            appId: "calendar",
            iconName: "calendar",
            appName: "Calendar",
            badge: "3 today",
            iconTint: MColors.marathonTealBright,
            widget: calendarWidget,
            preview: calendarPreview
        },
        {
            appId: "music",
            iconName: "music",
            appName: "Music",
            badge: "Playing",
            iconTint: MColors.marathonTealBright,
            widget: musicWidget,
            preview: musicPreview
        },
        {
            appId: "health",
            iconName: "heart",
            appName: "Health",
            badge: "2 of 3",
            iconTint: MColors.secRose,
            widget: healthWidget,
            preview: null
        },
        {
            appId: "messages",
            iconName: "message",
            appName: "Messages",
            badge: "3 unread",
            iconTint: MColors.secBlue,
            widget: messagesWidget,
            preview: messagesPreview
        }
    ]

    // ── Widget components — sample / placeholder content ─────
    Component {
        id: calendarWidget
        Column {
            spacing: 6
            Row {
                spacing: 10
                Text {
                    text: "12:00"
                    color: MColors.marathonTealBright
                    font.family: MTypography.fontFamily
                    font.pixelSize: 13
                    font.weight: MTypography.weightDemiBold
                }
                Text {
                    text: "Design review"
                    color: MColors.textPrimary
                    font.family: MTypography.fontFamily
                    font.pixelSize: 13
                    font.weight: MTypography.weightMedium
                }
            }
            Row {
                spacing: 10
                Text {
                    text: "15:30"
                    color: MColors.textSecondary
                    font.family: MTypography.fontFamily
                    font.pixelSize: 13
                }
                Text {
                    text: "1:1 Devon"
                    color: MColors.textPrimary
                    font.family: MTypography.fontFamily
                    font.pixelSize: 13
                }
            }
            Row {
                spacing: 10
                Text {
                    text: "19:30"
                    color: MColors.textSecondary
                    font.family: MTypography.fontFamily
                    font.pixelSize: 13
                }
                Text {
                    text: "Concert · Bowery"
                    color: MColors.textPrimary
                    font.family: MTypography.fontFamily
                    font.pixelSize: 13
                }
            }
        }
    }
    Component {
        id: calendarPreview
        Text {
            anchors.centerIn: parent
            text: "December 2025"
            color: MColors.textSecondary
            font.family: MTypography.fontFamily
            font.pixelSize: 12
        }
    }

    Component {
        id: musicWidget
        Item {
            readonly property bool hasMedia: MPRIS2Controller && MPRIS2Controller.hasActivePlayer
            readonly property real progressFraction: {
                if (!MPRIS2Controller || !MPRIS2Controller.trackLength)
                    return 0;
                const len = MPRIS2Controller.trackLength;
                const pos = MPRIS2Controller.position || 0;
                return Math.max(0, Math.min(1, pos / len));
            }

            Row {
                anchors.fill: parent
                spacing: 12

                Rectangle {
                    width: 44
                    height: 44
                    radius: MRadius.md
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
                    border.width: 1
                    border.color: MColors.whiteOverlay08
                    anchors.verticalCenter: parent.verticalCenter

                    Icon {
                        anchors.centerIn: parent
                        name: "music"
                        size: 20
                        color: MColors.marathonTealBright
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 56
                    spacing: 4

                    Text {
                        width: parent.width
                        // Title text bound to MPRIS2; idle state shows
                        // the DS-design 'Nothing playing' placeholder.
                        text: hasMedia ? (MPRIS2Controller.trackTitle || "Untitled") : "Nothing playing"
                        color: hasMedia ? MColors.textPrimary : MColors.textSecondary
                        font.family: MTypography.fontFamily
                        font.pixelSize: 11
                        font.weight: MTypography.weightDemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: hasMedia ? (MPRIS2Controller.trackArtist || "Unknown artist") : "Tap Music to start"
                        color: MColors.textSecondary
                        font.family: MTypography.fontFamily
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        width: parent.width
                        height: 3
                        radius: 1.5
                        color: MColors.whiteOverlay08

                        Rectangle {
                            width: parent.width * progressFraction
                            height: parent.height
                            radius: parent.radius
                            color: MColors.marathonTealBright
                            visible: hasMedia
                        }
                    }
                }
            }
        }
    }
    Component {
        id: musicPreview
        Item {
            Text {
                anchors.centerIn: parent
                text: "Now Playing"
                color: MColors.textSecondary
            }
        }
    }

    Component {
        id: healthWidget
        // Concentric SVG rings — Move (rose, 60%), Exercise (teal, 75%),
        // Stand (blue, 37%). Bottom-left anchored per DS spec.
        Item {
            id: ringsRoot
            anchors.fill: parent
            property real moveFraction: 0.60
            property real exerciseFraction: 0.75
            property real standFraction: 0.37

            Canvas {
                id: rings
                width: 74
                height: 74
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 4
                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();
                    var cx = width / 2, cy = height / 2;
                    function ring(r, frac, color, alpha) {
                        ctx.beginPath();
                        ctx.strokeStyle = "rgba(255,255,255,0.08)";
                        ctx.lineWidth = 5;
                        ctx.lineCap = "round";
                        ctx.arc(cx, cy, r, 0, Math.PI * 2);
                        ctx.stroke();
                        ctx.beginPath();
                        ctx.strokeStyle = color;
                        ctx.lineWidth = 5;
                        ctx.lineCap = "round";
                        ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * frac);
                        ctx.stroke();
                    }
                    ring(30, ringsRoot.moveFraction, "#a85968", 1.0);
                    ring(22, ringsRoot.exerciseFraction, "#1de9b6", 1.0);
                    ring(14, ringsRoot.standFraction, "#3a6b9c", 1.0);
                }
            }
        }
    }

    Component {
        id: messagesWidget
        Column {
            spacing: 6
            Row {
                spacing: 8
                Text {
                    text: "Maya"
                    color: MColors.textPrimary
                    font.family: MTypography.fontFamily
                    font.pixelSize: 12
                    font.weight: MTypography.weightDemiBold
                }
                Text {
                    text: "Saved a spot near…"
                    color: MColors.textSecondary
                    font.family: MTypography.fontFamily
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    width: 130
                }
            }
            Row {
                spacing: 8
                Text {
                    text: "Devon"
                    color: MColors.textPrimary
                    font.family: MTypography.fontFamily
                    font.pixelSize: 12
                    font.weight: MTypography.weightDemiBold
                }
                Text {
                    text: "Pushing 4.2.2"
                    color: MColors.textSecondary
                    font.family: MTypography.fontFamily
                    font.pixelSize: 12
                }
            }
            Row {
                spacing: 8
                Text {
                    text: "Linear"
                    color: MColors.textPrimary
                    font.family: MTypography.fontFamily
                    font.pixelSize: 12
                    font.weight: MTypography.weightDemiBold
                }
                Text {
                    text: "MARS-204 assign…"
                    color: MColors.textSecondary
                    font.family: MTypography.fontFamily
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    width: 130
                }
            }
        }
    }
    Component {
        id: messagesPreview
        Item {
            Text {
                anchors.centerIn: parent
                text: "Messages"
                color: MColors.textSecondary
            }
        }
    }
}
