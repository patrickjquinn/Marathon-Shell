import MarathonOS.Shell 1.0
import MarathonUI.Containers
import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Theme
import QtQuick

// Marathon DS · Quick Settings panel (§08).
//
// Pulled down from the top edge. Glass overlay over the wallpaper.
// Layout, top to bottom:
//   • Header — Marathon lockup + date right
//   • Sliders block — brightness + volume (MQSSlider)
//   • Tile grid — 2 cols × N rows of MQSTile (split-bay)
//   • Page indicator — teal bar for active, dim circles for others
//   • Music strip — MNowBar variant (only when something is playing)
//   • Drag handle — 44 × 4 bar centred at bottom
Item {
    id: quickSettings

    // The running app surface to blur behind the QS chrome, if any.
    // Set by MarathonShell.qml to appWindowContainer when an app is
    // open; null otherwise (a dark tint covers the wallpaper).
    property Item appBackdrop: null

    signal closed
    signal launchApp(var app)

    // Backdrop: live blur of the running app (iOS-style glass-over-app)
    // when one is open, dark tint over the wallpaper otherwise.
    AppBackdropBlur {
        anchors.fill: parent
        source: quickSettings.appBackdrop
        blurAmount: 1.0
        blurMax: 48
        saturation: 0.5
        brightness: -0.1
        tint: Qt.rgba(13 / 255, 13 / 255, 14 / 255, 0.55)
    }

    Rectangle {
        anchors.fill: parent
        visible: quickSettings.appBackdrop === null
        color: Qt.rgba(13 / 255, 13 / 255, 14 / 255, 0.95)
    }

    // Tile state. Wired to SystemControlStore / SystemStatusStore.
    // Helper: descriptive sublabels per JSX QuickSettings — show meaningful
    // state when on (SSID, "5G · 87%", profile name), simple "Off" otherwise.
    function mobileDataSub() {
        if (!SystemControlStore.isCellularDataOn)
            return "Off";
        const tech = ModemManagerCpp.networkType || "";
        const signal = ModemManagerCpp.signalStrength;
        const op = ModemManagerCpp.operatorName;
        if (tech && signal > 0)
            return tech + " · " + signal + "%";
        if (op)
            return op;
        return "On";
    }
    readonly property var tiles: [
        {
            id: "wifi",
            icon: "wifi",
            label: "Wi-Fi",
            on: SystemControlStore.isWifiOn,
            sub: SystemControlStore.isWifiOn ? (SystemStatusStore.wifiNetwork || "On") : "Off"
        },
        {
            id: "bluetooth",
            icon: "bluetooth",
            label: "Bluetooth",
            on: SystemControlStore.isBluetoothOn,
            sub: SystemControlStore.isBluetoothOn ? "On" : "Off"
        },
        {
            id: "cellular",
            icon: "signal-high",
            label: "Mobile data",
            on: SystemControlStore.isCellularDataOn,
            sub: mobileDataSub()
        },
        {
            id: "airplane",
            icon: "plane",
            label: "Flight mode",
            on: SystemControlStore.isAirplaneModeOn,
            sub: SystemControlStore.isAirplaneModeOn ? "On" : "Off"
        },
        {
            id: "dnd",
            icon: "bell-off",
            label: "Do Not Disturb",
            on: SystemControlStore.isDndMode,
            sub: SystemControlStore.isDndMode ? "On" : "Off"
        },
        {
            id: "torch",
            icon: "flashlight",
            label: "Torch",
            on: SystemControlStore.isFlashlightOn,
            sub: SystemControlStore.isFlashlightOn ? "On" : "Off"
        }
    ]

    Column {
        id: content

        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.topMargin: 14
        spacing: 14

        // ── Header — Marathon lockup + date ──────────────────
        Row {
            width: parent.width
            spacing: 10

            // Marathon lockup — 20 px teal-gradient bay + black M
            // glyph per JSX QuickSettings(). Bay radius is 3 (one step
            // off the squircle 14 to read more like a glyph than an
            // app tile).
            Rectangle {
                width: 20
                height: 20
                radius: 3
                anchors.verticalCenter: parent.verticalCenter
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
                border.width: 1
                border.color: MColors.tealBorder

                Text {
                    anchors.centerIn: parent
                    text: "M"
                    color: MColors.elev0
                    font.family: MTypography.fontFamily
                    font.pixelSize: 13
                    font.weight: MTypography.weightBlack
                }
            }
            // 'MARATHON' eyebrow — DS Eyebrow role (11/700/+2 tracking,
            // textPrimary on this surface since the lockup is the
            // brand). Was sizeCaption (12) which is one role too large.
            Text {
                text: "MARATHON"
                color: MColors.textPrimary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeEyebrow
                font.weight: MTypography.weightBold
                font.letterSpacing: 2
                font.capitalization: Font.AllUppercase
                anchors.verticalCenter: parent.verticalCenter
            }
            // Spacer
            Item {
                width: parent.width - 24 - 90 - 110
                height: 1
            }
            // Short "Fri · 7:08 PM" per JSX QuickSettings — long form
            // dateString ("Thursday, May 14") overflows the right edge on
            // 540 px canvases. Recompute from a local timer-driven clock.
            Text {
                text: Qt.formatDateTime(new Date(), "ddd · h:mm AP")
                color: MColors.textSecondary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeFootnote
                font.features: ({
                        "tnum": 1
                    })
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // ── Sliders ──────────────────────────────────────────
        // DS-spec card: elev-2 fill, whiteOverlay04 border + inner
        // highlight, 4 px radius, padding 12 14.
        Rectangle {
            width: parent.width
            height: brightness.height + volume.height + slidersDivider.height + 24
            radius: MRadius.md
            color: MColors.elev2
            border.width: 1
            border.color: MColors.whiteOverlay04

            MQSSlider {
                id: brightness
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                anchors.topMargin: 12
                iconName: "sun"
                label: "Brightness"
                value: SystemControlStore.brightness
                onMoved: function (v) {
                    SystemControlStore.setBrightness(v);
                }
            }
            Rectangle {
                id: slidersDivider
                anchors.top: brightness.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 10
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                height: 1
                color: MColors.whiteOverlay04
            }
            MQSSlider {
                id: volume
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: slidersDivider.bottom
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                anchors.topMargin: 10
                iconName: "volume-2"
                label: "Volume"
                value: SystemControlStore.volume
                onMoved: function (v) {
                    SystemControlStore.setVolume(v);
                }
            }
        }

        // ── Tile grid (2 cols) ───────────────────────────────
        Grid {
            id: tileGrid
            width: parent.width
            columns: 2
            rowSpacing: 8
            columnSpacing: 8
            readonly property real cellWidth: (width - columnSpacing) / 2

            Repeater {
                model: quickSettings.tiles
                delegate: MQSTile {
                    required property int index
                    required property var modelData
                    width: tileGrid.cellWidth
                    iconName: modelData.icon || "square"
                    label: modelData.label || ""
                    sublabel: modelData.sub || ""
                    on: modelData.on === true
                    onToggled: quickSettings.toggle(modelData.id)
                }
            }
        }

        // ── Page indicator ──────────────────────────────────
        // Matches the JSX QuickSettings() spec: an 18 × 4 tealBright
        // pill for the active page + N - 1 dim 4 × 4 dots for the
        // remaining pages. Currently the tile array holds a single
        // page's worth of tiles (6), so only the active pill shows —
        // when a second page lands the indicator grows automatically.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6

            readonly property int pages: 1   // bump when tile pages > 1

            Rectangle {
                width: 18
                height: 4
                radius: 2
                color: MColors.marathonTealBright
                anchors.verticalCenter: parent.verticalCenter
            }
            Repeater {
                model: Math.max(0, parent.pages - 1)
                delegate: Rectangle {
                    required property int index
                    width: 4
                    height: 4
                    radius: 2
                    color: MColors.whiteOverlay24
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // ── Now-playing strip (visible when something playing) ──
        MNowBar {
            width: parent.width
            visible: MPRIS2Controller.isPlaying
            variant: "music"
            iconName: "music"
            label: MPRIS2Controller.trackTitle || ""
            sublabel: MPRIS2Controller.trackArtist || ""
            playing: MPRIS2Controller.isPlaying
        }
    }

    // ── Drag handle ─────────────────────────────────────────
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        width: 44
        height: 4
        radius: 2
        color: MColors.whiteOverlay12
    }

    // ── Behaviour hooks ─────────────────────────────────────
    function toggle(id) {
        switch (id) {
        case "wifi":
            SystemControlStore.toggleWifi();
            break;
        case "bluetooth":
            SystemControlStore.toggleBluetooth();
            break;
        case "cellular":
            SystemControlStore.toggleCellularData();
            break;
        case "airplane":
            SystemControlStore.toggleAirplaneMode();
            break;
        case "dnd":
            SystemControlStore.toggleDndMode();
            break;
        case "torch":
            SystemControlStore.toggleFlashlight();
            break;
        }
    }
}
