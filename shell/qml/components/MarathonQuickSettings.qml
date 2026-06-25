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

    // Tap anywhere outside the tiles/sliders → dismiss. TapHandler composes
    // with the MouseAreas inside MQSTile / MQSSlider — a tap that lands on
    // a tile is claimed by the tile first; a tap on the dim area below the
    // last tile reaches this handler. Without it, touches fall through to
    // whatever's behind quickSettings (the home grid) and partially light
    // up app icons under the dim overlay.
    TapHandler {
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: quickSettings.closed()
    }

    // Swipe-down anywhere in the shade also dismisses. Threshold matches
    // the up-from-indicator swipe used to open the shade.
    DragHandler {
        id: dismissDrag
        yAxis.enabled: true
        xAxis.enabled: false
        property real startY: 0
        onActiveChanged: {
            if (active) {
                startY = centroid.position.y;
            } else {
                const dy = centroid.position.y - startY;
                if (dy > 120 || centroid.velocity.y > 800)
                    quickSettings.closed();
            }
        }
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
            icon: "cell-signal-high",
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
            icon: "bell-slash",
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

        // ── Header — date only ──────────────────────────────
        // Per user direction the MARATHON brand lockup at the top of
        // Quick Settings was dropped. The status bar already carries
        // the brand; repeating it here was redundant. The date string
        // stays as the only ornament so the panel has a clear anchor.
        Item {
            width: parent.width
            height: 22

            // ddd · h:mm AP — re-evaluated every 30 s so the chip stays in
            // sync. Without the tick the string is frozen at QS-open time.
            property string dateText: Qt.formatDateTime(new Date(), "ddd · h:mm AP")
            Timer {
                interval: 30000
                running: quickSettings.visible
                repeat: true
                triggeredOnStart: true
                onTriggered: parent.dateText = Qt.formatDateTime(new Date(), "ddd · h:mm AP")
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: parent.dateText
                color: MColors.textSecondary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeFootnote
                font.features: ({
                        "tnum": 1
                    })
            }
        }

        // ── Sliders ──────────────────────────────────────────
        // DS-spec card: elev-2 fill, whiteOverlay04 border, 4 px radius.
        // Heights computed from the inner Column so sliders + halo
        // always fit cleanly inside without overflowing into the tile
        // grid below.
        Rectangle {
            width: parent.width
            height: slidersInner.height + 24       // 12 top + 12 bottom padding
            radius: MRadius.md
            color: MColors.elev2
            border.width: 1
            border.color: MColors.whiteOverlay04

            Column {
                id: slidersInner
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                anchors.topMargin: 12
                // JSX QuickSettings inner divider uses `margin: '12px 0'`
                // — i.e. 12 px gap above + below the hairline. Column spacing
                // applies between every child, so a value of 12 yields the
                // brightness/divider/volume rhythm the spec calls for.
                spacing: 12

                MQSSlider {
                    id: brightness
                    width: parent.width
                    iconName: "sun"
                    label: "Brightness"
                    value: SystemControlStore.brightness
                    onMoved: function (v) {
                        SystemControlStore.setBrightness(v);
                    }
                }
                Rectangle {
                    width: parent.width
                    height: 1
                    color: MColors.whiteOverlay04
                }
                MQSSlider {
                    id: volume
                    width: parent.width
                    iconName: "volume-2"
                    label: "Volume"
                    value: SystemControlStore.volume
                    onMoved: function (v) {
                        SystemControlStore.setVolume(v);
                    }
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
    // Sized + opacified to read as "grabbable" against the dimmed app
    // behind. Matches iOS Control Center pill and Android 16 shade
    // handle prominence — a thinner / lower-opacity pill reads as
    // decorative chrome.
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        width: 56
        height: 5
        radius: 2.5
        color: MColors.whiteOverlay24
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
