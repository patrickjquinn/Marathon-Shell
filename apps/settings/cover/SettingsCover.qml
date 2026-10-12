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
        property alias text: label.text

        width: parent.width
        spacing: Theme.paddingMedium

        Icon {
            id: icon

            anchors.verticalCenter: parent.verticalCenter
            width: Theme.iconSizeSmall
            height: Theme.iconSizeSmall
        }
        Label {
            id: label

            width: line.width - icon.width - line.spacing
            anchors.verticalCenter: parent.verticalCenter
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeMedium
        }
    }

    Column {
        x: Theme.paddingLarge
        y: Theme.paddingLarge
        width: parent.width - 2 * Theme.paddingLarge
        spacing: Theme.paddingMedium

        StateLine {
            objectName: "coverWifi"
            icon: Network.wifiEnabled ? "image://theme/icon-s-wlan" : "image://theme/icon-s-wlan-off"
            text: Logic.wifiSummary(Network.wifiEnabled, Network.wifiConnected, Network.wifiSsid)
        }
        StateLine {
            objectName: "coverBluetooth"
            icon: "image://theme/icon-s-bluetooth"
            text: Logic.bluetoothSummary(Bluetooth.enabled, Bluetooth.pairedDevices)
        }
        StateLine {
            objectName: "coverBattery"
            icon: "image://theme/icon-s-battery"
            text: Logic.batterySummary(Power.batteryLevel, Power.isCharging)
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
