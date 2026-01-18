import MarathonUI.Controls
import MarathonUI.Core
import MarathonUI.Navigation
import MarathonUI.Theme
import MarathonOS.Shell 1.0
import QtQuick
import QtQuick.Controls

Rectangle {
    id: quickSettings

    readonly property int gridColumns: Constants.screenWidth < 800 ? 2 : (Constants.screenWidth < 1200 ? 3 : 4)
    readonly property real tileHeight: Constants.hubHeaderHeight
    readonly property real reservedHeight: 50 + 160 + Constants.spacingMedium * 4 + Constants.spacingLarge * 2 + 80
    readonly property real availableGridHeight: Math.max(tileHeight * 3, height - reservedHeight)
    readonly property int maxGridRows: Math.max(3, Math.min(5, Math.floor(availableGridHeight / (tileHeight + Constants.spacingSmall))))
    readonly property int tilesPerPage: gridColumns * maxGridRows
    readonly property real calculatedGridHeight: (tileHeight * maxGridRows) + (Constants.spacingSmall * (maxGridRows - 1))
    property string networkSubtitle: SystemStatusStore.ethernetConnected ? ((typeof NetworkManagerCpp !== "undefined" && NetworkManagerCpp) ? (NetworkManagerCpp.ethernetConnectionName || "Wired") : "Wired") : (SystemStatusStore.wifiNetwork || "Not connected")
    property string networkIcon: SystemStatusStore.ethernetConnected ? "plug-zap" : "wifi"
    property string networkLabel: SystemStatusStore.ethernetConnected ? "Ethernet" : "Wi-Fi"
    property string cellularSubtitle: (typeof ModemManagerCpp !== 'undefined' && ModemManagerCpp ? ModemManagerCpp.operatorName : "") || "No service"
    property string batterySubtitle: "Battery " + SystemStatusStore.batteryLevel + "%"
    property int updateTrigger: 0
    property var allTiles: [
        {
            "id": "settings",
            "icon": "settings",
            "label": "Settings",
            "active": false,
            "available": true,
            "trigger": updateTrigger
        },
        {
            "id": "lock",
            "icon": "lock",
            "label": "Lock device",
            "active": false,
            "available": true,
            "trigger": updateTrigger
        },
        {
            "id": "power",
            "icon": "power",
            "label": "Power menu",
            "active": false,
            "available": true,
            "trigger": updateTrigger
        },
        {
            "id": "rotation",
            "icon": "rotate-ccw",
            "label": "Rotation lock",
            "active": SystemControlStore.isRotationLocked,
            "available": true,
            "trigger": updateTrigger
        },
        {
            "id": "wifi",
            "icon": networkIcon,
            "label": networkLabel,
            "active": SystemControlStore.isWifiOn || SystemStatusStore.ethernetConnected,
            "available": true,
            "subtitle": networkSubtitle,
            "trigger": updateTrigger
        },
        {
            "id": "bluetooth",
            "icon": "bluetooth",
            "label": "Bluetooth",
            "active": SystemControlStore.isBluetoothOn,
            "available": (typeof BluetoothManagerCpp !== "undefined" && BluetoothManagerCpp ? BluetoothManagerCpp.available : false),
            "subtitle": SystemControlStore.isBluetoothOn ? (SystemStatusStore.bluetoothConnectedDevicesCount > 0 ? SystemStatusStore.bluetoothConnectedDevicesCount + " devices" : "On") : "Off",
            "trigger": updateTrigger
        },
        {
            "id": "flight",
            "icon": "plane",
            "label": "Flight mode",
            "active": SystemControlStore.isAirplaneModeOn,
            "available": true,
            "trigger": updateTrigger
        },
        {
            "id": "cellular",
            "icon": "signal-high",
            "label": "Mobile network",
            "active": SystemControlStore.isCellularOn,
            "available": (typeof ModemManagerCpp !== 'undefined' && ModemManagerCpp.modemAvailable),
            "subtitle": cellularSubtitle,
            "trigger": updateTrigger
        },
        {
            "id": "hotspot",
            "icon": "router",
            "label": "Hotspot",
            "active": SystemControlStore.isHotspotOn,
            "available": (typeof NetworkManagerCpp !== 'undefined' && NetworkManagerCpp.hotspotSupported),
            "trigger": updateTrigger
        },
        {
            "id": "vibration",
            "icon": "smartphone",
            "label": "Vibration",
            "active": SystemControlStore.isVibrationOn,
            "available": (typeof HapticManager !== 'undefined' && HapticManager.available),
            "trigger": updateTrigger
        },
        {
            "id": "nightlight",
            "icon": "moon",
            "label": "Night Light",
            "active": SystemControlStore.isNightLightOn,
            "available": (typeof DisplayManagerCpp !== 'undefined' && DisplayManagerCpp.available),
            "trigger": updateTrigger
        },
        {
            "id": "torch",
            "icon": "flashlight",
            "label": "Torch",
            "active": SystemControlStore.isFlashlightOn,
            "available": (typeof FlashlightManagerCpp !== "undefined" && FlashlightManagerCpp.available),
            "trigger": updateTrigger
        },
        {
            "id": "screenshot",
            "icon": "camera",
            "label": "Screenshot",
            "active": false,
            "available": true,
            "trigger": updateTrigger
        },
        {
            "id": "alarm",
            "icon": "clock",
            "label": "Alarm",
            "active": SystemControlStore.isAlarmOn,
            "available": true,
            "trigger": updateTrigger
        },
        {
            "id": "battery",
            "icon": "battery",
            "label": "Battery saving",
            "active": SystemControlStore.isLowPowerMode,
            "available": true,
            "trigger": updateTrigger
        },
        {
            "id": "monitor",
            "icon": "info",
            "label": "Device monitor",
            "active": false,
            "available": true,
            "subtitle": batterySubtitle,
            "trigger": updateTrigger
        }
    ]
    property var visibleTiles: {
        updateTrigger;
        var enabled = SettingsManagerCpp.enabledQuickSettingsTiles;
        var order = SettingsManagerCpp.quickSettingsTileOrder;
        var result = [];
        for (var i = 0; i < order.length; i++) {
            var tileId = order[i];
            if (enabled.indexOf(tileId) !== -1) {
                var tile = null;
                for (var j = 0; j < allTiles.length; j++) {
                    if (allTiles[j].id === tileId) {
                        tile = allTiles[j];
                        break;
                    }
                }
                if (tile)
                    result.push(tile);
            }
        }
        for (var k = 0; k < allTiles.length; k++) {
            if (order.indexOf(allTiles[k].id) === -1 && enabled.indexOf(allTiles[k].id) !== -1)
                result.push(allTiles[k]);
        }
        return result;
    }

    signal closed
    signal launchApp(var app)

    function handleToggleTap(toggleId) {
        Logger.info("QuickSettings", "Toggle tapped: " + toggleId);
        if (toggleId === "wifi") {
            SystemControlStore.toggleWifi();
        } else if (toggleId === "bluetooth") {
            SystemControlStore.toggleBluetooth();
        } else if (toggleId === "flight") {
            SystemControlStore.toggleAirplaneMode();
        } else if (toggleId === "rotation") {
            SystemControlStore.toggleRotationLock();
        } else if (toggleId === "torch") {
            SystemControlStore.toggleFlashlight();
        } else if (toggleId === "autobrightness") {
            SystemControlStore.toggleAutoBrightness();
        } else if (toggleId === "location") {
            SystemControlStore.toggleLocation();
        } else if (toggleId === "hotspot") {
            SystemControlStore.toggleHotspot();
        } else if (toggleId === "vibration") {
            SystemControlStore.toggleVibration();
        } else if (toggleId === "nightlight") {
            SystemControlStore.toggleNightLight();
        } else if (toggleId === "screenshot") {
            SystemControlStore.captureScreenshot();
            UIStore.closeQuickSettings();
        } else if (toggleId === "alarm") {
            SystemControlStore.toggleAlarm();
            UIStore.closeQuickSettings();
            Qt.callLater(function () {
                var app = {
                    "id": "clock",
                    "name": "Clock",
                    "icon": "qrc:/images/clock.svg",
                    "type": "marathon"
                };
                launchApp(app);
            });
        } else if (toggleId === "battery") {
            SystemControlStore.toggleLowPowerMode();
        } else if (toggleId === "settings") {
            UIStore.closeQuickSettings();
            Qt.callLater(function () {
                var app = {
                    "id": "settings",
                    "name": "Settings",
                    "icon": "settings",
                    "type": "marathon"
                };
                launchApp(app);
            });
        } else if (toggleId === "lock") {
            UIStore.closeQuickSettings();
            Qt.callLater(function () {
                SessionStore.lock();
            });
        } else if (toggleId === "power") {
            UIStore.closeQuickSettings();
            Qt.callLater(function () {
                shell.showPowerMenu();
            });
        } else if (toggleId === "cellular")
            SystemControlStore.toggleCellular();
        else if (toggleId === "notifications")
            SystemControlStore.toggleDndMode();
        else if (toggleId === "monitor")
            Logger.info("QuickSettings", "Device monitor - info only, no action");
    }

    function handleLongPress(toggleId) {
        Logger.info("QuickSettings", "Toggle long-pressed: " + toggleId);
        if (toggleId === "settings" || toggleId === "lock" || toggleId === "power" || toggleId === "monitor")
            return;

        var deepLinkMap = {
            "wifi": "marathon://settings/wifi",
            "bluetooth": "marathon://settings/bluetooth",
            "cellular": "marathon://settings/cellular",
            "flight": "marathon://settings/cellular",
            "rotation": "marathon://settings/display",
            "torch": "marathon://settings/display",
            "alarm": "marathon://settings/sound",
            "notifications": "marathon://settings/notifications",
            "battery": "marathon://settings/power",
            "settings": "marathon://settings"
        };
        var deepLink = deepLinkMap[toggleId];
        if (deepLink) {
            Logger.info("QuickSettings", "Navigating to deep link: " + deepLink);
            NavigationRouter.navigate(deepLink);
            UIStore.closeQuickSettings();
        }
    }

    color: MColors.background
    opacity: 0.98
    Component.onCompleted: {
        Logger.info("QuickSettings", "Grid layout: " + gridColumns + " cols × " + maxGridRows + " rows (screen: " + Constants.screenWidth + "px)");
        var enabled = SettingsManagerCpp.enabledQuickSettingsTiles || [];
        var knownCount = 0;
        var unknownCount = 0;
        var seen = {};
        for (var i = 0; i < enabled.length; i++) {
            var id = enabled[i];
            if (seen[id])
                continue;

            seen[id] = true;
            var isKnown = false;
            for (var j = 0; j < allTiles.length; j++) {
                if (allTiles[j].id === id) {
                    isKnown = true;
                    break;
                }
            }
            if (isKnown)
                knownCount++;
            else
                unknownCount++;
        }
        Logger.info("QuickSettings", "Enabled tiles: " + knownCount + " of " + allTiles.length + (unknownCount > 0 ? (" (" + unknownCount + " unknown in settings)") : ""));
    }

    Connections {
        function onIsWifiOnChanged() {
            updateTrigger++;
        }

        function onIsBluetoothOnChanged() {
            updateTrigger++;
        }

        function onIsAirplaneModeOnChanged() {
            updateTrigger++;
        }

        function onIsCellularOnChanged() {
            updateTrigger++;
        }

        target: SystemControlStore
    }

    Connections {
        function onWifiNetworkChanged() {
            updateTrigger++;
        }

        function onEthernetConnectedChanged() {
            updateTrigger++;
        }

        function onBatteryLevelChanged() {
            updateTrigger++;
        }

        target: SystemStatusStore
    }

    Connections {
        function onEthernetConnectionNameChanged() {
            updateTrigger++;
        }

        target: typeof NetworkManagerCpp !== "undefined" ? NetworkManagerCpp : null
    }

    Connections {
        function onEnabledQuickSettingsTilesChanged() {
            updateTrigger++;
        }

        function onQuickSettingsTileOrderChanged() {
            updateTrigger++;
        }

        target: SettingsManagerCpp
    }

    Item {
        anchors.fill: parent

        Item {
            id: contentContainer

            anchors.centerIn: parent
            width: Constants.screenWidth <= 1080 ? parent.width : Math.min(parent.width, 800)
            height: parent.height

            Flickable {
                id: scrollView

                anchors.fill: parent
                anchors.topMargin: MSpacing.lg
                anchors.leftMargin: MSpacing.md
                anchors.rightMargin: MSpacing.md
                anchors.bottomMargin: 80
                contentHeight: contentColumn.height
                clip: true
                flickDeceleration: 5000
                maximumFlickVelocity: 2500

                Column {
                    id: contentColumn

                    width: parent.width
                    spacing: MSpacing.md

                    MLabel {
                        text: SystemStatusStore.dateString
                        variant: "body"
                        anchors.left: parent.left
                    }

                    Column {
                        width: parent.width
                        spacing: MSpacing.md

                        SwipeView {
                            id: toggleSwipeView

                            width: parent.width
                            height: calculatedGridHeight
                            clip: true
                            interactive: count > 1

                            Repeater {
                                model: Math.ceil(visibleTiles.length / tilesPerPage)

                                Item {
                                    width: toggleSwipeView.width
                                    height: toggleSwipeView.height

                                    Grid {
                                        anchors.fill: parent
                                        columns: gridColumns
                                        columnSpacing: MSpacing.sm
                                        rowSpacing: MSpacing.sm

                                        Repeater {
                                            model: {
                                                var startIdx = index * tilesPerPage;
                                                var endIdx = Math.min(startIdx + tilesPerPage, visibleTiles.length);
                                                return visibleTiles.slice(startIdx, endIdx);
                                            }

                                            delegate: QuickSettingsTile {
                                                tileWidth: (toggleSwipeView.width - (MSpacing.sm * (gridColumns - 1))) / gridColumns
                                                toggleData: modelData
                                                onTapped: handleToggleTap(modelData.id)
                                                onLongPressed: handleLongPress(modelData.id)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        MPageIndicator {
                            count: toggleSwipeView.count
                            currentIndex: toggleSwipeView.currentIndex
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }

                    MediaPlaybackManager {
                        id: mediaPlayer

                        width: parent.width
                    }

                    Column {
                        width: parent.width
                        spacing: MSpacing.sm

                        MLabel {
                            text: "Brightness"
                            variant: "body"
                            font.weight: Font.Medium
                        }

                        MSlider {
                            id: brightnessSlider

                            width: parent.width
                            from: 0
                            to: 100
                            Component.onCompleted: value = SystemControlStore.brightness
                            onMoved: {
                                brightnessDebounce.restart();
                            }
                            onReleased: {
                                brightnessDebounce.stop();
                                SystemControlStore.setBrightness(brightnessSlider.value);
                            }

                            Timer {
                                id: brightnessDebounce

                                interval: 150
                                onTriggered: SystemControlStore.setBrightness(brightnessSlider.value)
                            }

                            Connections {
                                function onBrightnessChanged() {
                                    if (!brightnessSlider.pressed)
                                        brightnessSlider.value = SystemControlStore.brightness;
                                }

                                target: SystemControlStore
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: MSpacing.sm

                        MLabel {
                            text: "Volume"
                            variant: "body"
                            font.weight: Font.Medium
                        }

                        MSlider {
                            id: volumeSlider

                            width: parent.width
                            from: 0
                            to: 100
                            Component.onCompleted: value = SystemControlStore.volume
                            onMoved: {
                                volumeDebounce.restart();
                            }
                            onReleased: {
                                volumeDebounce.stop();
                                SystemControlStore.setVolume(volumeSlider.value);
                            }

                            Timer {
                                id: volumeDebounce

                                interval: 150
                                onTriggered: SystemControlStore.setVolume(volumeSlider.value)
                            }

                            Connections {
                                function onVolumeChanged() {
                                    if (!volumeSlider.pressed)
                                        volumeSlider.value = SystemControlStore.volume;
                                }

                                target: SystemControlStore
                            }
                        }
                    }

                    Item {
                        height: Constants.navBarHeight
                    }
                }
            }
        }
    }
}
