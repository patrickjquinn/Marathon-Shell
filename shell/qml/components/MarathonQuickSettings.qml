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
Rectangle {
    id: quickSettings

    signal closed
    signal launchApp(var app)

    // Container: glass over wallpaper.
    color: Qt.rgba(13 / 255, 13 / 255, 14 / 255, 0.95)
    border.width: 0

    // Tile state. Wired to SystemControlStore / SystemStatusStore.
    readonly property var tiles: [
        {
            id: "wifi",
            icon: "wifi",
            label: "Wi-Fi",
            on: SystemStatusStore.isWifiOn,
            sub: SystemStatusStore.wifiNetwork || "Off"
        },
        {
            id: "bluetooth",
            icon: "bluetooth",
            label: "Bluetooth",
            on: SystemStatusStore.isBluetoothOn,
            sub: SystemStatusStore.isBluetoothOn ? "On" : "Off"
        },
        {
            id: "cellular",
            icon: "signal-high",
            label: "Mobile data",
            on: !SystemStatusStore.isAirplaneMode,
            sub: ModemManagerCpp.operatorName || "Off"
        },
        {
            id: "airplane",
            icon: "plane",
            label: "Flight mode",
            on: SystemStatusStore.isAirplaneMode,
            sub: SystemStatusStore.isAirplaneMode ? "On" : "Off"
        },
        {
            id: "dnd",
            icon: "bell-off",
            label: "Do Not Disturb",
            on: SystemStatusStore.isDndMode,
            sub: SystemStatusStore.isDndMode ? "On" : "Off"
        },
        {
            id: "torch",
            icon: "flashlight",
            label: "Torch",
            on: FlashlightManagerCpp.on,
            sub: FlashlightManagerCpp.on ? "On" : "Off"
        },
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

            Rectangle {
                width: 18
                height: 18
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
                    color: "#000000"
                    font.family: MTypography.fontFamily
                    font.pixelSize: 12
                    font.weight: MTypography.weightBlack
                }
            }
            Text {
                text: "MARATHON"
                color: MColors.textSecondary
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeCaption
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
            Text {
                text: SystemStatusStore.dateString + " · " + SystemStatusStore.timeString
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
        Rectangle {
            width: parent.width
            height: brightness.height + volume.height + slidersDivider.height + 24
            radius: MRadius.md
            color: MColors.bb10Elevated
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
                value: SettingsManagerCpp.userBrightness !== undefined ? SettingsManagerCpp.userBrightness : 62
                onMoved: function (v) {
                    if (SettingsManagerCpp.userBrightness !== undefined) {
                        SettingsManagerCpp.userBrightness = v;
                    }
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
                value: SystemControlStore.volume !== undefined ? SystemControlStore.volume : 40
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

        // ── Page indicator (single page for now) ─────────────
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6
            Rectangle {
                width: 18
                height: 4
                radius: 2
                color: MColors.marathonTealBright
                anchors.verticalCenter: parent.verticalCenter
            }
            Repeater {
                model: 2
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
            label: MPRIS2Controller.title || ""
            sublabel: MPRIS2Controller.artist || ""
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
            SystemControlStore.setWifi(!SystemStatusStore.isWifiOn);
            break;
        case "bluetooth":
            SystemControlStore.setBluetooth(!SystemStatusStore.isBluetoothOn);
            break;
        case "airplane":
            SystemControlStore.setAirplaneMode(!SystemStatusStore.isAirplaneMode);
            break;
        case "dnd":
            SystemControlStore.setDndMode(!SystemStatusStore.isDndMode);
            break;
        case "torch":
            FlashlightManagerCpp.toggle();
            break;
        case "cellular":  /* TODO: data toggle via ModemManager */
            break;
        }
    }
}
