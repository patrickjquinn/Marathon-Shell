pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

// Marathon DS · Quick Settings panel (§7.5).
//
// Pulled down from the top edge. Glass overlay over the wallpaper.
// Layout, top to bottom (content-rich single shade):
//   • Header — Sora Title3 time + Footnote date, left-anchored (live 1s tick)
//   • Sliders block — brightness + volume (MQSSlider)
//   • Primary tile grid — 4 cols × 2 rows of MQSTile (the common toggles)
//   • Now-playing strip — MNowBar (only when media/call active)
//   • "More Controls" — the secondary toggles, then Screenshot and Power
//   • Drag handle — 72 × 6 bar centred at bottom
//
// Notifications deliberately DO NOT live here — they belong to the Hub.
// This shade is controls-only: toggles + contextual controls + actions.
Item {
    id: quickSettings

    readonly property real scaleFactor: Constants.scaleFactor || 1.0

    // The shade's fully-open height, supplied by the shell. `height` grows
    // from 0 while the shade opens, so it cannot be used to decide whether
    // the content overflows -- every open would briefly look like overflow
    // at every scale.
    property real maxHeight: 0

    // The running app surface to blur behind the QS chrome, if any.
    // Set by MarathonShell.qml to appWindowContainer when an app is
    // open; null otherwise (a dark tint covers the wallpaper).
    property Item appBackdrop: null

    // The wallpaper surface to frost behind the shade when NO app is open.
    // Set by MarathonShell.qml. Lets the home-case shade read as frosted
    // glass over the wallpaper rather than a flat opaque panel.
    property Item homeBackdrop: null

    signal closed
    signal launchApp(var app)
    // Emitted when the Power quick-action is tapped. Wired by
    // MarathonShell.qml to showPowerMenu() — never a hard shutdown here.
    signal powerRequested

    // How far the shade is open, 0..1, derived from its own (animating,
    // drag-driven) height against the content it needs to show. Drives the
    // content reveal so the chrome MATERIALISES as the shade pulls down and
    // fades back out as it's dragged closed — motion coupled to the gesture,
    // not a canned one-shot. +140 keeps it ~1 before the last pixels arrive.
    readonly property real openProgress: Math.min(1, height / Math.max(1, content.implicitHeight + 140))

    // Cheap, blur-free contact shadow: a dark→transparent gradient cast just
    // below a floating card. Reads as real ambient occlusion on OLED without
    // a MultiEffect (per the DS perf rule — no per-frame Gaussian on etnaviv).
    // Drop as a child of any card; it anchors under the card's bottom edge.
    component QSContactShadow: Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.bottom
        height: 12
        z: -1
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.5) }
            GradientStop { position: 1.0; color: "transparent" }
        }
    }

    // Backdrop: live blur of the running app (iOS-style glass-over-app)
    // when one is open, dark tint over the wallpaper otherwise.
    //
    // Both backdrops keep the open shade's size while the shade animates;
    // the shade clips them. Filling the shade made every frame of the pull
    // resize the capture and the blur's render targets and re-run the whole
    // blur: 25-33 ms of GPU per frame on the PinePhone, about 30 fps. At a
    // fixed size the blur renders once and each frame draws one texture.
    AppBackdropBlur {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: quickSettings.maxHeight
        source: quickSettings.appBackdrop
        blurAmount: 1.0
        blurMax: MBlur.lg
        blurMultiplier: 1.4
        saturation: 0.5
        brightness: -0.1
        tint: Qt.rgba(13 / 255, 13 / 255, 14 / 255, 0.82)
        // QS shade is pulled over a snapshot — the underlying app is
        // either frozen or the wallpaper. Either way, no per-frame work.
        live: false
    }

    // Home case (no app behind): FROSTED MATTE glass over the wallpaper.
    // A solid elev0 floor guarantees the shade stays opaque if the wallpaper
    // source is ever missing; the blurred, heavily desaturated wallpaper on
    // top gives the shade a frosted-glass face (iOS Control-Center-over-home)
    // instead of a dead-flat black slab. Tuned MATTE, not glossy: high tint
    // opacity + low saturation + extra blur diffusion so it reads as etched/
    // sandblasted glass rather than a clear reflective pane. The elev0 floor
    // still keeps the elev2/elev3 cards reading as layered surfaces above it.
    Rectangle {
        anchors.fill: parent
        visible: quickSettings.appBackdrop === null
        color: MColors.elev0
    }
    AppBackdropBlur {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: quickSettings.maxHeight
        visible: quickSettings.appBackdrop === null
        source: quickSettings.homeBackdrop
        // 1:1 slice of the wallpaper (same size as the shade) — NOT the whole
        // frame squashed in, which produced the diagonal green smear. Heavy
        // blur + deep desaturation + a high matte tint turn it into an even,
        // milky frosted pane with only a whisper of wallpaper colour left.
        sourceRect: Qt.rect(0, 0, width, height)
        blurAmount: 1.0
        blurMax: MBlur.lg
        blurMultiplier: 2.2
        saturation: 0.2
        brightness: -0.1
        tint: Qt.rgba(0.05, 0.055, 0.062, 0.82)
        live: false
    }

    // Tap anywhere outside the tiles/sliders → dismiss. TapHandler composes
    // with the MouseAreas inside MQSTile / MQSSlider — a tap that lands on
    // a control is claimed by it first; a tap on the dim area reaches here.
    TapHandler {
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: quickSettings.closed()
    }

    // Drag inside the shade for "follow-finger then snap" close. Grabs
    // the shade chrome (NOT tiles/sliders) and shrinks quickSettingsHeight
    // per-frame as the finger moves up; snaps open/closed on release.
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
            if (dy >= 0) {
                // pull-down past open → iOS rubber-band resistance
                const c = 0.55;
                const dim = Math.max(1, startHeight);
                const resisted = dim - dim / (dy * c / dim + 1);
                UIStore.quickSettingsHeight = startHeight + resisted;
            } else {
                // pull-up shrinking toward 0 → linear (natural close)
                UIStore.quickSettingsHeight = Math.max(0, startHeight + dy);
            }
        }
    }

    // ── Primary toggles (the everyday four-plus-four) ────────
    readonly property var tiles: [
        { id: "wifi",           icon: "wifi-high",        label: "Wi-Fi",     on: SystemControlStore.isWifiOn },
        { id: "bluetooth",      icon: "bluetooth",        label: "Bluetooth", on: SystemControlStore.isBluetoothOn },
        { id: "cellular",       icon: "cell-signal-high", label: "Mobile",    on: SystemControlStore.isCellularDataOn },
        { id: "airplane",       icon: "airplane-tilt",    label: "Flight",    on: SystemControlStore.isAirplaneModeOn },
        { id: "dnd",            icon: "bell-slash",       label: "DND",       on: SystemControlStore.isDndMode },
        { id: "torch",          icon: "flashlight",       label: "Torch",     on: SystemControlStore.isFlashlightOn },
        { id: "autobrightness", icon: "sun",              label: "Auto",      on: SystemControlStore.isAutoBrightnessOn },
        { id: "settings",       icon: "gear",             label: "Settings",  on: false }
    ]

    // ── Secondary contextual controls (beyond the toggles) ───
    // Rotation lock is only shown when an orientation sensor actually exists.
    // On hardware with no accelerometer (e.g. Librem 5 with lsm6dsx
    // blacklisted) auto-rotate can never fire, so a rotation-LOCK toggle
    // would control nothing — hide it rather than present a dead switch.
    readonly property var expandedTiles: {
        var t = [];
        if (RotationManager.available)
            t.push({ id: "rotation", icon: "device-rotate", label: "Rotation", on: SystemControlStore.isRotationLocked });
        t.push({ id: "nightlight", icon: "moon",        label: "Night",    on: SystemControlStore.isNightLightOn });
        t.push({ id: "location",   icon: "map-pin",     label: "Location", on: SystemControlStore.isLocationOn });
        t.push({ id: "hotspot",    icon: "broadcast",   label: "Hotspot",  on: SystemControlStore.isHotspotOn });
        t.push({ id: "lowpower",   icon: "battery-low", label: "Saver",    on: SystemControlStore.isLowPowerMode });
        t.push({ id: "vibration",  icon: "vibrate",     label: "Vibrate",  on: SystemControlStore.isVibrationOn });
        return t;
    }

    // ── One-shot actions (distinct from toggles) ─────────────
    readonly property var actions: [
        { id: "screenshot", icon: "camera", label: "Screenshot" },
        { id: "power",      icon: "power",  label: "Power" }
    ]

    // ── Bottom edge terminus — soft hairline + shadow line ───
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

    // The shade is a fixed-height surface but its contents are all scaled
    // tokens, so past roughly 1.4x display size the column is taller than
    // the shade and the Screenshot / Lock / Power row was simply sliced off
    // the bottom with no way to reach it.
    //
    // interactive is gated on actual overflow: at the shipping default the
    // content fits, the Flickable is inert, and drag-to-close behaves
    // exactly as before. The dismiss DragHandler above deliberately grabs
    // only the shade chrome and never the tiles/sliders, so this does not
    // take a gesture that used to close the shade.
    Flickable {
        id: shadeScroll

        anchors.fill: parent
        // Leave the drag handle at the bottom uncovered. Ask it for its
        // geometry rather than restating it -- resizing the handle would
        // otherwise silently re-clip the last row.
        anchors.bottomMargin: dragHandle.height + MSpacing.md * 2
        // Clipping forces a scissor and breaks batching across the whole
        // shade, and `content` animates its opacity while the shade opens.
        // Only pay for it when there is actually something to scroll.
        clip: interactive
        contentHeight: content.y + content.height + MSpacing.lg
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: MMotion.flickDecelerationFast

        // Gated on the OPEN height, not the live one, so this is a function
        // of display scale alone and does not flip during the open
        // animation.
        //
        // Tradeoff, stated plainly: this Flickable fills the shade, and the
        // dismiss DragHandler on the root has no bounds -- it worked only
        // because the gaps between tiles had no other grabber. So when this
        // is interactive, an upward drag on the shade body scrolls instead
        // of closing. That only happens at the scales where the bottom
        // controls were previously unreachable, and closing is still
        // available from the drag handle below, a tap anywhere on the
        // shade, and the nav bar.
        // Compare against this Flickable's own settled viewport, not the
        // shade's: the viewport is shorter by the drag-handle margin, and
        // measuring against the shade made the threshold ~44px too high --
        // the shade stopped scrolling at exactly the scales that need it.
        readonly property real settledViewportHeight: quickSettings.maxHeight
                                                      - anchors.bottomMargin
        interactive: quickSettings.maxHeight > 0
                     && contentHeight > settledViewportHeight

        // The shade is hidden, not destroyed, so contentY survives a
        // close/reopen: without this it would reopen still scrolled to the
        // action row with the clock and sliders off the top.
        onVisibleChanged: if (!visible) contentY = 0

        Column {
            id: content

            x: Silica.Theme.horizontalPageMargin
            y: Silica.Theme.paddingLarge
            width: shadeScroll.width - Silica.Theme.horizontalPageMargin * 2
            spacing: Silica.Theme.paddingMedium

            layer.enabled: true

            // Gesture-coupled reveal: fade + a small settle-up as the shade
            // opens; both collapse to a no-op under reduceMotion. Anchored to
            // the top and clip:true on the shade, so translating down just
            // exposes panel above — never overlaps the status bar.
            opacity: MMotion.reduceMotion ? 1 : Math.min(1, quickSettings.openProgress * 1.35)
            transform: Translate {
                y: MMotion.reduceMotion ? 0 : (1 - quickSettings.openProgress) * 16
            }

            // ── Header — live time + date, left-anchored ─────────
            Item {
                id: header
                width: parent.width
                height: headerText.implicitHeight

                property string dateText: Qt.formatDateTime(new Date(), "dddd, MMMM d")
                property string timeText: Qt.formatDateTime(new Date(), SettingsManagerCpp.timeFormat === "12h" ? "h:mm AP" : "HH:mm")
                // 1s tick so the shade clock never lags the status bar clock.
                Timer {
                    interval: 1000
                    running: quickSettings.visible
                    repeat: true
                    triggeredOnStart: true
                    onTriggered: {
                        header.dateText = Qt.formatDateTime(new Date(), "dddd, MMMM d");
                        header.timeText = Qt.formatDateTime(new Date(), SettingsManagerCpp.timeFormat === "12h" ? "h:mm AP" : "HH:mm");
                    }
                }

                Column {
                    id: headerText
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    Text {
                        text: header.timeText
                        color: Silica.Theme.highlightColor
                        font.family: Silica.Theme.fontFamilyHeading
                        font.pixelSize: Silica.Theme.fontSizeLarge
                        font.features: ({ "tnum": 1 })
                    }
                    Text {
                        text: header.dateText
                        color: Silica.Theme.secondaryHighlightColor
                        font.family: Silica.Theme.fontFamily
                        font.pixelSize: Silica.Theme.fontSizeSmall
                    }
                }
            }

            // ── Sliders — brightness + volume ────────────────────
            Column {
                width: parent.width

                MQSSlider {
                    id: brightness
                    width: parent.width
                    iconName: "sun"
                    a11yName: "Brightness"
                    value: SystemControlStore.brightness
                    onMoved: v => SystemControlStore.setBrightnessFromUser(v)
                }
                MQSSlider {
                    id: volume
                    width: parent.width
                    iconName: "speaker-high"
                    a11yName: "Volume"
                    value: SystemControlStore.volume
                    onMoved: v => SystemControlStore.setVolume(v)
                }
            }

            // ── Primary tile grid (4 × 2) ────────────────────────
            Grid {
                id: tileGrid
                width: parent.width
                columns: 4
                rowSpacing: Silica.Theme.paddingMedium
                readonly property real cellWidth: width / 4

                Repeater {
                    model: quickSettings.tiles
                    delegate: MQSTile {
                        required property var modelData
                        width: tileGrid.cellWidth
                        iconName: modelData.icon || "square"
                        label: modelData.label || ""
                        on: modelData.on === true
                        onToggled: quickSettings.toggle(modelData.id)
                    }
                }
            }

            // ── Now-playing strip — always present ────────────────
            // When media is live it shows the track; when idle it stays as a
            // "tap to open Music" affordance rather than collapsing to a void.
            // The whole strip taps through to Music either way. Wrapped so it
            // carries a contact shadow and sits at a card-weight 56 design-px
            // height (the bare NowBar read as loose text jammed between grids).
            Item {
                width: parent.width
                // Card weight is the floor; the bar's own content height wins
                // if it is taller. This used to be a flat 76 chosen to clear
                // the two eyebrow line-boxes at scaleFactor 1.79 — a caller-
                // side workaround for MNowBar not scaling its own geometry.
                // MNowBar now sizes to its text, so ask it instead of guessing.
                height: Math.max(nowBar.implicitHeight,
                                 Math.round(56 * quickSettings.scaleFactor))

                QSContactShadow {}

                MNowBar {
                    id: nowBar
                    anchors.fill: parent
                    variant: "music"
                    iconName: "music-note"
                    label: MPRIS2Controller.isPlaying ? (MPRIS2Controller.trackTitle || "Now Playing") : "Music"
                    sublabel: MPRIS2Controller.isPlaying ? (MPRIS2Controller.trackArtist || "") : "Nothing playing · tap to open"
                    playing: MPRIS2Controller.isPlaying
                    onActivated: quickSettings.launchApp({ "appId": "music", "name": "Music" })
                }
            }

            // ── Section label ────────────────────────────────────
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignRight
                text: qsTr("More controls")
                color: Silica.Theme.highlightColor
                font.family: Silica.Theme.fontFamily
                font.pixelSize: Silica.Theme.fontSizeSmall
            }

            // ── Secondary toggles, then one-shot actions ─────────
            Grid {
                id: expandedGrid
                width: parent.width
                columns: 4
                rowSpacing: Silica.Theme.paddingMedium
                readonly property real cellWidth: width / 4

                Repeater {
                    model: quickSettings.expandedTiles
                    delegate: MQSTile {
                        required property var modelData
                        width: expandedGrid.cellWidth
                        iconName: modelData.icon || "square"
                        label: modelData.label || ""
                        on: modelData.on === true
                        onToggled: quickSettings.toggle(modelData.id)
                    }
                }
                Repeater {
                    model: quickSettings.actions
                    delegate: MQSTile {
                        required property var modelData
                        width: expandedGrid.cellWidth
                        iconName: modelData.icon
                        label: modelData.label
                        checkable: false
                        onToggled: {
                            MHaptics.light();
                            quickSettings.doAction(modelData.id);
                        }
                    }
                }
            }
        }
    }

    // ── Drag handle ─────────────────────────────────────────
    Rectangle {
        id: dragHandle
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
        case "wifi":           SystemControlStore.toggleWifi(); break;
        case "bluetooth":      SystemControlStore.toggleBluetooth(); break;
        case "cellular":       SystemControlStore.toggleCellularData(); break;
        case "airplane":       SystemControlStore.toggleAirplaneMode(); break;
        case "dnd":            SystemControlStore.toggleDndMode(); break;
        case "torch":          SystemControlStore.toggleFlashlight(); break;
        case "autobrightness": SystemControlStore.toggleAutoBrightness(); break;
        case "rotation":       SystemControlStore.toggleRotationLock(); break;
        case "nightlight":     SystemControlStore.toggleNightLight(); break;
        case "location":       SystemControlStore.toggleLocation(); break;
        case "hotspot":        SystemControlStore.toggleHotspot(); break;
        case "lowpower":       SystemControlStore.toggleLowPowerMode(); break;
        case "vibration":      SystemControlStore.toggleVibration(); break;
        case "settings":
            quickSettings.closed();
            quickSettings.launchApp({ "appId": "settings", "name": "Settings" });
            break;
        }
    }

    function doAction(id) {
        switch (id) {
        case "screenshot":
            // Dismiss first so the shade isn't in the capture.
            quickSettings.closed();
            SystemControlStore.captureScreenshot();
            break;
        case "power":
            quickSettings.closed();
            quickSettings.powerRequested();
            break;
        }
    }
}
