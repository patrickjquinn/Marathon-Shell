pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../SettingsLogic.js" as Logic

CoverBackground {
    id: cover

    signal wifiToggled
    signal bluetoothToggled

    component StateLine: Row {
        id: line

        property alias icon: icon.source
        property alias name: nameLabel.text
        property alias text: stateLabel.text
        property bool on

        width: (lines.width - (lines.columns - 1) * lines.columnSpacing) / lines.columns
        spacing: Theme.paddingMedium

        Icon {
            id: icon

            anchors.verticalCenter: parent.verticalCenter
            width: Theme.iconSizeSmall
            height: Theme.iconSizeSmall
            color: line.on ? Theme.highlightColor : Theme.secondaryColor
        }
        Column {
            width: line.width - icon.width - line.spacing
            anchors.verticalCenter: parent.verticalCenter

            Label {
                id: nameLabel

                width: parent.width
                truncationMode: TruncationMode.Fade
                font.pixelSize: Theme.fontSizeSmall
            }
            Label {
                id: stateLabel

                width: parent.width
                truncationMode: TruncationMode.Fade
                font.pixelSize: Theme.fontSizeExtraSmall
                color: line.on ? Theme.highlightColor : Theme.secondaryColor
            }
        }
    }

    // Side by side on a wide cover, where three rows would run into the actions.
    Grid {
        id: lines

        x: Theme.paddingLarge
        y: Theme.paddingLarge
        width: parent.width - 2 * Theme.paddingLarge
        columns: cover.width > cover.height ? 2 : 1
        columnSpacing: Theme.paddingMedium
        rowSpacing: Theme.paddingLarge

        StateLine {
            objectName: "coverWifi"
            icon: Network.wifiEnabled ? "image://theme/icon-s-wlan" : "image://theme/icon-s-wlan-off"
            name: qsTr("Wi-Fi")
            text: Logic.wifiSummary(Network.wifiEnabled, Network.wifiConnected, Network.wifiSsid)
            on: Network.wifiEnabled
        }
        StateLine {
            objectName: "coverBluetooth"
            icon: "image://theme/icon-s-bluetooth"
            name: qsTr("Bluetooth")
            text: Logic.bluetoothSummary(Bluetooth.enabled, Bluetooth.pairedDevices)
            on: Bluetooth.enabled
        }
        StateLine {
            objectName: "coverBattery"
            icon: "image://theme/icon-s-battery"
            name: qsTr("Battery")
            text: Logic.batterySummary(Power.batteryLevel, Power.isCharging)
            on: Power.isCharging
        }
    }

    CoverActionList {
        CoverAction {
            objectName: "wifiAction"
            iconSource: Network.wifiEnabled ? "image://theme/icon-cover-wlan-off" : "image://theme/icon-cover-wlan"
            onTriggered: cover.wifiToggled()
        }
        CoverAction {
            objectName: "bluetoothAction"
            iconSource: "image://theme/icon-cover-bluetooth"
            onTriggered: cover.bluetoothToggled()
        }
    }
}
