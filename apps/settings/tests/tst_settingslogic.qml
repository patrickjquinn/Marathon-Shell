import QtQuick
import QtTest
import "../SettingsLogic.js" as Logic

TestCase {
    name: "SettingsLogic"

    function test_pageFile() {
        compare(Logic.pageFile("wifi"), "WiFiPage.qml");
        compare(Logic.pageFile("/about"), "AboutPage.qml");
        compare(Logic.pageFile("Bluetooth"), "BluetoothPage.qml");
        compare(Logic.pageFile("display/brightness"), "DisplayPage.qml");
        compare(Logic.pageFile("scale"), "DisplayPage.qml");
        compare(Logic.pageFile("ambience"), "AmbiencePage.qml");
        compare(Logic.pageFile("wallpaper"), "AmbiencePage.qml");
        compare(Logic.pageFile("nope"), "");
        compare(Logic.pageFile(""), "");
        compare(Logic.pageFile(undefined), "");
    }

    function test_everyEntryHasAPage() {
        Logic.sections.forEach(section => section.entries.forEach(entry => {
            verify(entry.app || Logic.pageFile(entry.page) !== "", entry.title);
            verify(entry.icon.indexOf("image://theme/icon-m-") === 0, entry.title);
        }));
    }

    function test_search() {
        compare(Logic.search(""), []);
        compare(Logic.search("   "), []);
        compare(Logic.search("wifi").map(e => e.page), ["wifi"]);
        compare(Logic.search("PIN").map(e => e.page), ["security"]);
        compare(Logic.search("volume")[0].page, "sound");
        compare(Logic.search("volume")[0].section, "Device");
        compare(Logic.search("tiles")[0].section, "Device");
        compare(Logic.search("accounts")[0].section, "Security and accounts");
        compare(Logic.search("time zone").map(e => e.page), ["datetime"]);
        compare(Logic.search("terminal")[0].app, "terminal");
        compare(Logic.search("zzz"), []);
    }

    function test_wlanIcon() {
        compare(Logic.wlanIcon(0), "image://theme/icon-m-wlan-0");
        compare(Logic.wlanIcon(20), "image://theme/icon-m-wlan-1");
        compare(Logic.wlanIcon(50), "image://theme/icon-m-wlan-2");
        compare(Logic.wlanIcon(90), "image://theme/icon-m-wlan-3");
        compare(Logic.wlanIcon(150), "image://theme/icon-m-wlan-3");
        compare(Logic.wlanIcon(undefined), "image://theme/icon-m-wlan-0");
    }

    function test_signalQuality() {
        compare(Logic.signalQuality(80), "Excellent");
        compare(Logic.signalQuality(55), "Good");
        compare(Logic.signalQuality(30), "Fair");
        compare(Logic.signalQuality(5), "Weak");
    }

    function test_batteryStatus() {
        compare(Logic.batteryStatus(true, true, 0), "Charging");
        compare(Logic.batteryStatus(false, true, 0), "Plugged in, not charging");
        compare(Logic.batteryStatus(false, false, 0), "Discharging");
        compare(Logic.batteryStatus(false, false, 2 * 3600 + 5 * 60), "2 h 5 min left");
        compare(Logic.batteryStatus(false, false, 40 * 60), "40 min left");
    }

    function test_networkSubtitle() {
        compare(Logic.networkSubtitle({ ssid: "Cafe", strength: 55, security: "Open", secured: false }), "Open · Good signal");
        compare(Logic.networkSubtitle({ ssid: "Home", strength: 80, security: "WPA2", secured: true, known: true }), "Saved · Secured · Excellent signal");
        compare(Logic.networkSubtitle({ ssid: "Lab", strength: 10, security: "WPA3" }), "Secured · Weak signal");
    }

    function test_deviceIcon() {
        compare(Logic.deviceIcon("headphones"), "image://theme/icon-m-headphone");
        compare(Logic.deviceIcon(" Keyboard "), "image://theme/icon-m-keyboard");
        compare(Logic.deviceIcon("volume-2"), "image://theme/icon-m-speaker");
        compare(Logic.deviceIcon(""), "image://theme/icon-m-bluetooth");
        compare(Logic.deviceIcon(undefined), "image://theme/icon-m-bluetooth");
    }

    function test_summaries() {
        compare(Logic.wifiSummary(false, false, ""), "Off");
        compare(Logic.wifiSummary(true, false, ""), "On");
        compare(Logic.wifiSummary(true, true, "Home"), "Home");
        compare(Logic.bluetoothSummary(false, [{ name: "Buds", connected: true }]), "Off");
        compare(Logic.bluetoothSummary(true, []), "On");
        compare(Logic.bluetoothSummary(true, [{ name: "A" }, { alias: "Buds", name: "x", connected: true }]), "Buds");
        compare(Logic.batterySummary(55, false), "55%");
        compare(Logic.batterySummary(55, true), "55% · charging");
        compare(Logic.batterySummary(-1, false), "");
        compare(Logic.batterySummary(undefined, false), "");
        compare(Logic.percent(0.456), 46);
        compare(Logic.percent(2), 100);
        compare(Logic.zoneCity("America/Port_of_Spain"), "Port of Spain");
        compare(Logic.zoneCity(""), "UTC");
    }

    function test_setMember() {
        compare(Logic.setMember(["a", "b"], "c", true), ["a", "b", "c"]);
        compare(Logic.setMember(["a", "b"], "a", true), ["b", "a"]);
        compare(Logic.setMember(["a", "b"], "a", false), ["b"]);
        compare(Logic.setMember(undefined, "a", true), ["a"]);
    }

    function test_nearestIndex() {
        const factors = Logic.scales.map(s => s.factor);
        compare(Logic.nearestIndex(factors, 1), 2);
        compare(Logic.nearestIndex(factors, 1.0999), 3);
        compare(Logic.nearestIndex(factors, 3), factors.length - 1);
    }

    function test_manifestPermissionsHaveLabels() {
        compare(Logic.permissionInfo("phone").title, "Phone");
        compare(Logic.permissionInfo("secret-service").title, "Passwords");
        verify(Logic.permissionInfo("secret-service").description.length > 0);
    }
}
