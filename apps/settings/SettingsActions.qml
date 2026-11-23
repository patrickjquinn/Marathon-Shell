import QtQuick
import Sailfish.Silica 1.0
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
    // Asked for before Settings' first page is on the stack; opened once it is.
    property string pendingPage

    function open(page) {
        if (app.pageStack.depth > 0)
            app.openPage(page, PageStackAction.Immediate, true);
        else
            pendingPage = page;
    }

    Connections {
        target: root.app.pageStack

        function onDepthChanged() {
            if (root.app.pageStack.depth === 0 || root.pendingPage === "")
                return;
            const page = root.pendingPage;
            root.pendingPage = "";
            root.app.openPage(page, PageStackAction.Immediate, true);
        }
    }

    KeelAction {
        name: "settings.status"
        title: qsTr("Phone status")
        description: "What the phone's Settings show at a glance: whether Wi-Fi is on and the network it is joined to, airplane mode, whether Bluetooth is on and the device connected, and the battery's charge (0 to 100, absent without a battery) and whether it is charging."
        readOnly: true
        idempotent: true
        returns: KeelResult {
            type: "object"
            KeelParam {
                name: "wifiEnabled"
                type: "boolean"
                required: true
            }
            KeelParam {
                name: "wifiNetwork"
                type: "string"
                maxLength: 64
                required: true
                description: "Empty when not connected"
            }
            KeelParam {
                name: "airplaneMode"
                type: "boolean"
                required: true
            }
            KeelParam {
                name: "bluetoothEnabled"
                type: "boolean"
                required: true
            }
            KeelParam {
                name: "bluetoothDevice"
                type: "string"
                maxLength: 248
                required: true
                description: "Empty when none is connected"
            }
            KeelParam {
                name: "batteryLevel"
                type: "integer"
                minimum: 0
                maximum: 100
            }
            KeelParam {
                name: "charging"
                type: "boolean"
                required: true
            }
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
            KeelParam {
                name: "enabled"
                type: "boolean"
                required: true
            }
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
            KeelParam {
                name: "enabled"
                type: "boolean"
                required: true
            }
        ]
        onInvoked: (args, call) => {
            if (Bluetooth.enabled !== args.enabled)
                root.app.toggleBluetooth();
        }
    }

    KeelPage {
        name: "wifi"
        title: qsTr("Wi-Fi")
        description: "Networks nearby, joining one, hidden networks, and each network's password, auto-join, Low Data Mode, private address, IP and DNS."
        onShow: root.open(name)
    }
    KeelPage {
        name: "savednetworks"
        title: qsTr("Saved networks")
        description: "The Wi-Fi networks the phone remembers, to open or forget one."
        onShow: root.open(name)
    }
    KeelPage {
        name: "bluetooth"
        title: qsTr("Bluetooth")
        description: "Turning Bluetooth on or off, pairing, connecting and removing devices."
        onShow: root.open(name)
    }
    KeelPage {
        name: "cellular"
        title: qsTr("Mobile network")
        description: "Mobile data, data roaming, network mode, the operator and signal."
        onShow: root.open(name)
    }
    KeelPage {
        name: "apn"
        title: qsTr("Access point (APN)")
        description: "The mobile data access point: the carrier's own or one you enter."
        onShow: root.open(name)
    }
    KeelPage {
        name: "mms"
        title: qsTr("MMS")
        description: "Downloading picture and group messages automatically, and the carrier's MMS settings."
        onShow: root.open(name)
    }
    KeelPage {
        name: "display"
        title: qsTr("Display")
        description: "Brightness, automatic brightness, night light, nightshade, screen timeout, auto-rotate, interface size and reduce motion."
        onShow: root.open(name)
    }
    KeelPage {
        name: "ambience"
        title: qsTr("Ambience")
        description: "Wallpaper and theme."
        onShow: root.open(name)
    }
    KeelPage {
        name: "sound"
        title: qsTr("Sounds")
        description: "Media volume and mute, ringtone, notification and alarm sounds and volumes, vibration and each app's volume."
        onShow: root.open(name)
    }
    KeelPage {
        name: "notifications"
        title: qsTr("Notifications")
        description: "Do not disturb, notifications on the lock screen, the notification sound and each app's notifications."
        onShow: root.open(name)
    }
    KeelPage {
        name: "quicksettings"
        title: qsTr("Quick settings")
        description: "Which tiles the top menu shows, and resetting them."
        onShow: root.open(name)
    }
    KeelPage {
        name: "datetime"
        title: qsTr("Date and time")
        description: "Automatic time, the time and date, 24-hour clock, units, and automatic time zone."
        onShow: root.open(name)
    }
    KeelPage {
        name: "timezone"
        title: qsTr("Time zone")
        description: "Choosing the time zone by city."
        onShow: root.open(name)
    }
    KeelPage {
        name: "battery"
        title: qsTr("Battery")
        description: "Charge, time left, the power profile (performance, balanced, power saver) and battery history."
        onShow: root.open(name)
    }
    KeelPage {
        name: "storage"
        title: qsTr("Storage")
        description: "How much is used and how much is free."
        onShow: root.open(name)
    }
    KeelPage {
        name: "keyboard"
        title: qsTr("Keyboard")
        description: "Languages, auto-correct, auto-capitalize, word predictions, vibrate on key press and speed keys."
        onShow: root.open(name)
    }
    KeelPage {
        name: "speedkeys"
        title: qsTr("Speed keys")
        description: "The app each letter opens when held on the home screen."
        onShow: root.open(name)
    }
    KeelPage {
        name: "assistkey"
        title: qsTr("Assistant key")
        description: "What pressing and holding the key between the volume keys does."
        onShow: root.open(name)
    }
    KeelPage {
        name: "trackpad"
        title: qsTr("Trackpad")
        description: "Whether the keyboard's trackpad scrolls and navigates or moves a pointer."
        onShow: root.open(name)
    }
    KeelPage {
        name: "security"
        title: qsTr("Security")
        description: "The device lock, quick PIN, fingerprint, trackpad unlock, lock delay and data encryption."
        onShow: root.open(name)
    }
    KeelPage {
        name: "permissions"
        title: qsTr("App permissions")
        description: "What each app may use: camera, microphone, location, contacts and more, and the in-use indicator."
        onShow: root.open(name)
    }
    KeelPage {
        name: "accounts"
        title: qsTr("Accounts")
        description: "CardDAV and CalDAV accounts that sync contacts and calendars: adding, syncing and removing."
        onShow: root.open(name)
    }
    KeelPage {
        name: "appmanager"
        title: qsTr("Installed apps")
        description: "Each installed app's details: version, notifications, permissions, uninstalling, disabling and force stop."
        onShow: root.open(name)
    }
    KeelPage {
        name: "android"
        title: qsTr("Android apps")
        description: "Whether Android is running, starting it at login, Google services (microG), push messages and resetting it."
        onShow: root.open(name)
    }
    KeelPage {
        name: "androidapps"
        title: qsTr("Android apps list")
        description: "Each Android app's permissions, notifications, battery use and storage."
        onShow: root.open(name)
    }
    KeelPage {
        name: "androidaccess"
        title: qsTr("Special access")
        description: "What Android apps may do beyond their permissions: all files, installing apps, alarms and more."
        onShow: root.open(name)
    }
    KeelPage {
        name: "hiddenapps"
        title: qsTr("Hidden apps")
        description: "Which apps are hidden from the app grid."
        onShow: root.open(name)
    }
    KeelPage {
        name: "appsort"
        title: qsTr("App grid")
        description: "Columns on the app grid, hiding desktop apps, searching native apps and notification badges."
        onShow: root.open(name)
    }
    KeelPage {
        name: "themedapps"
        title: qsTr("Themed apps")
        description: "Whether GNOME, KDE, Android and Flatpak apps take the ambience's accent and colours."
        onShow: root.open(name)
    }
    KeelPage {
        name: "store"
        title: qsTr("App Store")
        description: "Phone-only apps, the Flathub and F-Droid sources, anti-features, and automatic app updates."
        onShow: root.open(name)
    }
    KeelPage {
        name: "updates"
        title: qsTr("Software updates")
        description: "Checking for and installing system updates, automatic updates and developer updates."
        onShow: root.open(name)
    }
    KeelPage {
        name: "about"
        title: qsTr("About device")
        description: "Device name, model, software version, kernel, hardware and legal notices."
        onShow: root.open(name)
    }
    KeelPage {
        name: "licenses"
        title: qsTr("Open source licenses")
        description: "The licenses of the open source components in this build."
        onShow: root.open(name)
    }
    KeelPage {
        name: "tos"
        title: qsTr("Terms of service")
        description: "Marathon OS's terms of service."
        onShow: root.open(name)
    }
    KeelPage {
        name: "privacy"
        title: qsTr("Privacy policy")
        description: "Marathon OS's privacy policy: what stays on the device."
        onShow: root.open(name)
    }
    KeelPage {
        name: "developer"
        title: qsTr("Developer tools")
        description: "Remote connection over SSH, its password, and sharing a bug report."
        onShow: root.open(name)
    }
    KeelPage {
        name: "erase"
        title: qsTr("Erase all content")
        description: "Erasing everything and starting again as new: a factory reset."
        onShow: root.open(name)
    }
}
