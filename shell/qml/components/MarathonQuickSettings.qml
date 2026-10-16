pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

// Quick Settings, laid out as Sailfish's top menu: Settings and Power, a grid
// of switches, the sliders, now playing and shortcuts. Ambiences are picked in
// Settings > Ambience; notifications live in the Hub.
Item {
    id: quickSettings

    readonly property real scaleFactor: Constants.scaleFactor || 1.0
    readonly property bool compactLayout: Constants.isSquareScreen || Constants.screenHeight < 800

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

    // Long-press on Hotspot shows what a client needs to join.
    property bool hotspotDetailsShown: false
    onVisibleChanged: if (!visible) hotspotDetailsShown = false

    // How far the shade is open, 0..1; drives the content reveal so it
    // follows the finger.
    readonly property real openProgress: Math.min(1, height / Math.max(1, maxHeight))

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
        // Overflowing content scrolls first; the shade closes from its end.
        // Held while active: shrinking the shade moves atYEnd.
        enabled: active || !shadeScroll.interactive || shadeScroll.atYEnd
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

    // ── The switch grid ───────────────────────────────────────
    // Settings › Quick settings switches tiles off by these IDs.
    function enabledOnly(list) {
        const enabled = SettingsManagerCpp.enabledQuickSettingsTiles;
        return list.filter(tile => enabled.indexOf(tile.id) >= 0);
    }

    // Hardware tiles only when the hardware exists: without it they control nothing.
    readonly property var tiles: {
        var t = [{ id: "wifi",      icon: "wifi-high",        label: "Wi-Fi",     on: SystemControlStore.isWifiOn }];
        if (ModemManagerCpp.modemAvailable)
            t.push({ id: "cellular",  icon: "cell-signal-high", label: "Mobile",    on: SystemControlStore.isCellularDataOn });
        t.push({ id: "bluetooth", icon: "bluetooth",        label: "Bluetooth", on: SystemControlStore.isBluetoothOn },
               { id: "airplane",  icon: "airplane-tilt",    label: "Flight",    on: SystemControlStore.isAirplaneModeOn },
               { id: "dnd",       icon: "bell-slash",       label: "Silent",    on: SystemControlStore.isDndMode });
        if (FlashlightManagerCpp.available)
            t.push({ id: "torch",     icon: "flashlight",       label: "Torch",     on: SystemControlStore.isFlashlightOn });
        t.push({ id: "location",  icon: "map-pin",          label: "Location",  on: SystemControlStore.isLocationOn },
               { id: "hotspot",   icon: "broadcast",        label: "Hotspot",   on: SystemControlStore.isHotspotOn },
               { id: "nightlight", icon: "moon",            label: "Night",     on: SystemControlStore.isNightLightOn });
        if (RotationManager.available)
            t.push({ id: "rotation", icon: "device-rotate", label: "Rotation", on: SystemControlStore.isRotationLocked });
        if (SensorManagerCpp.lightAvailable)
            t.push({ id: "autobrightness", icon: "sun",     label: "Auto",    on: SystemControlStore.isAutoBrightnessOn });
        t.push({ id: "lowpower",       icon: "battery-low", label: "Saver",   on: SystemControlStore.isLowPowerMode });
        if (HapticManager.available)
            t.push({ id: "vibration",  icon: "vibrate",     label: "Vibrate", on: SystemControlStore.isVibrationOn });
        return enabledOnly(t);
    }
    readonly property bool powerShown: SettingsManagerCpp.enabledQuickSettingsTiles.indexOf("power") >= 0

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
        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.onPressAction: activated()

        Column {
            id: shortcutColumn

            width: parent.width
            spacing: Silica.Theme.paddingSmall

            GlyphIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: shortcut.iconName
                size: Silica.Theme.iconSizeSmall
                color: shortcutMouse.pressed ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
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

    // A bare glyph, as Silica's IconButton.
    component HeaderButton: MouseArea {
        id: headerButton

        property string iconName
        property string a11yName

        width: Silica.Theme.itemSizeExtraSmall
        height: width
        Accessible.role: Accessible.Button
        Accessible.name: a11yName
        Accessible.onPressAction: clicked(null)

        GlyphIcon {
            anchors.centerIn: parent
            name: headerButton.iconName
            size: Silica.Theme.iconSizeSmall
            color: headerButton.pressed ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
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

    // Past roughly 1.4x display size the column is taller than the shade;
    // the Flickable scrolls only then, so at the default scale an upward
    // drag on the shade still closes it.
    Flickable {
        id: shadeScroll

        objectName: "shadeScroll"

        anchors.fill: parent
        // Clipping forces a scissor and breaks batching across the whole
        // shade, and `content` animates its opacity while the shade opens.
        clip: interactive
        contentHeight: content.y + content.height + Silica.Theme.paddingLarge
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: MMotion.flickDecelerationFast
        maximumFlickVelocity: MMotion.flickVelocity

        // Gated on the open height, not the animating one, so it does not
        // flip while the shade opens.
        interactive: quickSettings.maxHeight > 0 && contentHeight > quickSettings.maxHeight

        // The shade is hidden, not destroyed: reopen at the top.
        onVisibleChanged: if (!visible) contentY = 0

        Column {
            id: content

            x: Silica.Theme.horizontalPageMargin
            y: Silica.Theme.paddingMedium
            width: shadeScroll.width - Silica.Theme.horizontalPageMargin * 2
            spacing: quickSettings.compactLayout ? Silica.Theme.paddingLarge : Silica.Theme.paddingLarge * 2

            layer.enabled: true

            // Gesture-coupled reveal: fade + a small settle-up as the shade
            // opens; both collapse to a no-op under reduceMotion.
            opacity: MMotion.reduceMotion ? 1 : Math.min(1, quickSettings.openProgress * 1.35)
            transform: Translate {
                y: MMotion.reduceMotion ? 0 : (1 - quickSettings.openProgress) * Silica.Theme.paddingLarge
            }

            // ── Date, Settings and Power ─────────────────────────
            Item {
                width: parent.width
                height: Silica.Theme.itemSizeExtraSmall

                Silica.Label {
                    anchors.left: parent.left
                    anchors.right: headerButtons.left
                    anchors.verticalCenter: parent.verticalCenter
                    // As the Hub and lock screen write it; re-read at midnight.
                    text: Qt.formatDate(SystemStatusStore.dateString ? new Date() : new Date(), "dddd, d MMMM")
                    truncationMode: Silica.TruncationMode.Fade
                    color: Silica.Theme.secondaryHighlightColor
                    font.pixelSize: Silica.Theme.fontSizeSmall
                }
                Row {
                    id: headerButtons

                    anchors.right: parent.right
                    // Glyphs flush with the page margin.
                    anchors.rightMargin: -(Silica.Theme.itemSizeExtraSmall - Silica.Theme.iconSizeSmall) / 2

                    HeaderButton {
                        objectName: "settingsButton"
                        iconName: "gear"
                        a11yName: qsTr("Settings")
                        onClicked: quickSettings.toggle("settings")
                    }
                    HeaderButton {
                        objectName: "powerButton"
                        visible: quickSettings.powerShown
                        iconName: "power"
                        a11yName: qsTr("Power")
                        onClicked: quickSettings.doAction("power")
                    }
                }
            }

            // ── Switches, four across ────────────────────────────
            Grid {
                id: tileGrid

                objectName: "tileGrid"
                width: parent.width
                columns: 4
                rowSpacing: quickSettings.compactLayout ? Silica.Theme.paddingMedium : Silica.Theme.paddingLarge
                readonly property real cellWidth: width / columns

                Repeater {
                    model: quickSettings.tiles
                    delegate: MQSTile {
                        required property var modelData
                        width: tileGrid.cellWidth
                        iconName: modelData.icon
                        label: modelData.label
                        on: modelData.on === true
                        busy: SystemControlStore.pendingSwitches.indexOf(modelData.id) >= 0
                        onToggled: quickSettings.toggle(modelData.id)
                        onHeld: quickSettings.hold(modelData.id)
                    }
                }
            }

            Column {
                width: parent.width
                visible: quickSettings.hotspotDetailsShown

                Silica.DetailItem {
                    leftMargin: 0
                    rightMargin: 0
                    label: qsTr("Hotspot network")
                    value: SystemControlStore.hotspotSsid
                }
                Silica.DetailItem {
                    leftMargin: 0
                    rightMargin: 0
                    label: qsTr("Password")
                    value: SystemControlStore.hotspotPassword
                }
            }

            // ── Brightness and volume ────────────────────────────
            Column {
                width: parent.width

                MQSSlider {
                    objectName: "brightnessSlider"
                    width: parent.width
                    iconName: "sun"
                    a11yName: "Brightness"
                    value: SystemControlStore.brightness
                    onMoved: v => SystemControlStore.setBrightnessFromUser(v)
                }
                MQSSlider {
                    width: parent.width
                    iconName: "speaker-high"
                    a11yName: "Volume"
                    value: SystemControlStore.volume
                    onMoved: v => SystemControlStore.setVolume(v)
                }
            }

            MNowBar {
                objectName: "nowPlaying"
                readonly property bool active: MPRIS2Controller.hasActivePlayer
                width: parent.width
                height: Math.max(implicitHeight, Silica.Theme.itemSizeSmall)
                variant: "music"
                iconName: "music-note"
                // A radio stream may have no title; its station is the artist.
                label: active ? (MPRIS2Controller.trackTitle || MPRIS2Controller.trackArtist || MPRIS2Controller.playerName) : qsTr("Music")
                sublabel: active ? (MPRIS2Controller.trackTitle ? MPRIS2Controller.trackArtist : MPRIS2Controller.playerName) : qsTr("Nothing playing · tap to open")
                playing: MPRIS2Controller.isPlaying
                controls: active
                canGoPrevious: MPRIS2Controller.canGoPrevious
                canGoNext: MPRIS2Controller.canGoNext
                artworkSource: active ? MPRIS2Controller.albumArtUrl : ""
                onActivated: {
                    quickSettings.closed();
                    quickSettings.launchApp({ "id": active && MPRIS2Controller.desktopEntry ? MPRIS2Controller.desktopEntry : "music" });
                }
                onPreviousClicked: {
                    MHaptics.light();
                    MPRIS2Controller.previous();
                }
                onPlayPauseClicked: {
                    MHaptics.light();
                    MPRIS2Controller.playPause();
                }
                onNextClicked: {
                    MHaptics.light();
                    MPRIS2Controller.next();
                }
            }

            // ── Shortcuts, on the switch columns ─────────────────
            Row {
                Repeater {
                    model: quickSettings.shortcuts
                    delegate: QSShortcut {
                        required property var modelData
                        width: tileGrid.cellWidth
                        iconName: modelData.icon
                        label: modelData.label
                        onActivated: quickSettings.doAction(modelData.id)
                    }
                }
            }
        }
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
            quickSettings.launchApp({ "id": "settings", "name": "Settings" });
            break;
        }
    }

    function hold(id) {
        if (id !== "hotspot")
            return;
        MHaptics.light();
        SystemControlStore.ensureHotspotCredentials();
        hotspotDetailsShown = !hotspotDetailsShown;
    }

    function doAction(id) {
        if (id.startsWith("app:")) {
            quickSettings.closed();
            quickSettings.launchApp({ "id": id.slice(4) });
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
