pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

// Quick Settings, laid out as Sailfish's top menu: the ambiences, a grid of
// switches, brightness and shortcuts; Marathon's extras below the fold.
// Notifications live in the Hub, not here.
Item {
    id: quickSettings

    readonly property real scaleFactor: Constants.scaleFactor || 1.0

    // The shade's fully-open height, supplied by the shell. `height` grows
    // from 0 while the shade opens, so it cannot be used to decide whether
    // the content overflows -- every open would briefly look like overflow
    // at every scale.
    property real maxHeight: 0

    // The wallpaper, frosted behind the shade as Sailfish frosts its ambience.
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

    // Backdrop: the ambience's wallpaper, lightly frosted, over any app or
    // the home screen alike. It keeps the open shade's size while the shade
    // animates and the shade clips it: resizing it every frame re-ran the
    // blur at 25-33 ms of GPU per frame on the PinePhone. A solid floor keeps
    // the shade opaque if the wallpaper is missing.
    Rectangle {
        anchors.fill: parent
        color: MColors.elev0
    }
    AppBackdropBlur {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: quickSettings.maxHeight
        source: quickSettings.homeBackdrop
        sourceRect: Qt.rect(0, 0, width, height)
        blurAmount: 1.0
        blurMax: MBlur.lg
        blurMultiplier: 2.2
        saturation: 0.8
        brightness: -0.05
        tint: Qt.rgba(0, 0, 0, 0.5)
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

    // ── The switch grid, five across as in Sailfish's top menu ─
    // Rotation lock only when an orientation sensor exists: without one it
    // would control nothing.
    readonly property var tiles: {
        var t = [
            { id: "wifi",      icon: "wifi-high",        label: "Wi-Fi",     on: SystemControlStore.isWifiOn },
            { id: "cellular",  icon: "cell-signal-high", label: "Mobile",    on: SystemControlStore.isCellularDataOn },
            { id: "bluetooth", icon: "bluetooth",        label: "Bluetooth", on: SystemControlStore.isBluetoothOn },
            { id: "airplane",  icon: "airplane-tilt",    label: "Flight",    on: SystemControlStore.isAirplaneModeOn },
            { id: "dnd",       icon: "bell-slash",       label: "Silent",    on: SystemControlStore.isDndMode },
            { id: "torch",     icon: "flashlight",       label: "Torch",     on: SystemControlStore.isFlashlightOn },
            { id: "location",  icon: "map-pin",          label: "Location",  on: SystemControlStore.isLocationOn },
            { id: "hotspot",   icon: "broadcast",        label: "Hotspot",   on: SystemControlStore.isHotspotOn },
            { id: "nightlight", icon: "moon",            label: "Night",     on: SystemControlStore.isNightLightOn }
        ];
        if (RotationManager.available)
            t.push({ id: "rotation", icon: "device-rotate", label: "Rotation", on: SystemControlStore.isRotationLocked });
        else
            t.push({ id: "autobrightness", icon: "sun", label: "Auto", on: SystemControlStore.isAutoBrightnessOn });
        return t;
    }

    // Below the fold: the rest of Marathon's controls.
    readonly property var moreTiles: {
        var t = [
            { id: "lowpower",  icon: "battery-low", label: "Saver",   on: SystemControlStore.isLowPowerMode },
            { id: "vibration", icon: "vibrate",     label: "Vibrate", on: SystemControlStore.isVibrationOn }
        ];
        if (RotationManager.available)
            t.push({ id: "autobrightness", icon: "sun", label: "Auto", on: SystemControlStore.isAutoBrightnessOn });
        t.push({ id: "power", icon: "power", label: "Power", on: false, action: true });
        return t;
    }

    // ── Shortcuts row: one-shot actions and apps ──────────────
    readonly property var shortcuts: [
        { id: "screenshot", icon: "camera-plus", label: "Screenshot" },
        { id: "app:camera", icon: "camera",      label: "Camera" },
        { id: "app:clock",  icon: "alarm",       label: "Alarm" },
        { id: "app:notes",  icon: "note-pencil", label: "Note" }
    ]

    component QSShortcut: Item {
        id: shortcut

        property string iconName
        property string label
        signal activated

        width: Silica.Theme.itemSizeExtraLarge
        height: shortcutColumn.height

        Column {
            id: shortcutColumn

            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Silica.Theme.paddingSmall

            GlyphIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: shortcut.iconName
                size: Silica.Theme.iconSizeSmall
                color: shortcutMouse.pressed ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: shortcut.label
                color: shortcutMouse.pressed ? Silica.Theme.highlightColor : Silica.Theme.secondaryColor
                font.family: Silica.Theme.fontFamily
                font.pixelSize: Silica.Theme.fontSizeTiny
            }
        }
        MouseArea {
            id: shortcutMouse

            anchors.fill: parent
            onClicked: {
                MHaptics.light();
                shortcut.activated();
            }
        }
    }

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

            // ── Ambiences: the wallpapers, one tap away ──────────
            ListView {
                id: ambiences

                width: parent.width
                height: Math.round(width / 3.6 * 1.25)
                orientation: ListView.Horizontal
                spacing: Silica.Theme.paddingSmall
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: WallpaperStore.wallpapers

                delegate: Item {
                    id: ambience

                    required property var modelData
                    readonly property bool current: modelData.path === WallpaperStore.path

                    width: Math.round(ambiences.width / 3.6)
                    height: ambiences.height

                    Image {
                        anchors.fill: parent
                        source: ambience.modelData.path
                        sourceSize: Qt.size(width, height * 2)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        opacity: ambienceMouse.pressed ? 0.7 : 1
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: ambienceName.height + Silica.Theme.paddingMedium * 2
                        gradient: Gradient {
                            GradientStop { position: 0; color: "transparent" }
                            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.6) }
                        }
                    }
                    Text {
                        id: ambienceName

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: Silica.Theme.paddingSmall
                        text: ambience.modelData.name
                        elide: Text.ElideRight
                        color: ambience.current ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
                        font.family: Silica.Theme.fontFamily
                        font.pixelSize: Silica.Theme.fontSizeExtraSmall
                    }
                    Rectangle {
                        anchors.fill: parent
                        visible: ambience.current
                        color: "transparent"
                        border.width: Math.max(2, Math.round(Silica.Theme.paddingSmall / 3))
                        border.color: Silica.Theme.highlightColor
                    }
                    MouseArea {
                        id: ambienceMouse

                        anchors.fill: parent
                        onClicked: WallpaperStore.setWallpaper(ambience.modelData.path, ambience.modelData.isDark)
                    }
                }
            }

            // ── Switches, five across ────────────────────────────
            Grid {
                id: tileGrid
                width: parent.width
                columns: 5
                rowSpacing: Silica.Theme.paddingMedium
                readonly property real cellWidth: width / columns

                Repeater {
                    model: quickSettings.tiles
                    delegate: MQSTile {
                        required property var modelData
                        width: tileGrid.cellWidth
                        iconName: modelData.icon
                        label: modelData.label
                        on: modelData.on === true
                        onToggled: quickSettings.toggle(modelData.id)
                    }
                }
            }

            MQSSlider {
                width: parent.width
                iconName: "sun"
                a11yName: "Brightness"
                value: SystemControlStore.brightness
                onMoved: v => SystemControlStore.setBrightnessFromUser(v)
            }

            // ── Shortcuts, and Settings at the end ───────────────
            Item {
                width: parent.width
                height: shortcutRow.height

                Row {
                    id: shortcutRow

                    Repeater {
                        model: quickSettings.shortcuts
                        delegate: QSShortcut {
                            required property var modelData
                            width: (tileGrid.width - settingsButton.width) / quickSettings.shortcuts.length
                            iconName: modelData.icon
                            label: modelData.label
                            onActivated: quickSettings.doAction(modelData.id)
                        }
                    }
                }
                QSShortcut {
                    id: settingsButton

                    anchors.right: parent.right
                    width: tileGrid.cellWidth
                    iconName: "gear"
                    label: qsTr("Settings")
                    onActivated: quickSettings.toggle("settings")
                }
            }

            // ── Below the fold: Marathon's extras ────────────────
            Text {
                width: parent.width
                topPadding: Silica.Theme.paddingLarge
                horizontalAlignment: Text.AlignRight
                text: qsTr("More controls")
                color: Silica.Theme.highlightColor
                font.family: Silica.Theme.fontFamily
                font.pixelSize: Silica.Theme.fontSizeSmall
            }

            MQSSlider {
                width: parent.width
                iconName: "speaker-high"
                a11yName: "Volume"
                value: SystemControlStore.volume
                onMoved: v => SystemControlStore.setVolume(v)
            }

            MNowBar {
                width: parent.width
                height: Math.max(implicitHeight, Silica.Theme.itemSizeSmall)
                variant: "music"
                iconName: "music-note"
                label: MPRIS2Controller.isPlaying ? (MPRIS2Controller.trackTitle || "Now Playing") : "Music"
                sublabel: MPRIS2Controller.isPlaying ? (MPRIS2Controller.trackArtist || "") : "Nothing playing · tap to open"
                playing: MPRIS2Controller.isPlaying
                onActivated: quickSettings.launchApp({ "appId": "music", "name": "Music" })
            }

            Grid {
                id: moreGrid
                width: parent.width
                columns: 5
                rowSpacing: Silica.Theme.paddingMedium

                Repeater {
                    model: quickSettings.moreTiles
                    delegate: MQSTile {
                        required property var modelData
                        width: tileGrid.cellWidth
                        iconName: modelData.icon
                        label: modelData.label
                        on: modelData.on === true
                        checkable: modelData.action !== true
                        onToggled: modelData.action === true ? quickSettings.doAction(modelData.id) : quickSettings.toggle(modelData.id)
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
        if (id.startsWith("app:")) {
            quickSettings.closed();
            quickSettings.launchApp({ "appId": id.slice(4) });
            return;
        }
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
