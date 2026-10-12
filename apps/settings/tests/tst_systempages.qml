import QtQuick
import QtTest
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import MarathonApp.Settings
import ".."

TestCase {
    id: testCase

    name: "SystemPages"
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
        Security.reset();
        Updates.reset();
        DavSync.reset();
        Power.reset();
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

    function pushed(app, from) {
        tryVerify(() => app.pageStack.currentPage !== from && app.pageStack.currentPage.status === PageStatus.Active, 3000);
        return app.pageStack.currentPage;
    }

    function back(s) {
        tryVerify(() => s.app.pageStack.currentPage === s.page && s.page.status === PageStatus.Active, 3000);
    }

    function test_securityStatus() {
        Security.fingerprintAvailable = true;
        Security.failedAttempts = 2;
        const s = open("security");
        compare(findChild(s.page, "lockMethod"), null);
        const autoLock = child(s.page, "autoLockSwitch");
        verify(autoLock.checked);
        autoLock.clicked(null);
        verify(!Settings.autoLock);
        verify(!autoLock.checked);
        compare(child(s.page, "fingerprint").value, "Enrolled");
        compare(child(s.page, "failedAttempts").value, "2");
        compare(child(s.page, "accountStatus").value, "Active");
        Security.isLockedOut = true;
        Security.lockoutSecondsRemaining = 30;
        compare(child(s.page, "accountStatus").value, "Locked (30s remaining)");
        verify(!child(s.page, "removePinItem").visible);
        compare(child(s.page, "pinItem").text, "Set quick PIN");
    }

    function test_setQuickPin() {
        const s = open("security");
        child(s.page, "pinItem").clicked(null);
        const dialog = pushed(s.app, s.page);
        verify(!dialog.changing);
        dialog.pin = "12";
        verify(!dialog.canAccept);
        dialog.pin = "1234";
        dialog.confirmation = "1235";
        dialog.password = "secret";
        verify(dialog.mismatch);
        verify(!dialog.canAccept);
        dialog.confirmation = "1234";
        verify(dialog.canAccept);
        dialog.accept();
        back(s);
        compare(Security.calls, [["set", "1234", "secret"]]);
        verify(!child(s.page, "pinItem").enabled);
        Security.authenticationFailed("Wrong password");
        compare(s.page.pending, "");
        const retry = pushed(s.app, s.page);
        compare(retry.pin, "1234");
        compare(retry.confirmation, "1234");
        compare(retry.password, "");
        verify(child(retry, "passwordField").errorHighlight);
        compare(child(retry, "passwordField").description, "Wrong password");
        retry.password = "right";
        verify(!child(retry, "passwordField").errorHighlight);
        verify(retry.canAccept);
        retry.accept();
        back(s);
        compare(Security.calls[1], ["set", "1234", "right"]);
    }

    function test_removeQuickPin() {
        Security.hasQuickPIN = true;
        const s = open("security");
        compare(child(s.page, "pinItem").text, "Change quick PIN");
        child(s.page, "removePinItem").clicked(null);
        const dialog = pushed(s.app, s.page);
        verify(!dialog.canAccept);
        dialog.password = "secret";
        dialog.accept();
        back(s);
        compare(Security.calls, [["remove", "secret"]]);
        compare(s.page.pending, "remove");
        Security.hasQuickPIN = false;
        Security.quickPINChanged();
        compare(s.page.pending, "");
        verify(!child(s.page, "removePinItem").visible);
    }

    function test_accounts() {
        const s = open("accounts");
        const list = child(s.page, "accountList");
        compare(list.count, 0);
        verify(child(s.page, "placeholder").enabled);
        verify(!child(s.page, "syncItem").enabled);
        child(s.page, "addItem").clicked();
        const dialog = pushed(s.app, s.page);
        verify(!dialog.canAccept);
        dialog.baseUrl = "https://cloud.example.com";
        dialog.username = "pat";
        dialog.secret = "pw";
        verify(dialog.canAccept);
        dialog.accept();
        back(s);
        compare(DavSync.calls, [["add", "pat", "https://cloud.example.com", "pat", "pw", "basic"]]);
        compare(list.count, 1);
        verify(!child(s.page, "placeholder").enabled);
        compare(s.page.checkingId, "acc1");
        verify(!child(s.page, "addItem").enabled);
        DavSync.accountDiscovered("acc1");
        compare(s.page.checkingId, "");
        compare(DavSync.calls[1], ["sync"]);
        child(s.page, "syncItem").clicked();
        compare(DavSync.calls[2], ["sync"]);
        compare(child(s.page, "lastSync").value, "Never");
        DavSync.lastError = "401";
        verify(child(s.page, "lastError").visible);
    }

    function test_addAccountFailureKeepsInput() {
        const s = open("accounts");
        child(s.page, "addItem").clicked();
        const dialog = pushed(s.app, s.page);
        dialog.baseUrl = " cloud.example.com ";
        dialog.username = "pat";
        dialog.secret = "wrong";
        dialog.displayName = "Work";
        dialog.accept();
        back(s);
        compare(DavSync.calls, [["add", "Work", "https://cloud.example.com", "pat", "wrong", "basic"]]);
        DavSync.accountDiscoveryFailed("acc1", "principal not found");
        const retry = pushed(s.app, s.page);
        compare(DavSync.calls[1], ["remove", "acc1"]);
        compare(child(s.page, "accountList").count, 0);
        verify(child(retry, "errorLabel").visible);
        compare(retry.baseUrl, " cloud.example.com ");
        compare(retry.username, "pat");
        compare(retry.secret, "wrong");
        compare(retry.displayName, "Work");
    }

    function test_removeAccount() {
        DavSync.accounts = [{ id: "a1", displayName: "Nextcloud", baseUrl: "https://c", username: "pat" }];
        const s = open("accounts");
        const item = child(s.page, "account-a1");
        item.remorseDelete(() => DavSync.removeAccount("a1"), 1);
        tryCompare(child(s.page, "accountList"), "count", 0, 5000);
        compare(DavSync.calls, [["remove", "a1"]]);
    }

    function test_updates() {
        const s = open("updates");
        compare(child(s.page, "statusLabel").text, "Update r380 is available");
        compare(child(s.page, "currentVersion").value, "r375");
        verify(child(s.page, "howToUpdate").visible);
        child(s.page, "checkItem").clicked();
        child(s.page, "openReleaseButton").clicked(null);
        compare(Updates.calls, [["check"], ["open"]]);
        const channel = child(s.page, "channelCombo");
        compare(channel.currentIndex, 0);
        Updates.setChannel("edge");
        compare(channel.currentIndex, 1);
        Updates.updateAvailable = false;
        compare(child(s.page, "statusLabel").text, "Up to date");
        verify(!child(s.page, "howToUpdate").visible);
        verify(!child(s.page, "openReleaseButton").visible);
        verify(!child(s.page, "errorHint").visible);
        Updates.lastError = "Host api.github.com not found";
        compare(child(s.page, "statusLabel").text, "Couldn't check for updates");
        verify(child(s.page, "errorHint").visible);
    }

    function test_aboutAndRename() {
        const s = open("about");
        compare(child(s.page, "nameButton").value, "Librem 5");
        compare(child(s.page, "storageItem").value, "64.0 GB");
        compare(child(s.page, "batteryItem").value, "80%");
        compare(child(s.page, "versionItem").value, "r375");
        compare(child(s.page, "baseItem").value, "postmarketOS edge");
        Power.batteryLevel = -1;
        compare(child(s.page, "batteryItem").value, "No battery");
        child(s.page, "nameButton").clicked(null);
        const dialog = pushed(s.app, s.page);
        compare(dialog.name, "Librem 5");
        dialog.name = "  ";
        verify(!dialog.canAccept);
        dialog.name = " Pat's phone ";
        dialog.accept();
        back(s);
        compare(Settings.deviceName, "Pat's phone");
    }

    function test_legalPages() {
        const s = open("about");
        child(s.page, "licensesItem").clicked(null);
        const licenses = pushed(s.app, s.page);
        compare(child(licenses, "sections").count, 1);
        s.app.pageStack.pop(undefined, PageStackAction.Immediate);
        back(s);
        child(s.page, "termsItem").clicked(null);
        compare(pushed(s.app, s.page).title, "Terms of service");
        s.app.pageStack.pop(undefined, PageStackAction.Immediate);
        back(s);
        child(s.page, "privacyItem").clicked(null);
        compare(pushed(s.app, s.page).sections.length, 3);
    }
}
