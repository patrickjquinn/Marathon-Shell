import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components"

TestCase {
    name: "OOBEWifi"
    when: windowShown

    Window {
        width: 540
        height: 1140
        visible: true

        MarathonOOBE {
            id: oobe

            anchors.fill: parent
        }
    }

    function cleanup() {
        SystemStatusStore.isWifiOn = false;
        Network.availableNetworks = [];
        Network.wifiConnected = false;
        Network.wifiSsid = "";
        oobe.currentPage = 0;
    }

    function network(ssid, strength) {
        return { ssid: ssid, strength: strength, secured: true, security: "WPA2/WPA3", connected: false };
    }

    // A pre-seeded network can connect after the scan the list came from.
    function test_marksTheNetworkAlreadyConnected() {
        SystemStatusStore.isWifiOn = true;
        Network.availableNetworks = [network("Cafe", 90), network("Home", 60)];
        Network.wifiConnected = true;
        Network.wifiSsid = "Home";
        oobe.currentPage = 2;
        let home = null;
        tryVerify(() => (home = findChild(oobe, "oobeNetwork-Home")) && home.visible);
        const cafe = findChild(oobe, "oobeNetwork-Cafe");
        verify(home.connected);
        verify(!home.enabled);
        verify(!cafe.connected);
        tryVerify(() => home.y < cafe.y);
        verify(findChild(home, "oobeNetworkStatus").visible);
        verify(!findChild(cafe, "oobeNetworkStatus").visible);

        const next = findChild(oobe, "oobeNext");
        verify(next.enabled);
        mouseClick(next);
        compare(oobe.currentPage, 3);
    }
}
