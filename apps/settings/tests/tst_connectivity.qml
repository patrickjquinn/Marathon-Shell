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
        Modem.reset();
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
        tryVerify(() => !Network.wifiEnabled);
        verify(!child(s.page, "noNetworks").visible);
        compare(child(s.page, "networks").count, 0);
    }

    function test_turningWifiOnScans() {
        Network.wifiEnabled = false;
        const s = open("wifi");
        compare(Network.calls.length, 0);
        child(s.page, "wifiSwitch").clicked(null);
        tryVerify(() => Network.wifiEnabled);
        compare(Network.calls[Network.calls.length - 1], ["scanWifi"]);
        verify(s.page.scanning);
        verify(!child(s.page, "noNetworks").visible);
    }

    function test_savedNetworkConnectsWithoutPassword() {
        Network.availableNetworks = [{ ssid: "Home", strength: 80, security: "WPA2", secured: true, known: true }];
        const s = open("wifi");
        child(s.page, "network-Home").clicked(null);
        compare(SettingsController.calls, [["wifiPassword", "Home", ""]]);
        verify(child(s.page, "connectingLabel").visible);
        verify(s.app.pageStack.currentPage === s.page);
        SettingsController.wifiFailed("Incorrect password");
        const dialog = activeDialog(s.app);
        compare(child(dialog, "errorLabel").text, "Incorrect password");
    }

    function test_retryKeepsThePassword() {
        Network.availableNetworks = [{ ssid: "Home", strength: 80, security: "WPA2", secured: true }];
        const s = open("wifi");
        child(s.page, "network-Home").clicked(null);
        const dialog = activeDialog(s.app);
        dialog.password = "hunter22x";
        dialog.accept();
        tryCompare(s.app.pageStack, "currentPage", s.page);
        SettingsController.wifiFailed("Incorrect password");
        const retry = activeDialog(s.app);
        compare(retry.password, "hunter22x");
    }

    function test_forgetSavedNetwork() {
        Network.availableNetworks = [{ ssid: "Home", strength: 80, security: "WPA2", secured: true, known: true }, { ssid: "Cafe", strength: 30, secured: false }];
        const s = open("wifi");
        verify(child(s.page, "network-Cafe").menu === null);
        const menu = child(s.page, "network-Home").openMenu();
        tryVerify(() => menu._open && menu.height > 0);
        wait(300);
        mouseClick(findChild(menu, "forgetItem"));
        verify(!Network.calls.some(c => c[0] === "forget"));
        tryVerify(() => Network.calls.some(c => c[0] === "forget" && c[1] === "Home"), 10000);
    }

    function test_hiddenNetwork() {
        const s = open("wifi");
        child(s.page, "addNetworkItem").clicked();
        const dialog = activeDialog(s.app);
        verify(!dialog.canAccept);
        dialog.ssid = "Secret";
        verify(!dialog.canAccept);
        dialog.password = "password1";
        verify(dialog.canAccept);
        dialog.accept();
        tryCompare(s.app.pageStack, "currentPage", s.page);
        compare(SettingsController.calls, [["hidden", "Secret", "wpa-psk", "password1"]]);
        verify(child(s.page, "connectingLabel").visible);
        SettingsController.wifiFailed("Incorrect password");
        const retry = activeDialog(s.app);
        compare(retry.ssid, "Secret");
        compare(retry.password, "password1");
        compare(child(retry, "errorLabel").text, "Incorrect password");
        retry.security = "none";
        verify(!child(retry, "passwordField").visible);
        verify(retry.canAccept);
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

    function test_cellular() {
        const s = open("cellular");
        verify(!child(s.page, "placeholder").enabled);
        const data = child(s.page, "dataSwitch");
        verify(!data.checked);
        data.clicked(null);
        verify(Modem.dataEnabled);
        child(s.page, "roamingSwitch").clicked(null);
        verify(Modem.dataRoamingAllowed);
        const mode = child(s.page, "modeCombo");
        compare(mode.currentIndex, 0);
        compare(mode.value, "4G, 3G and 2G");
        Modem.setAllowedModes(2);
        compare(mode.currentIndex, 2);
        compare(mode.value, "2G only");
        compare(child(s.page, "operatorItem").value, "Vodafone");
        compare(child(s.page, "networkItem").value, "LTE");
        compare(child(s.page, "signalItem").value, "Excellent");
        compare(child(s.page, "roamingItem").value, "Home network");
        Modem.registered = false;
        compare(child(s.page, "operatorItem").value, "No service");
        verify(!child(s.page, "signalItem").visible);
    }

    function test_cellularWithoutSimOrModem() {
        Modem.simPresent = false;
        const s = open("cellular");
        const placeholder = child(s.page, "placeholder");
        verify(placeholder.enabled);
        compare(placeholder.text, "No SIM card");
        verify(!child(s.page, "dataSwitch").visible);
        Modem.available = false;
        compare(placeholder.text, "No modem found");
    }
}
