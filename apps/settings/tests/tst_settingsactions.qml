import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Keel.Actions 1.0
import Marathon.Platform 1.0
import "../SettingsLogic.js" as Logic
import ".."

TestCase {
    id: testCase

    name: "SettingsActions"
    when: windowShown
    visible: true
    width: 540
    height: 1140

    property var app

    Component {
        id: appComponent

        SettingsApp {
            width: 540
            height: 1140
        }
    }

    function initTestCase() {
        app = appComponent.createObject(testCase);
        tryVerify(() => app.pageStack.currentPage !== null);
    }

    function cleanupTestCase() {
        app.destroy();
    }

    function init() {
        Network.reset();
        Bluetooth.reset();
        Power.reset();
    }

    function invoke(name, args) {
        const call = KeelActions.invoke(name, args);
        tryCompare(call, "finished", true);
        verify(call.succeeded, call.errorMessage);
        return call.result;
    }

    function test_status() {
        Network.wifiConnected = true;
        Network.wifiSsid = "Home";
        Bluetooth.enabled = true;
        Bluetooth.pairedDevices = [
            {
                address: "A",
                name: "Buds",
                connected: true
            }
        ];
        Power.batteryLevel = 64;
        Power.isCharging = true;
        compare(invoke("settings.status", {}), {
            wifiEnabled: true,
            wifiNetwork: "Home",
            airplaneMode: false,
            bluetoothEnabled: true,
            bluetoothDevice: "Buds",
            batteryLevel: 64,
            charging: true
        });
    }

    function test_statusOffAndNoBattery() {
        Network.wifiEnabled = false;
        Power.batteryLevel = -1;
        const status = invoke("settings.status", {});
        compare(status.wifiEnabled, false);
        compare(status.wifiNetwork, "");
        compare(status.bluetoothEnabled, false);
        compare(status.bluetoothDevice, "");
        compare(status.batteryLevel, undefined);
    }

    function test_wifiSwitch() {
        invoke("wifi.switch", {
            enabled: true
        });
        compare(Network.calls, []);
        invoke("wifi.switch", {
            enabled: false
        });
        compare(Network.calls, [["toggleWifi"]]);
        tryCompare(Network, "wifiEnabled", false);
        Network.wifiAvailable = false;
        compare(KeelActions.invoke("wifi.switch", {
            enabled: true
        }).errorCode, "NotAvailable");
    }

    function test_bluetoothSwitch() {
        invoke("bluetooth.switch", {
            enabled: true
        });
        compare(Bluetooth.enabled, true);
        invoke("bluetooth.switch", {
            enabled: true
        });
        compare(Bluetooth.enabled, true);
        invoke("bluetooth.switch", {
            enabled: false
        });
        compare(Bluetooth.enabled, false);
    }

    function test_switchesAskFirst() {
        const tools = KeelActions.describe().tools;
        for (const name of ["wifi.switch", "bluetooth.switch"])
            verify(tools.find(t => t.name.endsWith("/" + name))._meta["org.shipwright.keel/confirm"], name);
    }

    // A pull-down from the page's top opens its pulley menu.
    function pulleyIn(item) {
        if (!item)
            return null;
        if (item._isPullDownMenu === true && item.visible)
            return item;
        const children = item.children || [];
        for (let i = 0; i < children.length; ++i) {
            const found = pulleyIn(children[i]);
            if (found)
                return found;
        }
        return null;
    }

    function pullDown(item) {
        const menu = pulleyIn(item);
        verify(menu, "a pull-down menu");
        const x = item.width / 2;
        mousePress(item, x, 300);
        for (let y = 320; y <= 780; y += 40)
            mouseMove(item, x, y, 16);
        verify(menu.active, "pulley open");
        mouseRelease(item, x, 780);
        return menu;
    }

    function test_wifiPulleyOpens() {
        invoke("app.show", {
            page: "wifi"
        });
        tryVerify(() => String(app.pageStack.currentPage).indexOf("WiFiPage") === 0 && !app.pageStack.busy);
        pullDown(app.pageStack.currentPage);
    }

    function test_showOpensAPage() {
        invoke("app.show", {
            page: "battery"
        });
        tryVerify(() => app.pageStack.depth === 2 && !app.pageStack.busy);
        verify(String(app.pageStack.currentPage).indexOf("BatteryPage") === 0, String(app.pageStack.currentPage));
        invoke("app.show", {
            page: "wifi"
        });
        tryVerify(() => String(app.pageStack.currentPage).indexOf("WiFiPage") === 0 && !app.pageStack.busy);
        compare(app.pageStack.depth, 2);
        compare(KeelActions.invoke("app.show", {
            page: "nonsense"
        }).errorCode, "InvalidArguments");
    }

    function shownPages() {
        const show = KeelActions.describe().tools.find(t => t.name.endsWith("/app.show"));
        return show.inputSchema.properties.page.enum;
    }

    // Every page Settings has a route to can be opened by app.show.
    function test_everyPageIsDeclared() {
        const declared = shownPages();
        const files = declared.map(name => Logic.pageFile(name));
        for (const name of declared)
            verify(Logic.pageFile(name) !== "", name + " is not a route");
        for (const route in Logic.pages)
            verify(files.indexOf(Logic.pages[route]) >= 0, Logic.pages[route] + " has no KeelPage");
    }

    function test_everyDeclaredPageOpens() {
        for (const name of shownPages()) {
            invoke("app.show", {
                page: name
            });
            const file = Logic.pageFile(name).replace(".qml", "");
            tryVerify(() => String(app.pageStack.currentPage).indexOf(file) === 0 && !app.pageStack.busy, 5000, name);
            compare(app.pageStack.depth, 2, name);
        }
    }

    function readJson(file) {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", Qt.resolvedUrl("../" + file), false);
        xhr.send();
        return JSON.parse(xhr.responseText);
    }

    // keel-actions.json is generated by `keel actions`; it must match the
    // declarations.
    function test_manifestMatchesDeclarations() {
        const manifest = readJson("keel-actions.json");
        compare(manifest.appId, "org.marathonos.settings");
        const live = KeelActions.describe();
        const prefix = live.appId + "/";
        const tools = live.tools.map(t => Object.assign({}, t, {
                name: "org.marathonos.settings/" + t.name.substring(prefix.length)
            }));
        compare(JSON.stringify(tools), JSON.stringify(manifest.tools));
    }

    // The shell's search offers manifest.json's deepLinks: one for every
    // page, each opening it as a link from search does.
    function test_everyPageHasADeepLink() {
        const links = readJson("manifest.json").deepLinks;
        const files = Object.keys(links).map(route => Logic.pageFile(route));
        for (const route in links) {
            verify(Logic.pageFile(route) !== "", route + " is not a route");
            verify(links[route].title && links[route].description, route);
        }
        for (const route in Logic.pages)
            verify(files.indexOf(Logic.pages[route]) >= 0, Logic.pages[route] + " has no deep link");
    }

    function test_deepLinksOpenTheirPage() {
        for (const route in readJson("manifest.json").deepLinks) {
            verify(app.openPage(route, PageStackAction.Immediate, true, true), route);
            const file = Logic.pageFile(route).replace(".qml", "");
            tryVerify(() => String(app.pageStack.currentPage).indexOf(file) === 0 && !app.pageStack.busy, 5000, route);
            compare(app.pageStack.depth, 2, route);
        }
    }
}
