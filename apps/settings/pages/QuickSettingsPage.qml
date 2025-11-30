import QtQuick
import QtQuick.Controls
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import "../components"

SettingsPageTemplate {
    id: quickSettingsPage
    pageTitle: "Quick Settings"

    property string pageName: "quicksettings"

    // navigateBack signal already provided by SettingsPageTemplate

    content: Flickable {
        contentHeight: quickSettingsContent.height + 40
        clip: true

        Column {
            id: quickSettingsContent
            width: parent.width
            spacing: MSpacing.xl
            leftPadding: 24
            rightPadding: 24
            topPadding: 24

            MSection {
                title: "Tile Customization"
                subtitle: "Tap to enable/disable tiles. Drag to reorder (coming soon)"
                width: parent.width - 48

                Column {
                    width: parent.width
                    spacing: 0

                    // Define all possible tiles with descriptions
                    Repeater {
                        model: [
                            {
                                id: "wifi",
                                label: "Wi-Fi",
                                icon: "wifi",
                                desc: "Toggle wireless network"
                            },
                            {
                                id: "bluetooth",
                                label: "Bluetooth",
                                icon: "bluetooth",
                                desc: "Connect to devices"
                            },
                            {
                                id: "flight",
                                label: "Flight Mode",
                                icon: "plane",
                                desc: "Disable all radios"
                            },
                            {
                                id: "cellular",
                                label: "Mobile Network",
                                icon: "signal",
                                desc: "Toggle cellular data"
                            },
                            {
                                id: "rotation",
                                label: "Rotation Lock",
                                icon: "rotate-ccw",
                                desc: "Lock screen orientation"
                            },
                            {
                                id: "autobrightness",
                                label: "Auto-brightness",
                                icon: "sun-moon",
                                desc: "Automatic brightness adjustment"
                            },
                            {
                                id: "location",
                                label: "Location",
                                icon: "map-pin",
                                desc: "GPS and location services"
                            },
                            {
                                id: "hotspot",
                                label: "Hotspot",
                                icon: "wifi-tethering",
                                desc: "Share internet connection"
                            },
                            {
                                id: "vibration",
                                label: "Vibration",
                                icon: "vibrate",
                                desc: "Haptic feedback"
                            },
                            {
                                id: "nightlight",
                                label: "Night Light",
                                icon: "moon",
                                desc: "Reduce blue light"
                            },
                            {
                                id: "torch",
                                label: "Torch",
                                icon: "flashlight",
                                desc: "Toggle flashlight"
                            },
                            {
                                id: "notifications",
                                label: "DND Mode",
                                icon: "bell",
                                desc: "Do Not Disturb"
                            },
                            {
                                id: "battery",
                                label: "Battery Saver",
                                icon: "battery",
                                desc: "Low power mode"
                            },
                            {
                                id: "screenshot",
                                label: "Screenshot",
                                icon: "camera",
                                desc: "Capture screen"
                            },
                            {
                                id: "settings",
                                label: "Settings",
                                icon: "settings",
                                desc: "Open Settings app"
                            },
                            {
                                id: "lock",
                                label: "Lock Device",
                                icon: "lock",
                                desc: "Lock the screen"
                            },
                            {
                                id: "power",
                                label: "Power Menu",
                                icon: "power",
                                desc: "Show power options"
                            }
                        ]

                        delegate: MSettingsListItem {
                            required property var modelData
                            title: modelData.label
                            subtitle: modelData.desc
                            showToggle: true
                            toggleValue: SettingsManagerCpp.enabledQuickSettingsTiles.indexOf(modelData.id) !== -1
                            onToggleChanged: value => {
                                var tiles = SettingsManagerCpp.enabledQuickSettingsTiles;
                                var idx = tiles.indexOf(modelData.id);

                                if (value && idx === -1) {
                                    // Enable tile
                                    tiles.push(modelData.id);
                                    SettingsManagerCpp.enabledQuickSettingsTiles = tiles;
                                    Logger.info("QuickSettings", "Enabled tile: " + modelData.id);
                                } else if (!value && idx !== -1) {
                                    // Disable tile
                                    tiles.splice(idx, 1);
                                    SettingsManagerCpp.enabledQuickSettingsTiles = tiles;
                                    Logger.info("QuickSettings", "Disabled tile: " + modelData.id);
                                }
                            }
                        }
                    }
                }
            }

            MSection {
                title: "Actions"
                width: parent.width - 48

                MSettingsListItem {
                    title: "Reset to Defaults"
                    subtitle: "Restore all tiles in default order"
                    iconName: "refresh-cw"
                    showChevron: false
                    onSettingClicked: {
                        var defaultTiles = ["wifi", "bluetooth", "flight", "cellular", "rotation", "autobrightness", "location", "hotspot", "vibration", "nightlight", "torch", "notifications", "battery", "screenshot", "settings", "lock"];
                        SettingsManagerCpp.enabledQuickSettingsTiles = defaultTiles;
                        SettingsManagerCpp.quickSettingsTileOrder = defaultTiles;
                        Logger.info("QuickSettings", "Reset to defaults");
                        HapticService.light();
                    }
                }
            }

            Item {
                height: Constants.navBarHeight
            }
        }
    }
}
