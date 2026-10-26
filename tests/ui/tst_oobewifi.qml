import QtQuick
import QtQuick.Window
import QtTest
import MarathonOS.Shell
import "../../shell/qml/components/oobe"

TestCase {
    name: "OobeOnline"
    when: windowShown

    Window {
        width: 540
        height: 1140
        visible: true

        OobeOnline {
            id: beat

            anchors.fill: parent
        }
    }

    SignalSpy {
        id: doneSpy

        target: beat
        signalName: "done"
    }

    function init() {
        doneSpy.clear();
    }

    function cleanup() {
        SystemStatusStore.isWifiOn = false;
        Network.availableNetworks = [];
        Network.wifiConnected = false;
        Network.wifiSsid = "";
    }

    function network(ssid, strength) {
        return {
            ssid: ssid,
            strength: strength,
            secured: true,
            security: "WPA2/WPA3",
            connected: false
        };
    }

    function test_connectedNetworkComesFirstAndLit() {
        SystemStatusStore.isWifiOn = true;
        Network.availableNetworks = [network("Cafe", 90), network("Home", 60)];
        Network.wifiConnected = true;
        Network.wifiSsid = "Home";
        let home = null;
        tryVerify(() => (home = findChild(beat, "oobeNetwork-Home")) && home.visible);
        const cafe = findChild(beat, "oobeNetwork-Cafe");
        verify(home.connected);
        verify(!home.enabled);
        verify(!cafe.connected);
        verify(home.lit);
        verify(!cafe.lit);
        tryVerify(() => home.y < cafe.y);
        verify(findChild(home, "oobeNetworkStatus").visible);
        verify(!findChild(cafe, "oobeNetworkStatus").visible);
    }

    function test_continueAdvances() {
        SystemStatusStore.isWifiOn = true;
        mouseClick(findChild(beat, "oobeContinue"));
        compare(doneSpy.count, 1);
    }

    function test_notNowAdvancesWithoutConnecting() {
        SystemStatusStore.isWifiOn = true;
        Network.availableNetworks = [network("Cafe", 90)];
        mouseClick(findChild(beat, "oobeNotNow"));
        compare(doneSpy.count, 1);
        verify(!Network.wifiConnected);
    }

    function test_wifiOffShowsTheSwitchAndNotNowWorks() {
        SystemStatusStore.isWifiOn = false;
        verify(findChild(beat, "oobeWifiSwitch").visible);
        verify(!findChild(beat, "oobeJoinOther").visible);
        mouseClick(findChild(beat, "oobeNotNow"));
        compare(doneSpy.count, 1);
    }

    function test_noBackStateToConsume() {
        verify(!beat.handleBack());
    }
}
