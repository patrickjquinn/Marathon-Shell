import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import MarathonOS.Settings 1.0
import "../SettingsLogic.js" as Logic
import ".."

TestCase {
    id: testCase

    name: "MmsPage"
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
        Settings.reset();
        Modem.reset();
        MmsSettings.reset();
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

    function test_validation() {
        compare(Logic.mmscError("http://mms.vodafone.ie/servlets/mms"), "");
        compare(Logic.mmscError("https://mms.example.com:8443/mms"), "");
        compare(Logic.mmscError("http://10.0.0.1/"), "");
        verify(Logic.mmscError("") !== "");
        verify(Logic.mmscError("mms.example.com") !== "");
        verify(Logic.mmscError("ftp://mms.example.com") !== "");
        verify(Logic.mmscError("http://") !== "");
        verify(Logic.mmscError("http://mms example.com/") !== "");
        verify(Logic.mmscError("http://mms.invalid") !== "");

        compare(Logic.mmsProxyError(""), "");
        compare(Logic.mmsProxyError("10.24.59.200:80"), "");
        compare(Logic.mmsProxyError("proxy.example.com"), "");
        compare(Logic.mmsProxyError("proxy.example.com:8080"), "");
        verify(Logic.mmsProxyError("http://proxy:80") !== "");
        verify(Logic.mmsProxyError("proxy:0") !== "");
        verify(Logic.mmsProxyError("proxy:70000") !== "");
        verify(Logic.mmsProxyError("pro xy") !== "");

        compare(Logic.apnError("live.vodafone.com"), "");
        compare(Logic.apnError("mms"), "");
        compare(Logic.apnError("three.co.uk_mms"), "");
        verify(Logic.apnError("") !== "");
        verify(Logic.apnError("apn.invalid") !== "");
        verify(Logic.apnError(".mms") !== "");
        verify(Logic.apnError("my apn") !== "");
        verify(Logic.apnError("a".repeat(101)) !== "");
    }

    // mmsd-tng's placeholders mean "not set".
    function test_unsetValues() {
        compare(Logic.mmsValue("http://mms.invalid"), "");
        compare(Logic.mmsValue("apn.invalid"), "");
        compare(Logic.mmsValue("NULL"), "");
        compare(Logic.mmsValue("live.vodafone.com"), "live.vodafone.com");
    }

    function test_entryOnMobileNetwork() {
        const s = open("cellular");
        const entry = child(s.page, "mmsEntry");
        compare(entry.subtitle, "live.vodafone.com");
        MmsSettings.available = false;
        compare(entry.subtitle, "Not available");
        entry.clicked(null);
        tryVerify(() => String(s.app.pageStack.currentPage).indexOf("MmsPage") === 0 && !s.app.pageStack.busy);
    }

    function test_page() {
        const s = open("mms");
        compare(MmsSettings.calls[0][0], "refresh");
        compare(child(s.page, "mmscItem").value, "http://mms.vodafone.ie/servlets/mms");
        compare(child(s.page, "proxyItem").value, "10.24.59.200:80");
        compare(child(s.page, "apnItem").value, "live.vodafone.com");
        const auto = child(s.page, "autoDownloadSwitch");
        verify(auto.checked);
        auto.clicked(null);
        compare(MmsSettings.calls[MmsSettings.calls.length - 1], ["setAutoDownload", false]);
        verify(!child(s.page, "placeholder").enabled);

        MmsSettings.proxy = "";
        MmsSettings.mmsc = "";
        compare(child(s.page, "proxyItem").value, "None");
        compare(child(s.page, "mmscItem").value, "Not set");
    }

    function test_unavailable() {
        MmsSettings.available = false;
        const s = open("mms");
        verify(child(s.page, "placeholder").enabled);
        compare(child(s.page, "placeholder").text, "MMS isn't available");
        verify(!child(s.page, "autoDownloadSwitch").visible);
        verify(!child(s.page, "editItem").visible);
        Modem.available = false;
        verify(child(s.page, "placeholder").hintText.indexOf("modem") >= 0);
    }

    // Saving goes through a dialog that won't accept bad values.
    function test_edit() {
        const s = open("mms");
        child(s.page, "editItem").clicked();
        tryVerify(() => String(s.app.pageStack.currentPage).indexOf("MmsDialog") === 0 && !s.app.pageStack.busy);
        const dialog = s.app.pageStack.currentPage;
        const mmsc = child(dialog, "mmscField");
        const proxy = child(dialog, "proxyField");
        const apn = child(dialog, "apnField");
        compare(mmsc.text, "http://mms.vodafone.ie/servlets/mms");
        verify(dialog.canAccept);

        mmsc.text = "mms.example.com";
        verify(!dialog.canAccept);
        verify(mmsc.errorHighlight);
        mmsc.text = " http://mms.example.com/mms ";
        verify(dialog.canAccept);
        proxy.text = "proxy:99999";
        verify(!dialog.canAccept);
        proxy.text = "";
        apn.text = "my apn";
        verify(!dialog.canAccept);
        apn.text = "mms.example";
        verify(dialog.canAccept);

        dialog.accept();
        tryVerify(() => s.app.pageStack.currentPage === s.page && !s.app.pageStack.busy);
        compare(MmsSettings.calls[MmsSettings.calls.length - 1], ["save", "http://mms.example.com/mms", "mms.example", ""]);
        compare(child(s.page, "apnItem").value, "mms.example");
    }
}
