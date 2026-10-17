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

    function pick(combo, index) {
        let n = 0;
        let found = null;
        combo.menu._foreachMenuItem(function (item) {
            if (n++ === index)
                found = item;
            return found === null;
        });
        found.clicked();
    }

    function pushed(app, from) {
        tryVerify(() => app.pageStack.currentPage !== from && app.pageStack.currentPage.status === PageStatus.Active, 3000);
        return app.pageStack.currentPage;
    }

    function back(s) {
        tryVerify(() => s.app.pageStack.currentPage === s.page && s.page.status === PageStatus.Active, 3000);
    }

    function test_securityStatusHiddenWhenQuiet() {
        const s = open("security");
        verify(!child(s.page, "statusHeader").visible);
        verify(!child(s.page, "fingerprint").visible);
        verify(!child(s.page, "failedAttempts").visible);
        verify(!child(s.page, "accountStatus").visible);
    }

    function test_securityStatus() {
        Security.fingerprintAvailable = true;
        Security.failedAttempts = 2;
        const s = open("security");
        compare(findChild(s.page, "lockMethod"), null);
        compare(findChild(s.page, "autoLockSwitch"), null);
        compare(child(s.page, "fingerprint").value, "Enrolled");
        compare(child(s.page, "failedAttempts").value, "2");
        verify(child(s.page, "statusHeader").visible);
        verify(!child(s.page, "accountStatus").visible);
        Security.isLockedOut = true;
        verify(child(s.page, "accountStatus").visible);
        Security.lockoutSecondsRemaining = 30;
        compare(child(s.page, "accountStatus").value, "Locked (30s remaining)");
        verify(!child(s.page, "removePinItem").visible);
        compare(child(s.page, "pinItem").text, "Set quick PIN");
    }

    function test_lockDelay() {
        const s = open("security");
        const combo = child(s.page, "lockDelayCombo");
        compare(combo.currentIndex, 0);
        compare(combo.value, "Immediately");
        let labels = [];
        combo.menu._foreachMenuItem(function (item) {
            labels.push(item.text);
            return true;
        });
        compare(labels, ["Immediately", "5 seconds", "30 seconds", "1 minute", "5 minutes"]);
        pick(combo, 3);
        compare(Settings.autoLockTimeout, 60);
        compare(combo.value, "1 minute");
        Settings.autoLockTimeout = 300;
        compare(combo.currentIndex, 4);
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
        verify(!child(s.page, "syncState").visible);
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
        verify(child(s.page, "syncState").visible);
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

    function test_toggleAccountSync() {
        DavSync.accounts = [{ id: "a1", displayName: "Nextcloud", baseUrl: "https://c", username: "pat", enabled: true }];
        const s = open("accounts");
        const item = child(s.page, "account-a1");
        const menu = item.openMenu();
        tryVerify(() => menu._open && menu.height > 0);
        wait(300);
        const toggle = findChild(menu, "enableItem");
        compare(toggle.text, "Turn off sync");
        mouseClick(toggle);
        compare(DavSync.calls, [["enable", "a1", false]]);
        tryVerify(() => child(s.page, "account-a1").syncOff);
    }

    function test_updateAvailable() {
        const s = open("updates");
        compare(child(s.page, "statusLabel").text, "Marathon OS 26101801 is available");
        verify(child(s.page, "sizeLabel").visible);
        verify(child(s.page, "sizeLabel").text.startsWith("Download size: "));
        compare(child(s.page, "notesLabel").text, "Faster boot");
        verify(!child(s.page, "hintLabel").visible);
        compare(child(s.page, "osVersion").value, "26101701");
        compare(child(s.page, "currentVersion").value, "r375");
        verify(!child(s.page, "downloadProgress").visible);
        child(s.page, "checkItem").clicked();
        child(s.page, "installButton").clicked(null);
        compare(Updates.calls, [["check"], ["install"]]);
        Updates.downloadSize = -1;
        verify(!child(s.page, "sizeLabel").visible);
    }

    function test_updateBlocked() {
        const s = open("updates");
        const hint = child(s.page, "hintLabel");
        Updates.blockedReason = "metered";
        compare(hint.text, "Connect to Wi-Fi to download this update.");
        verify(hint.visible);
        Updates.blockedReason = "battery";
        compare(hint.text, "Charge to at least 30%, or plug in, to download this update.");
        verify(child(s.page, "installButton").visible);
    }

    function test_updateDownloadingThenReady() {
        Updates.state = "downloading";
        Updates.progress = 42;
        const s = open("updates");
        compare(child(s.page, "statusLabel").text, "Downloading Marathon OS 26101801…");
        const bar = child(s.page, "downloadProgress");
        verify(bar.visible);
        compare(bar.value, 42);
        verify(!child(s.page, "installButton").visible);
        verify(!child(s.page, "checkItem").enabled);
        child(s.page, "cancelButton").clicked(null);
        compare(Updates.calls, [["cancel"]]);

        Updates.state = "readyToReboot";
        compare(child(s.page, "statusLabel").text, "Marathon OS 26101801 is ready to install");
        verify(!bar.visible);
        verify(child(s.page, "hintLabel").text.startsWith("Restart to finish."));
        child(s.page, "rebootButton").clicked(null);
        compare(Updates.calls, [["cancel"], ["reboot"]]);
    }

    function test_updateRolledBack() {
        Updates.state = "rolledBack";
        Updates.rolledBackVersion = "26101801";
        const s = open("updates");
        compare(child(s.page, "statusLabel").text, "Marathon OS 26101801 didn't start");
        compare(child(s.page, "hintLabel").text, "Your phone went back to 26101701. A fixed update will be offered when it's published.");
        verify(!child(s.page, "installButton").visible);
        verify(!child(s.page, "rebootButton").visible);
        verify(child(s.page, "checkItem").enabled);
    }

    function test_updateStates() {
        Updates.state = "idle";
        Updates.lastCheckedMs = 0;
        const s = open("updates");
        const status = child(s.page, "statusLabel");
        compare(status.text, "Not checked yet");
        verify(!child(s.page, "lastChecked").visible);
        Updates.state = "checking";
        compare(status.text, "Checking for updates…");
        Updates.state = "upToDate";
        Updates.lastCheckedMs = 1760000000000;
        compare(status.text, "Up to date");
        verify(child(s.page, "lastChecked").visible);
        verify(child(s.page, "lastChecked").value !== "");
        Updates.state = "error";
        Updates.lastError = "Could not resolve host";
        compare(status.text, "Couldn't install Marathon OS 26101801");
        compare(child(s.page, "hintLabel").text, "The download didn't finish. Pull down to try again.");
        Updates.availableVersion = "";
        compare(status.text, "Couldn't check for updates");
        compare(child(s.page, "hintLabel").text, "Couldn't reach the update server. Check your connection, then pull down to try again.");
        Updates.state = "unsupported";
        compare(status.text, "This device can't install updates yet");
        verify(child(s.page, "hintLabel").visible);
    }

    function test_updateAutomatic() {
        const s = open("updates");
        const toggle = child(s.page, "autoUpdateSwitch");
        verify(toggle.visible);
        verify(toggle.checked);
        toggle.clicked(null);
        verify(!Updates.autoUpdate);
        verify(!toggle.checked);
        toggle.clicked(null);
        verify(Updates.autoUpdate);
        Updates.state = "unsupported";
        verify(!toggle.visible);
    }

    function test_updateTonight() {
        Updates.state = "readyToReboot";
        Updates.autoUpdate = false;
        const s = open("updates");
        const tonight = child(s.page, "tonightButton");
        verify(tonight.visible);
        tonight.clicked(null);
        compare(Updates.calls, [["tonight"]]);
        Updates.restartScheduled = true;
        verify(!tonight.visible);
        compare(child(s.page, "hintLabel").text, "It restarts tonight between 2 and 5 AM, on charge and not in use. If it doesn't start properly, your phone goes back to the version it has now.");
        verify(child(s.page, "rebootButton").visible);
    }

    function test_updateWhatsNew() {
        Updates.state = "upToDate";
        Updates.currentReleaseNotes = "";
        const s = open("updates");
        const notes = child(s.page, "currentNotesLabel");
        verify(!notes.visible);
        verify(!child(s.page, "notesLabel").visible);
        Updates.currentReleaseNotes = "Faster Wi-Fi";
        verify(notes.visible);
        compare(notes.text, "Faster Wi-Fi");
        verify(child(s.page, "currentNotesHeader").visible);
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
