pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import MarathonApp.Settings

Page {
    id: page

    readonly property var profiles: [
        { value: "performance", title: qsTr("Performance"), description: qsTr("Fastest, uses more battery") },
        { value: "balanced", title: qsTr("Balanced"), description: qsTr("Balances speed and battery life") },
        { value: "power-saver", title: qsTr("Power saver"), description: qsTr("Slower, makes the battery last longer") }
    ]

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
                text: qsTr("%1%").arg(Power.batteryLevel)
                font.pixelSize: Theme.fontSizeHuge
                color: Theme.highlightColor
            }
            Label {
                objectName: "statusLabel"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: SettingsController.batteryStatusText(Power.isCharging, Power.isPluggedIn, Power.estimatedBatteryTime)
                color: Theme.secondaryHighlightColor
            }
            Item {
                width: 1
                height: Theme.paddingLarge
            }
            TextSwitch {
                objectName: "saverSwitch"
                text: qsTr("Power saver mode")
                description: qsTr("Reduces performance to save battery")
                automaticCheck: false
                checked: Power.isPowerSaveMode
                onClicked: Power.setPowerSaveMode(!checked)
            }
            ComboBox {
                objectName: "profileCombo"
                width: parent.width
                visible: Power.powerProfilesSupported
                label: qsTr("Power profile")
                description: currentIndex >= 0 ? page.profiles[currentIndex].description : ""
                Binding on currentIndex {
                    value: page.profiles.findIndex(p => p.value === Power.powerProfile)
                }
                menu: ContextMenu {
                    Repeater {
                        model: page.profiles

                        MenuItem {
                            required property var modelData

                            text: modelData.title
                            onClicked: Power.setPowerProfile(modelData.value)
                        }
                    }
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
