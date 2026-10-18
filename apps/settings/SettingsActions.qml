import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Keel.Actions 1.0
import Marathon.Platform 1.0
import "SettingsLogic.js" as Logic

// keel-actions.json is actions.json from Shipwright's
//   keel actions --qml SettingsActions.qml --app-id org.marathonos.settings \
//       --exec /usr/bin/marathon-app-runner --out <dir>
// regenerate it after changing a declaration.
Item {
    id: root

    // The app: openPage(), toggleWifi() and toggleBluetooth().
    property var app

    function open(page) {
        app.openPage(page, PageStackAction.Immediate, true);
    }

    KeelAction {
        name: "settings.status"
        title: qsTr("Phone status")
        description: "What the phone's Settings show at a glance: whether Wi-Fi is on and the network it is joined to, airplane mode, whether Bluetooth is on and the device connected, and the battery's charge (0 to 100, absent without a battery) and whether it is charging."
        readOnly: true
        idempotent: true
        returns: KeelResult {
            type: "object"
            KeelParam { name: "wifiEnabled"; type: "boolean"; required: true }
            KeelParam { name: "wifiNetwork"; type: "string"; maxLength: 64; required: true; description: "Empty when not connected" }
            KeelParam { name: "airplaneMode"; type: "boolean"; required: true }
            KeelParam { name: "bluetoothEnabled"; type: "boolean"; required: true }
            KeelParam { name: "bluetoothDevice"; type: "string"; maxLength: 248; required: true; description: "Empty when none is connected" }
            KeelParam { name: "batteryLevel"; type: "integer"; minimum: 0; maximum: 100 }
            KeelParam { name: "charging"; type: "boolean"; required: true }
        }
        onInvoked: (args, call) => {
            const device = Bluetooth.enabled ? (Bluetooth.pairedDevices || []).find(d => d && d.connected) : null;
            const status = {
                wifiEnabled: Network.wifiEnabled,
                wifiNetwork: Network.wifiConnected ? Network.wifiSsid.substring(0, 64) : "",
                airplaneMode: Network.airplaneModeEnabled,
                bluetoothEnabled: Bluetooth.enabled,
                bluetoothDevice: device ? Logic.deviceName(device).substring(0, 248) : "",
                charging: Power.isCharging
            };
            if (Power.batteryLevel >= 0)
                status.batteryLevel = Math.min(100, Power.batteryLevel);
            call.reply(status);
        }
    }

    KeelAction {
        name: "wifi.switch"
        title: qsTr("Turn Wi-Fi on or off")
        description: "Turn the phone's Wi-Fi on or off. Off, the phone leaves its network and has no Wi-Fi connection until it is turned back on."
        idempotent: true
        confirm: true
        parameters: [
            KeelParam { name: "enabled"; type: "boolean"; required: true }
        ]
        onInvoked: (args, call) => {
            if (!Network.wifiAvailable)
                call.fail("NotAvailable", "This phone has no Wi-Fi");
            else if (Network.wifiEnabled !== args.enabled)
                root.app.toggleWifi();
        }
    }

    KeelAction {
        name: "bluetooth.switch"
        title: qsTr("Turn Bluetooth on or off")
        description: "Turn the phone's Bluetooth on or off. Off, connected headphones, speakers and other devices disconnect."
        idempotent: true
        confirm: true
        parameters: [
            KeelParam { name: "enabled"; type: "boolean"; required: true }
        ]
        onInvoked: (args, call) => {
            if (Bluetooth.enabled !== args.enabled)
                root.app.toggleBluetooth();
        }
    }

    KeelPage { name: "wifi"; title: qsTr("Wi-Fi"); description: "Networks nearby, joining one and the saved ones."; onShow: root.open(name) }
    KeelPage { name: "bluetooth"; title: qsTr("Bluetooth"); description: "Pairing and connecting devices."; onShow: root.open(name) }
    KeelPage { name: "display"; title: qsTr("Display"); description: "Brightness, screen timeout, text size and rotation."; onShow: root.open(name) }
    KeelPage { name: "ambience"; title: qsTr("Ambience"); description: "Wallpaper and theme."; onShow: root.open(name) }
    KeelPage { name: "sound"; title: qsTr("Sounds"); description: "Volume, ringtone, alarm and notification sounds."; onShow: root.open(name) }
    KeelPage { name: "notifications"; title: qsTr("Notifications"); description: "On the lock screen and for each app."; onShow: root.open(name) }
    KeelPage { name: "datetime"; title: qsTr("Date and time"); description: "Time zone and the 12- or 24-hour clock."; onShow: root.open(name) }
    KeelPage { name: "battery"; title: qsTr("Battery"); description: "Charge, power saving and the power profile."; onShow: root.open(name) }
    KeelPage { name: "storage"; title: qsTr("Storage"); description: "How much is used and how much is free."; onShow: root.open(name) }
    KeelPage { name: "keyboard"; title: qsTr("Keyboard"); description: "Languages, autocorrect and predictions."; onShow: root.open(name) }
    KeelPage { name: "security"; title: qsTr("Security"); description: "The device lock and its quick PIN."; onShow: root.open(name) }
    KeelPage { name: "accounts"; title: qsTr("Accounts"); description: "The accounts that sync contacts and calendars."; onShow: root.open(name) }
    KeelPage { name: "appmanager"; title: qsTr("Installed apps"); description: "Each installed app's details."; onShow: root.open(name) }
    KeelPage { name: "updates"; title: qsTr("Software updates"); description: "Checking for and installing system updates."; onShow: root.open(name) }
    KeelPage { name: "about"; title: qsTr("About device"); description: "Device name, model, software version and legal notices."; onShow: root.open(name) }
}
