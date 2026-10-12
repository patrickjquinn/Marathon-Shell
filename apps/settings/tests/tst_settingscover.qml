import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import "../cover"

TestCase {
    id: testCase

    name: "SettingsCover"
    when: windowShown
    width: 270
    height: 480

    Component {
        id: coverComponent

        SettingsCover {
            width: 270
            height: 480
        }
    }

    function init() {
        Network.reset();
        Bluetooth.reset();
        Power.reset();
    }

    function test_showsState() {
        const cover = createTemporaryObject(coverComponent, testCase);
        compare(findChild(cover, "coverWifi").text, "On");
        compare(findChild(cover, "coverBluetooth").text, "Off");
        compare(findChild(cover, "coverBattery").text, "80%");
        Network.wifiConnected = true;
        Network.wifiSsid = "Cafe";
        Bluetooth.enabled = true;
        Power.batteryLevel = 12;
        compare(findChild(cover, "coverWifi").text, "Cafe");
        compare(findChild(cover, "coverBluetooth").text, "On");
        compare(findChild(cover, "coverBattery").text, "12%");
    }

    function test_actions() {
        const cover = createTemporaryObject(coverComponent, testCase);
        const wifi = signalSpy.createObject(testCase, { target: cover, signalName: "wifiToggled" });
        const bt = signalSpy.createObject(testCase, { target: cover, signalName: "bluetoothToggled" });
        compare(findChild(cover, "wifiAction").iconSource, "image://theme/icon-cover-wlan-off");
        findChild(cover, "wifiAction").triggered();
        findChild(cover, "bluetoothAction").triggered();
        compare(wifi.count, 1);
        compare(bt.count, 1);
        Network.wifiEnabled = false;
        compare(findChild(cover, "wifiAction").iconSource, "image://theme/icon-cover-wlan");
    }

    Component {
        id: signalSpy

        SignalSpy {}
    }
}
