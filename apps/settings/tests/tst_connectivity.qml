import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import MarathonApp.Settings
import ".."

TestCase {
    id: testCase

    name: "Connectivity"
    when: windowShown
    visible: true
    width: 540
    height: 1140

    Component {
        id: appComponent

        SettingsApp {
            width: 540
            height: 1140
        }
    }

    function init() {
        Network.reset();
        Bluetooth.reset();
        SettingsController.reset();
    }

    function open(name) {
        const app = createTemporaryObject(appComponent, testCase);
        tryVerify(() => app.pageStack.currentPage !== null);
        verify(app.openPage(name, PageStackAction.Immediate));
        const page = app.pageStack.currentPage;
        tryCompare(page, "status", PageStatus.Active);
        return { app: app, page: page };
    }

    function child(parent, name) {
        let item = null;
        tryVerify(() => (item = findChild(parent, name)) !== null, 3000, name);
        return item;
    }

    function activeDialog(app) {
        tryVerify(() => app.pageStack.currentPage.hasOwnProperty("canAccept"), 3000);
        const dialog = app.pageStack.currentPage;
        tryCompare(dialog, "status", PageStatus.Active);
        return dialog;
    }

    function test_wifiScansAndToggles() {
        const s = open("wifi");
        compare(Network.calls[0], ["scanWifi"]);
        verify(s.page.scanning);
        Network.availableNetworks = [];
        verify(!s.page.scanning);
        verify(child(s.page, "noNetworks").visible);
        child(s.page, "scanItem").clicked();
        compare(Network.calls[Network.calls.length - 1], ["scanWifi"]);
        child(s.page, "wifiSwitch").clicked(null);
        verify(!Network.wifiEnabled);
        verify(!child(s.page, "noNetworks").visible);
        compare(child(s.page, "networks").count, 0);
    }

    function test_wifiWithoutAdapter() {
        Network.wifiAvailable = false;
        const s = open("wifi");
        compare(Network.calls.length, 0);
        verify(child(s.page, "noAdapter").visible);
        verify(!child(s.page, "wifiSwitch").enabled);
        verify(!child(s.page, "wifiSwitch").checked);
        verify(!child(s.page, "noNetworks").visible);
        verify(!child(s.page, "availableHeader").visible);
    }

    function test_wifiListsNetworksAndCurrent() {
        Network.availableNetworks = [{ ssid: "Home", strength: 80, security: "WPA2", secured: true }, { ssid: "Cafe", strength: 30, security: "", secured: false }];
        Network.wifiConnected = true;
        Network.wifiSsid = "Home";
        Network.wifiSignalStrength = 80;
        const s = open("wifi");
        verify(child(s.page, "currentNetwork").visible);
        compare(child(s.page, "networks").count, 1);
        verify(child(s.page, "network-Cafe") !== null);
        child(s.page, "disconnectItem").clicked();
        verify(!Network.wifiConnected);
        compare(child(s.page, "networks").count, 2);
    }

    function test_wifiPasswordDialog() {
        Network.availableNetworks = [{ ssid: "Home", strength: 80, security: "WPA2", secured: true }];
        const s = open("wifi");
        child(s.page, "network-Home").clicked(null);
        const dialog = activeDialog(s.app);
        verify(dialog.secured);
        dialog.password = "short";
        verify(!dialog.canAccept);
        dialog.password = "longenough";
        verify(dialog.canAccept);
        dialog.accept();
        tryCompare(s.app.pageStack, "currentPage", s.page);
        compare(SettingsController.calls, [["wifiPassword", "Home", "longenough"]]);
        verify(child(s.page, "connectingLabel").visible);

        SettingsController.wifiFailed("Wrong password");
        const retry = activeDialog(s.app);
        compare(child(retry, "errorLabel").text, "Wrong password");
        retry.reject();
        tryCompare(s.app.pageStack, "currentPage", s.page);
        verify(!SettingsController.wifiDialogVisible);
    }

    function test_openNetworkNeedsNoPassword() {
        Network.availableNetworks = [{ ssid: "Cafe", strength: 30, security: "", secured: false }];
        const s = open("wifi");
        child(s.page, "network-Cafe").clicked(null);
        const dialog = activeDialog(s.app);
        verify(!dialog.secured);
        verify(dialog.canAccept);
        verify(!child(dialog, "passwordField").visible);
        dialog.accept();
        tryCompare(s.app.pageStack, "currentPage", s.page);
        compare(SettingsController.calls, [["wifiPassword", "Cafe", ""]]);
        SettingsController.wifiSucceeded();
        verify(!child(s.page, "connectingLabel").visible);
        verify(s.app.pageStack.currentPage === s.page);
    }

    function test_bluetoothToggleAndConnect() {
        const s = open("bluetooth");
        compare(child(s.page, "pairedDevices").count, 0);
        child(s.page, "bluetoothSwitch").clicked(null);
        verify(Bluetooth.enabled);
        Bluetooth.pairedDevices = [{ name: "Buds", address: "AA", connected: true, paired: true }, { name: "Keys", address: "BB", connected: false, paired: true }];
        compare(child(s.page, "pairedDevices").count, 2);
        verify(Bluetooth.scanning);
        Bluetooth.calls = [];
        child(s.page, "paired-AA").clicked(null);
        child(s.page, "paired-BB").clicked(null);
        compare(Bluetooth.calls, [["disconnect", "AA"], ["connect", "BB"]]);
        verify(child(s.page, "noDevices").visible);
        child(s.page, "scanItem").clicked();
        verify(!Bluetooth.scanning);
        child(s.page, "scanItem").clicked();
        verify(Bluetooth.scanning);
    }

    function test_bluetoothScansWhileOpen() {
        Bluetooth.enabled = true;
        const s = open("bluetooth");
        tryVerify(() => Bluetooth.scanning);
        s.app.pageStack.pop(null, PageStackAction.Immediate);
        tryVerify(() => !Bluetooth.scanning);
    }

    function test_bluetoothRemovePaired() {
        Bluetooth.enabled = true;
        Bluetooth.pairedDevices = [{ name: "Buds", address: "AA", connected: false, paired: true }];
        const s = open("bluetooth");
        const menu = child(s.page, "paired-AA").openMenu();
        tryVerify(() => menu._open && menu.height > 0);
        wait(300);
        mouseClick(findChild(menu, "removeItem"));
        verify(!Bluetooth.calls.some(c => c[0] === "unpair"));
        tryVerify(() => Bluetooth.calls.some(c => c[0] === "unpair" && c[1] === "AA"), 10000);
        compare(child(s.page, "pairedDevices").count, 0);
    }

    function test_bluetoothPairJustWorks() {
        Bluetooth.enabled = true;
        Bluetooth.devices = [{ name: "Speaker", address: "CC", paired: false, rssi: -60 }, { name: "Buds", address: "AA", paired: true }];
        const s = open("bluetooth");
        compare(child(s.page, "availableDevices").count, 1);
        child(s.page, "device-CC").clicked(null);
        const dialog = activeDialog(s.app);
        compare(dialog.mode, "justworks");
        verify(dialog.canAccept);
        dialog.accept();
        tryCompare(s.app.pageStack, "currentPage", s.page);
        compare(SettingsController.calls, [["pin", "CC", ""]]);
        verify(child(s.page, "pairingLabel").visible);
        SettingsController.bluetoothSucceeded();
        verify(!child(s.page, "pairingLabel").visible);
    }

    function test_bluetoothPinRequestAndFailure() {
        Bluetooth.enabled = true;
        const s = open("bluetooth");
        SettingsController.showBluetoothDialog("Car", "DD", "device", "pin");
        const dialog = activeDialog(s.app);
        verify(child(dialog, "pinField").visible);
        verify(!dialog.canAccept);
        dialog.pin = "1234";
        verify(dialog.canAccept);
        dialog.accept();
        tryCompare(s.app.pageStack, "currentPage", s.page);
        compare(SettingsController.calls, [["pin", "DD", "1234"]]);
        SettingsController.bluetoothFailed("Authentication rejected");
        const retry = activeDialog(s.app);
        compare(child(retry, "errorLabel").text, "Authentication rejected");
        retry.reject();
        tryCompare(s.app.pageStack, "currentPage", s.page);
        compare(SettingsController.calls[1], ["cancel", "DD"]);
    }

    function test_bluetoothPasskeyAndConfirm() {
        Bluetooth.enabled = true;
        const s = open("bluetooth");
        SettingsController.showBluetoothDialog("Watch", "EE", "device", "passkey");
        const dialog = activeDialog(s.app);
        dialog.passkey = "12345";
        verify(!dialog.canAccept);
        dialog.passkey = "123456";
        dialog.accept();
        tryCompare(s.app.pageStack, "currentPage", s.page);
        compare(SettingsController.calls, [["passkey", "EE", "123456"]]);
        SettingsController.bluetoothSucceeded();

        SettingsController.showBluetoothPasskeyConfirmation("Phone", "FF", "phone", 424242);
        const confirm = activeDialog(s.app);
        compare(child(confirm, "passkeyLabel").text, "424242");
        confirm.reject();
        tryCompare(s.app.pageStack, "currentPage", s.page);
        compare(SettingsController.calls[1], ["confirm", "FF", false]);
        verify(!SettingsController.bluetoothDialogVisible);
    }

    function test_cellularUnavailable() {
        const s = open("cellular");
        const placeholder = child(s.page, "placeholder");
        verify(placeholder.enabled);
        compare(placeholder.text, "Mobile network settings aren't available yet");
        compare(findChild(s.page, "dataSwitch"), null);
    }
}
