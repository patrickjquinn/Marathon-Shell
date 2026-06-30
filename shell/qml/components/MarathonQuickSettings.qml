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
        blurMax: MBlur.lg
        blurMultiplier: 1.4
        saturation: 0.5
        brightness: -0.1
        tint: Qt.rgba(13 / 255, 13 / 255, 14 / 255, 0.55)
        // QS shade is pulled over a snapshot — the underlying app is
        // either frozen or the wallpaper. Either way, no per-frame work.
        live: false
    }

    // Opaque tint when no app is open behind the shade. 0.95 was already
    // dark, but the home grid icons (App Store, Music, etc.) still bled
    // through enough to make the shade feel like a translucent veil
    // instead of a real surface. Marathon DS calls for the QS shade to
    // read as a discrete panel — bump to elev1 fully opaque + a soft
    // hairline at the very bottom so the panel has a clear terminus.
    Rectangle {
        anchors.fill: parent
        visible: quickSettings.appBackdrop === null
        color: MColors.elev1
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

    // Drag inside the shade for "follow-finger then snap" close. Grabs
    // the shade chrome (NOT tiles/sliders — those steal input via their
    // own MouseAreas) and shrinks UIStore.quickSettingsHeight per-frame
    // as the finger moves up. On release, snap-back if drag < threshold
    // or snap-closed if fling/distance exceeds threshold.
    //
    // This is what makes the shade FEEL like a panel you can grab and
    // collapse rather than a static overlay that dismisses by magic.
    // Matches iOS Control Center + Android 16 shade behaviour.
    DragHandler {
        id: dismissDrag
        target: null
        yAxis.enabled: true
        xAxis.enabled: false
        property real startY: 0
        property real startHeight: 0
        onActiveChanged: {
            if (active) {
                startY = centroid.position.y;
                startHeight = UIStore.quickSettingsHeight;
                UIStore.quickSettingsDragging = true;
            } else {
                UIStore.quickSettingsDragging = false;
                const dy = centroid.position.y - startY;
                const vy = centroid.velocity.y;
                // Fling up OR more than a third of the shade swept up → close.
                // Otherwise spring back to fully open.
                if (vy < -800 || -dy > startHeight * 0.33)
                    UIStore.closeQuickSettings();
                else
                    UIStore.openQuickSettings();
            }
        }
        onCentroidChanged: {
            if (!active)
                return;
            const dy = centroid.position.y - startY;
            // Rubber-band on the dragged-PAST-open direction (dy > 0,
            // i.e. user pulling DOWN past the fully-open shade). iOS
            // formula: extra = travel - (travel / (extra * c / dim + 1))
            // where c≈0.55 and dim is the dimension we're resisting
            // against. We pick startHeight as the dim so the resistance
            // scales with the shade's open size.
            //
            // Within the legitimate range (dy ≤ 0, shrinking up to
            // fully-closed) we still hard-clamp at 0 — you can't make
            // the shade shorter than collapsed.
            if (dy >= 0) {
                // pull-down past open → rubber-band resistance
                const c = 0.55;
                const dim = Math.max(1, startHeight);
                const extra = dy;
                const resisted = dim - dim / (extra * c / dim + 1);
                UIStore.quickSettingsHeight = startHeight + resisted;
            } else {
                // pull-up shrinking toward 0 → linear (no resistance on
                // the natural close direction)
                UIStore.quickSettingsHeight = Math.max(0, startHeight + dy);
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
            sub: SystemControlStore.isWifiOn ? (SystemStatusStore.wifiNetwork || "") : ""
        },
        {
            id: "bluetooth",
            icon: "bluetooth",
            label: "Bluetooth",
            on: SystemControlStore.isBluetoothOn,
            sub: ""
        },
        {
            id: "cellular",
            icon: "cell-signal-high",
            label: "Mobile",
            on: SystemControlStore.isCellularDataOn,
            sub: ""
        },
        {
            id: "airplane",
            icon: "plane",
            label: "Flight",
            on: SystemControlStore.isAirplaneModeOn,
            sub: ""
        },
        {
            id: "dnd",
            icon: "bell-slash",
            label: "DND",
            on: SystemControlStore.isDndMode,
            sub: ""
        },
        {
            id: "torch",
            icon: "flashlight",
            label: "Torch",
            on: SystemControlStore.isFlashlightOn,
            sub: ""
        },
        {
            id: "autobrightness",
            icon: "sun-medium",
            label: "Auto",
            on: SystemControlStore.isAutoBrightnessOn,
            sub: ""
        },
        {
            id: "settings",
            icon: "settings",
            label: "Settings",
            on: false,
            sub: ""
        }
    ]

    // ── Bottom edge boundary ─────────────────────────────────
    // The shade had no visible terminus — it just faded into the home
    // grid via the dim Rectangle. iOS Control Center / Android 16 both
    // anchor the bottom of the shade with a soft hairline + 1 px shadow
    // line that reads as "the panel ends HERE."
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: MColors.whiteOverlay16
        z: 2
    }
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 1
        height: 1
        color: Qt.rgba(0, 0, 0, 0.45)
        z: 2
    }

    Column {
        id: content

        anchors.fill: parent
        anchors.leftMargin: MSpacing.lg     // 20 px — matches DS panel inset
        anchors.rightMargin: MSpacing.lg
        anchors.topMargin: MSpacing.md      // 14 px under the status bar
        spacing: MSpacing.md                // 14 px section rhythm

        // ── Header — Sora Title3 time + Sora Footnote date, left-anchored.
        // The right-aligned 12 px Footnote was dust. iOS centers a big
        // date/time block as the shade's anchor; Android puts the date
        // top-left + battery top-right. Marathon left-anchors the stack
        // at Title3 so the panel has a clear focal point at top.
        Item {
            id: header
            width: parent.width
            height: 44

            property string dateText: Qt.formatDateTime(new Date(), "dddd, MMMM d")
            property string timeText: Qt.formatDateTime(new Date(), SettingsManagerCpp.timeFormat === "12h" ? "h:mm AP" : "HH:mm")
            Timer {
                interval: 30000
                running: quickSettings.visible
                repeat: true
                triggeredOnStart: true
                onTriggered: {
                    header.dateText = Qt.formatDateTime(new Date(), "dddd, MMMM d");
                    header.timeText = Qt.formatDateTime(new Date(), SettingsManagerCpp.timeFormat === "12h" ? "h:mm AP" : "HH:mm");
                }
            }

            Column {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    text: header.timeText
                    color: MColors.textPrimary
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeTitle3
                    font.weight: MTypography.weightDemiBold
                    font.features: ({
                            "tnum": 1
                        })
                }
                Text {
                    text: header.dateText
                    color: MColors.textSecondary
                    font.family: MTypography.fontFamily
                    font.pixelSize: MTypography.sizeFootnote
                    font.weight: MTypography.weightMedium
                }
            }
        }

        // ── Sliders ──────────────────────────────────────────
        // World-class slider card: elev-2 fill, whiteOverlay08 border
        // (was 04 — invisible against the dark backdrop), 8 px radius,
        // 18 px vertical padding so the fatter 8 px tracks + 26 px thumb
        // halo breathe.
        Rectangle {
            width: parent.width
            height: slidersInner.height + 36       // 18 top + 18 bottom padding
            radius: MRadius.md
            color: MColors.elev2
            border.width: 1
            border.color: MColors.whiteOverlay16

            // Inner top-only hairline for sub-pixel chrome on glass.
            MTopHairline {
                radius: parent.radius
                color: MColors.whiteOverlay16
                lineWidth: 1
            }

            Column {
                id: slidersInner
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 18
                spacing: 16

                MQSSlider {
                    id: brightness
                    width: parent.width
                    iconName: "sun"
                    value: SystemControlStore.brightness
                    onMoved: function (v) {
                        SystemControlStore.setBrightness(v);
                    }
                }
                Rectangle {
                    width: parent.width
                    height: 1
                    color: MColors.whiteOverlay08
                }
                MQSSlider {
                    id: volume
                    width: parent.width
                    iconName: "volume-2"
                    value: SystemControlStore.volume
                    onMoved: function (v) {
                        SystemControlStore.setVolume(v);
                    }
                }
            }
        }

        // ── Tile grid (4 cols × 2 rows) ──────────────────────
        // BB10-modern density: compact square tiles, icon top-centered,
        // label below. 4×2 fits 8 actions without scrolling — the spec
        // pages above 8 to a second grid (not implemented yet; reserved).
        Grid {
            id: tileGrid
            width: parent.width
            columns: 4
            rowSpacing: 10
            columnSpacing: 10
            readonly property real cellWidth: (width - columnSpacing * 3) / 4

            Repeater {
                model: quickSettings.tiles
                delegate: MQSTile {
                    required property int index
                    required property var modelData
                    width: tileGrid.cellWidth
                    iconName: modelData.icon || "square"
                    label: modelData.label || ""
                    on: modelData.on === true
                    onToggled: quickSettings.toggle(modelData.id)
                }
            }
        }

        // ── Page indicator ──────────────────────────────────
        // 28 × 6 tealBright pill for the active page + 8 × 8 dim dots
        // for the rest. Previous 18 × 4 was below the system-wide
        // "minimum legible" threshold on a 720 px panel — it read as a
        // typo, not a control.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: MSpacing.sm

            readonly property int pages: 1   // bump when tile pages > 1

            Rectangle {
                width: 28
                height: 6
                radius: MRadius.sm
                color: MColors.marathonTealBright
                anchors.verticalCenter: parent.verticalCenter
            }
            Repeater {
                model: Math.max(0, parent.pages - 1)
                delegate: Rectangle {
                    required property int index
                    width: 8
                    height: 8
                    radius: 4
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
    // Visible pill at the bottom of the shade. iOS Control Center pill
    // is 60×5 white@70%, Android 16 is 32×4 white@40% — we land between
    // (closer to iOS) so the handle reads as a definitive "grab here"
    // affordance against the elev-1 panel.
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: MSpacing.md
        width: 72
        height: 6
        radius: MRadius.md
        color: Qt.rgba(1, 1, 1, 0.72)
        z: 3
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
        case "autobrightness":
            SystemControlStore.toggleAutoBrightness();
            break;
        case "settings":
            quickSettings.closed();
            quickSettings.launchApp({
                "appId": "settings",
                "name": "Settings"
            });
            break;
        }
    }
}
