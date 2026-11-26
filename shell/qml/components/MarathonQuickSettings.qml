pragma ComponentBehavior: Bound

import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

// Quick Settings, laid out as a top menu: Settings and Power, a grid
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

    // What the shade frosts, bottom to top: the open app, or the wallpaper
    // and the home screen.

    signal closed
    signal launchApp(var app)
    // Emitted when the Power quick-action is tapped. Wired by
    // MarathonShell.qml to showPowerMenu() — never a hard shutdown here.
    signal powerRequested

    // Long-press on Hotspot shows what a client needs to join.
    property bool hotspotDetailsShown: false
    onVisibleChanged: if (!visible)
        hotspotDetailsShown = false

    // How far the shade is open, 0..1; drives the content reveal so it
    // follows the finger.
    readonly property real openProgress: Math.min(1, height / Math.max(1, maxHeight))

    // The ambience, flat, at the open shade's size so a drag doesn't reload it;
    // the shade clips it.
    KeelAmbienceBackground {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: quickSettings.maxHeight
        wallpaper: AmbienceService.wallpaperUrl
        light: AmbienceService.light
        brightest: AmbienceService.brightest
        darkest: AmbienceService.darkest
    }

    // The drawn height: follows UIStore while a finger drags the shade and
    // springs to each new height from the release velocity.
    readonly property alias drawnHeight: shadeDrag.value
    property bool captureWhenClosed: false

    onDrawnHeightChanged: if (captureWhenClosed && drawnHeight <= 0) {
        captureWhenClosed = false;
        Qt.callLater(SystemControlStore.captureScreenshot);
    }
    readonly property alias tracker: shadeDrag

    // A drag always comes to rest shut or fully open.
    function rest() {
        if (UIStore.quickSettingsDragging)
            return;
        const h = UIStore.quickSettingsHeight;
        if (h !== 0 && h !== maxHeight) {
            if (UIStore.quickSettingsOpen)
                UIStore.openQuickSettings();
            else
                UIStore.closeQuickSettings();
        }
        if (!shadeDrag.settling && shadeDrag.value !== UIStore.quickSettingsHeight)
            shadeDrag.settleTo(UIStore.quickSettingsHeight);
    }

    GestureTracker {
        id: shadeDrag

        commitDistance: quickSettings.maxHeight * Constants.quickSettingsDismissThreshold
        settleDuration: MMotion.reduceMotion ? MMotion.micro : Constants.animationSlow
    }

    Connections {
        function onQuickSettingsHeightChanged() {
            if (UIStore.quickSettingsDragging)
                shadeDrag.move(UIStore.quickSettingsHeight);
            else
                shadeDrag.settleTo(UIStore.quickSettingsHeight);
        }
        // Keeps the release velocity for the settle that follows. The drag's
        // owner decides once this returns; rest() catches one that did not.
        function onQuickSettingsDraggingChanged() {
            if (UIStore.quickSettingsDragging)
                return;
            if (shadeDrag.active)
                shadeDrag.release();
            Qt.callLater(quickSettings.rest);
        }

        target: UIStore
    }

    // Drag inside the shade for "follow-finger then snap" close. Grabs
    // the shade chrome (NOT tiles/sliders) and shrinks quickSettingsHeight
    // per-frame as the finger moves up; snaps open/closed on release.
    MAxisDrag {
        id: dismissDrag
        // Overflowing content scrolls first; the shade closes from its end.
        // Held while active: shrinking the shade moves atYEnd.
        // E-paper pages the content (einkScroll), which closes past its end.
        enabled: active || !shadeScroll.overflows || (!MMotion.instant && shadeScroll.atYEnd)
        horizontal: false
        property real startY: 0
        property real startHeight: 0
        // E-paper: the shade stays put, and closes in one cut once the swipe
        // up passes a share of it.
        function closeOnPaper() {
            if (UIStore.quickSettingsOpen && startY - along(centroid.scenePosition) > startHeight * MMotion.swipeShare) {
                UIStore.quickSettingsDragging = false;
                UIStore.closeQuickSettings();
            }
        }
        onActiveChanged: {
            if (active) {
                startY = along(MMotion.instant ? centroid.scenePressPosition : centroid.scenePosition);
                // From where the shade is drawn: a settle in flight is caught, not skipped.
                startHeight = quickSettings.drawnHeight;
                UIStore.quickSettingsDragging = true;
                // E-paper: the whole swipe may arrive in this one update.
                if (MMotion.instant)
                    closeOnPaper();
            } else {
                UIStore.quickSettingsDragging = false;
                const dy = along(centroid.scenePosition) - startY;
                const vy = speed();
                // E-paper: a swipe up closed it already, or a flick does now.
                if (MMotion.instant) {
                    if (vy < -800)
                        UIStore.closeQuickSettings();
                    return;
                }
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
            const dy = along(centroid.scenePosition) - startY;
            if (MMotion.instant) {
                closeOnPaper();
                return;
            }
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

    function onOff(on) {
        return on ? qsTr("On") : qsTr("Off");
    }
    function signalWord(percent) {
        return percent >= 75 ? qsTr("strong") : percent >= 50 ? qsTr("good") : percent >= 25 ? qsTr("fair") : qsTr("weak");
    }
    readonly property var bluetoothDevice: BluetoothManagerCpp.pairedDevices.find(d => d.connected) || null

    // Hardware tiles only when the hardware exists: without it they control nothing.
    // `route` is the Settings page holding a tile opens. The order is the pages'.
    readonly property var tiles: {
        const wifiOn = SystemControlStore.shown("wifi", SystemControlStore.isWifiOn);
        const wifiJoined = wifiOn && SystemStatusStore.wifiConnected && SystemStatusStore.wifiNetwork !== "";
        var t = [];
        if (Network.wifiAvailable)
            t.push({
                id: "wifi",
                icon: "wifi-high",
                route: "wifi",
                label: wifiJoined ? SystemStatusStore.wifiNetwork : qsTr("Wi-Fi"),
                //: Quick settings Wi-Fi tile status, e.g. "Wi-Fi · strong"
                status: wifiJoined ? qsTr("Wi-Fi · %1").arg(signalWord(SystemStatusStore.wifiStrength)) : wifiOn ? qsTr("Not connected") : qsTr("Off"),
                on: wifiOn
            });
        if (Modem.modemAvailable) {
            const dataOn = SystemControlStore.shown("cellular", SystemControlStore.isCellularDataOn);
            t.push({
                id: "cellular",
                icon: "cell-signal-high",
                route: "cellular",
                label: SystemStatusStore.carrier || qsTr("Mobile"),
                //: Quick settings mobile tile status: network type and signal, e.g. "LTE · good"
                status: dataOn ? (SystemStatusStore.dataType ? qsTr("%1 · %2").arg(SystemStatusStore.dataType).arg(signalWord(SystemStatusStore.cellularStrength)) : signalWord(SystemStatusStore.cellularStrength)) : qsTr("Data off"),
                on: dataOn
            });
        }
        const btOn = SystemControlStore.shown("bluetooth", SystemControlStore.isBluetoothOn);
        t.push({
            id: "bluetooth",
            icon: "bluetooth",
            route: "bluetooth",
            label: btOn && bluetoothDevice ? (bluetoothDevice.alias || bluetoothDevice.name) : qsTr("Bluetooth"),
            status: !btOn ? qsTr("Off") : bluetoothDevice ? qsTr("Connected") : qsTr("On · no device"),
            on: btOn
        }, {
            id: "airplane",
            icon: "airplane-tilt",
            label: qsTr("Flight"),
            on: SystemControlStore.shown("airplane", SystemControlStore.isAirplaneModeOn)
        }, {
            id: "dnd",
            route: "notifications",
            icon: "bell-slash",
            label: qsTr("Silent"),
            on: SystemControlStore.isDndMode
        });
        if (FlashlightManagerCpp.available)
            t.push({
                id: "torch",
                icon: "flashlight",
                label: qsTr("Torch"),
                on: SystemControlStore.isFlashlightOn
            });
        if (Network.hotspotSupported)
            t.push({
                id: "hotspot",
                icon: "broadcast",
                label: qsTr("Hotspot"),
                on: SystemControlStore.shown("hotspot", SystemControlStore.isHotspotOn)
            });
        t.push({
            id: "location",
            icon: "map-pin",
            label: qsTr("Location"),
            on: SystemControlStore.isLocationOn
        }, {
            id: "nightlight",
            route: "display",
            icon: "moon",
            label: qsTr("Night"),
            on: SystemControlStore.isNightLightOn
        });
        if (Display.rotationAvailable)
            t.push({
                id: "rotation",
                route: "display",
                icon: "device-rotate",
                label: qsTr("Rotate"),
                status: SystemControlStore.isRotationLocked ? qsTr("Locked") : qsTr("Auto"),
                on: !SystemControlStore.isRotationLocked
            });
        if (Display.lightAvailable)
            t.push({
                id: "autobrightness",
                route: "display",
                icon: "sun",
                label: qsTr("Brightness"),
                //: Quick settings brightness tile status, e.g. "Auto · 24%"
                status: (SystemControlStore.isAutoBrightnessOn ? qsTr("Auto · %1%") : qsTr("Manual · %1%")).arg(Math.round(SystemControlStore.brightness)),
                on: SystemControlStore.isAutoBrightnessOn
            });
        t.push({
            id: "lowpower",
            route: "battery",
            icon: "battery-low",
            label: qsTr("Saver"),
            on: SystemControlStore.isLowPowerMode
        });
        if (HapticManager.available)
            t.push({
                id: "vibration",
                route: "sound",
                icon: "vibrate",
                label: qsTr("Vibrate"),
                on: SystemControlStore.isVibrationOn
            });
        if (typeof TrackpadInput !== "undefined" && TrackpadInput.available)
            t.push({
                id: "trackpad",
                route: "trackpad",
                icon: "cursor",
                label: qsTr("Pointer"),
                on: SettingsManagerCpp.trackpadMode === "mouse"
            });
        // E-paper's own control, first and always there: the flashing
        // clear that takes the ghosts away (docs/design/EINK_MODE.md).
        const refresh = Display.refreshControls ? [
            {
                id: "refresh",
                route: "display",
                icon: "arrows-clockwise",
                label: qsTr("Refresh"),
                status: qsTr("Clear ghosting"),
                on: false
            }
        ] : [];
        return refresh.concat(enabledOnly(t));
    }
    // Switches in pages of three across by three. Paged by id: statuses change
    // every few seconds, and a page made of the tiles themselves would rebuild
    // every tile on it each time.
    readonly property int tileColumns: 3
    readonly property int tilesPerPage: 3 * tileColumns
    readonly property var tileIds: tiles.map(t => t.id)
    property var tilePages: []
    onTileIdsChanged: repage()
    Component.onCompleted: repage()
    function repage() {
        const ids = tileIds;
        if (JSON.stringify(ids) === JSON.stringify([].concat(...tilePages)))
            return;
        const pages = [];
        for (let i = 0; i < ids.length; i += tilesPerPage)
            pages.push(ids.slice(i, i + tilesPerPage));
        tilePages = pages;
    }
    function tileById(id) {
        return tiles.find(x => x.id === id) || null;
    }
    readonly property bool powerShown: SettingsManagerCpp.enabledQuickSettingsTiles.indexOf("power") >= 0

    // ── Shortcuts row: one-shot actions and apps ──────────────
    readonly property var shortcuts: [
        {
            id: "screenshot",
            icon: "camera-plus",
            label: qsTr("Screenshot")
        },
        {
            id: "app:camera",
            icon: "camera",
            label: qsTr("Camera")
        },
        {
            id: "app:clock",
            icon: "alarm",
            label: qsTr("Alarm")
        },
        {
            id: "app:notes",
            icon: "note-pencil",
            label: qsTr("Note")
        }
    ]

    // A one-shot action: a flat disc with its glyph, the name under it.
    component QSShortcut: Item {
        id: shortcut

        property string iconName
        property string label
        signal activated

        height: shortcutColumn.height
        Accessible.role: Accessible.Button
        Accessible.name: label
        Accessible.onPressAction: activated()

        Column {
            id: shortcutColumn

            width: parent.width
            spacing: Silica.Theme.paddingSmall

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Silica.Theme.itemSizeExtraSmall * 0.75
                height: width
                radius: width / 2
                color: shortcutMouse.pressed ? MColors.whiteOverlay16 : MColors.controlFill

                GlyphIcon {
                    anchors.centerIn: parent
                    name: shortcut.iconName
                    size: Silica.Theme.iconSizeSmall
                    color: Silica.Theme.primaryColor
                }
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
        clip: overflows
        contentHeight: content.y + content.height + Silica.Theme.paddingLarge
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: MMotion.flickDecelerationFast
        maximumFlickVelocity: MMotion.flickVelocity

        // Gated on the open height, not the animating one, so it does not
        // flip while the shade opens.
        readonly property bool overflows: quickSettings.maxHeight > 0 && contentHeight > quickSettings.maxHeight
        interactive: overflows && !MMotion.instant

        MEinkScroll {
            flickable: shadeScroll
            onBeyond: step => {
                if (step > 0)
                    UIStore.closeQuickSettings();
            }
        }

        // The shade is hidden, not destroyed: reopen at the top.
        onVisibleChanged: if (!visible) {
            contentY = 0;
            tilePager.positionViewAtBeginning();
        }

        // A tap off the controls dismisses. An item beneath them, not a
        // handler over them: a control that takes the press keeps the tap.
        MouseArea {
            objectName: "dismissTap"
            width: shadeScroll.width
            height: Math.max(shadeScroll.height, shadeScroll.contentHeight)
            onClicked: quickSettings.closed()
        }

        Column {
            id: content

            x: Silica.Theme.horizontalPageMargin
            y: Silica.Theme.paddingMedium
            width: shadeScroll.width - Silica.Theme.horizontalPageMargin * 2
            spacing: Silica.Theme.paddingMedium

            // Flattened only while it fades, so it fades as one piece; open,
            // a slider drag doesn't re-render an offscreen copy every frame.
            layer.enabled: opacity < 1

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
                    //: Qt date format pattern: keep the letters d, M, y; reorder or add separators only. Weekday, day and month for the quick settings date, e.g. Monday, 26 October
                    text: Qt.formatDate(SystemStatusStore.dateString ? new Date() : new Date(), qsTr("dddd, d MMMM"))
                    truncationMode: Silica.TruncationMode.Fade
                    color: Silica.Theme.secondaryHighlightColor
                    font.pixelSize: Silica.Theme.fontSizeSmall

                    Silica.Label {
                        objectName: "batteryLine"
                        anchors.left: parent.left
                        anchors.leftMargin: parent.contentWidth + Silica.Theme.paddingSmall
                        anchors.baseline: parent.baseline
                        //: Quick settings date line battery, e.g. "· 98% charging"
                        text: (SystemStatusStore.isCharging ? qsTr("· %1% charging") : qsTr("· %1%")).arg(SystemStatusStore.batteryLevel)
                        color: Silica.Theme.secondaryColor
                        font.pixelSize: Silica.Theme.fontSizeExtraSmall
                    }
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

            // ── Switches: pages swiped sideways, as on BB10 ──
            ListView {
                id: tilePager

                objectName: "tilePager"
                width: parent.width
                height: contentItem.childrenRect.height
                orientation: ListView.Horizontal
                snapMode: ListView.SnapOneItem
                highlightRangeMode: ListView.StrictlyEnforceRange
                boundsBehavior: Flickable.StopAtBounds
                // Every page stays built: few, and switches off-screen keep their state.
                cacheBuffer: Math.max(1, width) * quickSettings.tilePages.length
                // The neighbouring pages would show in the page margins.
                clip: true
                // The page count, not the pages: live statuses rebuild the
                // tiles every few seconds, and a new model would reset the page.
                model: quickSettings.tilePages.length

                delegate: Grid {
                    id: page

                    required property int index
                    width: tilePager.width
                    columns: quickSettings.tileColumns
                    spacing: Silica.Theme.paddingSmall

                    Repeater {
                        model: quickSettings.tilePages[page.index] || []
                        delegate: MQSTile {
                            required property var modelData
                            // Its live state, rebound in place as it changes.
                            readonly property var t: quickSettings.tileById(modelData) || ({})
                            width: (page.width - (page.columns - 1) * page.spacing) / page.columns
                            iconName: t.icon || ""
                            label: t.label || ""
                            status: t.status !== undefined ? t.status : t.id === "hotspot" && t.on ? SystemControlStore.hotspotSsid : quickSettings.onOff(t.on)
                            hasPage: t.route !== undefined
                            on: t.on === true
                            busy: SystemControlStore.pendingSwitches.indexOf(modelData) >= 0
                            onToggled: quickSettings.toggle(modelData)
                            onHeld: quickSettings.hold(modelData)
                            onOpened: quickSettings.openSettings(t.route)
                        }
                    }
                }
            }

            // Which page: a dot for each, the current one lit; a tap goes there.
            Row {
                objectName: "tilePageDots"
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Silica.Theme.paddingMedium
                visible: quickSettings.tilePages.length > 1

                Repeater {
                    model: quickSettings.tilePages.length
                    delegate: MouseArea {
                        id: dot

                        required property int index
                        width: Silica.Theme.paddingLarge
                        height: width
                        onClicked: tilePager.currentIndex = index

                        Rectangle {
                            anchors.centerIn: parent
                            width: Math.round(Silica.Theme.paddingSmall * 1.2)
                            height: width
                            radius: width / 2
                            color: dot.index === tilePager.currentIndex ? Silica.Theme.highlightColor : Silica.Theme.rgba(Silica.Theme.primaryColor, 0.3)
                        }
                    }
                }
            }

            Column {
                width: parent.width
                visible: quickSettings.hotspotDetailsShown && !SessionStore.isLocked

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
                spacing: Silica.Theme.paddingSmall

                MQSSlider {
                    objectName: "brightnessSlider"
                    width: parent.width
                    iconName: "sun"
                    a11yName: qsTr("Brightness")
                    value: SystemControlStore.brightness
                    onMoved: v => SystemControlStore.setBrightnessFromUser(v)
                }
                MQSSlider {
                    objectName: "warmthSlider"
                    visible: SystemControlStore.hasWarmLight && SystemControlStore.isNightLightOn
                    width: parent.width
                    iconName: "moon"
                    a11yName: qsTr("Warmth")
                    value: SystemControlStore.nightLightWarmth
                    onMoved: v => SystemControlStore.setNightLightWarmth(v)
                }
                MQSSlider {
                    objectName: "volumeSlider"
                    width: parent.width
                    iconName: "speaker-high"
                    a11yName: qsTr("Volume")
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
                    quickSettings.launchApp({
                        "id": active && MPRIS2Controller.desktopEntry ? MPRIS2Controller.desktopEntry : "music"
                    });
                }
                onPreviousClicked: {
                    MHaptics.light();
                    if (MPRIS2Controller.desktopEntry)
                        Tasks.wakeApp(MPRIS2Controller.desktopEntry);
                    MPRIS2Controller.previous();
                }
                onPlayPauseClicked: {
                    MHaptics.light();
                    if (MPRIS2Controller.desktopEntry)
                        Tasks.wakeApp(MPRIS2Controller.desktopEntry);
                    MPRIS2Controller.playPause();
                }
                onNextClicked: {
                    MHaptics.light();
                    if (MPRIS2Controller.desktopEntry)
                        Tasks.wakeApp(MPRIS2Controller.desktopEntry);
                    MPRIS2Controller.next();
                }
            }

            // ── Shortcuts, on the switch columns ─────────────────
            Row {
                objectName: "shortcutsRow"
                width: parent.width
                topPadding: Silica.Theme.paddingLarge

                Repeater {
                    model: quickSettings.shortcuts
                    delegate: QSShortcut {
                        required property var modelData
                        width: parent.width / quickSettings.shortcuts.length
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
        case "rotation":
            SystemControlStore.toggleRotationLock();
            break;
        case "nightlight":
            SystemControlStore.toggleNightLight();
            break;
        case "location":
            SystemControlStore.toggleLocation();
            break;
        case "hotspot":
            SystemControlStore.toggleHotspot();
            break;
        case "lowpower":
            SystemControlStore.toggleLowPowerMode();
            break;
        case "vibration":
            SystemControlStore.toggleVibration();
            break;
        case "trackpad":
            SettingsManagerCpp.trackpadMode = SettingsManagerCpp.trackpadMode === "mouse" ? "gesture" : "mouse";
            break;
        case "refresh":
            // The clear waits for a still screen, so the shade is gone from it.
            quickSettings.closed();
            Display.fullRefresh();
            break;
        case "settings":
            quickSettings.closed();
            quickSettings.launchApp({
                "id": "settings",
                "name": "Settings"
            });
            break;
        }
    }

    // Holding a tile opens its page in Settings.
    function openSettings(route) {
        quickSettings.closed();
        quickSettings.launchApp({
            "id": "settings",
            "name": "Settings",
            "route": route
        });
    }

    function hold(id) {
        // The hotspot's details show its password: not over the lock screen.
        if (id !== "hotspot" || SessionStore.isLocked)
            return;
        MHaptics.light();
        SystemControlStore.ensureHotspotCredentials();
        hotspotDetailsShown = !hotspotDetailsShown;
    }

    function doAction(id) {
        if (id.startsWith("app:")) {
            quickSettings.closed();
            quickSettings.launchApp({
                "id": id.slice(4)
            });
            return;
        }
        switch (id) {
        case "screenshot":
            // Captured once the shade has closed, so it isn't in the picture.
            quickSettings.captureWhenClosed = true;
            quickSettings.closed();
            break;
        case "power":
            quickSettings.closed();
            quickSettings.powerRequested();
            break;
        }
    }
}
