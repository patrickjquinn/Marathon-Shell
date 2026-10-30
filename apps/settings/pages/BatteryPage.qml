pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../SettingsLogic.js" as Logic

Page {
    id: page

    readonly property var profiles: [
        {
            value: "performance",
            title: qsTr("Performance"),
            description: qsTr("Fastest, uses more battery")
        },
        {
            value: "balanced",
            title: qsTr("Balanced"),
            description: qsTr("Balances speed and battery life")
        },
        {
            value: "power-saver",
            title: qsTr("Power saver"),
            description: qsTr("Slower, makes the battery last longer")
        }
    ]
    readonly property bool hasBatteryLevel: Power.batteryLevel >= 0

    function setProfile(value) {
        if (value === "power-saver") {
            Power.setPowerSaveMode(true);
            return;
        }
        if (Power.isPowerSaveMode)
            Power.setPowerSaveMode(false);
        Power.setPowerProfile(value);
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("Battery")
            }
            Label {
                objectName: "levelLabel"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: page.hasBatteryLevel ? qsTr("%1%").arg(Power.batteryLevel) : qsTr("Battery level unavailable")
                font.pixelSize: page.hasBatteryLevel ? Theme.fontSizeHuge : Theme.fontSizeLarge
                color: page.hasBatteryLevel ? Theme.highlightColor : Theme.secondaryHighlightColor
            }
            Label {
                width: parent.width
                visible: page.hasBatteryLevel
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("Estimated remaining charge")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeSmall
            }
            Label {
                objectName: "statusLabel"
                width: parent.width
                visible: page.hasBatteryLevel || Power.isCharging || Power.isPluggedIn
                horizontalAlignment: Text.AlignHCenter
                text: Logic.batteryStatus(Power.isCharging, Power.isPluggedIn, Power.estimatedBatteryTime)
                color: Theme.secondaryHighlightColor
            }
            Item {
                width: 1
                height: Theme.paddingLarge
            }
            // Power saver is the power-saver profile plus the top menu's Battery saver tile state.
            ComboBox {
                objectName: "profileCombo"
                width: parent.width
                visible: Power.powerProfilesSupported
                label: qsTr("Power profile")
                description: currentIndex >= 0 ? page.profiles[currentIndex].description : ""
                Binding on currentIndex {
                    value: page.profiles.findIndex(p => p.value === (Power.isPowerSaveMode ? "power-saver" : Power.powerProfile))
                }
                menu: ContextMenu {
                    Repeater {
                        model: page.profiles

                        MenuItem {
                            required property var modelData

                            text: modelData.title
                            onClicked: page.setProfile(modelData.value)
                        }
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
