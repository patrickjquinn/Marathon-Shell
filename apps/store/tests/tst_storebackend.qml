import QtQuick
import QtTest
import "Fixtures.js" as Fixtures

TestCase {
    id: testCase

    name: "StoreBackend"

    Component {
        id: backendComponent
        TestBackend {}
    }

    SignalSpy {
        id: finishedSpy
        signalName: "jobFinished"
    }

    function makeBackend() {
        const b = createTemporaryObject(backendComponent, testCase);
        finishedSpy.clear();
        finishedSpy.target = b;
        return b;
    }

    function test_discoverListsNeverRepeat() {
        const b = makeBackend();
        b.collections = Fixtures.collections();
        compare(b.heroApp.app_id, "org.example.Hero");
        compare(b.trendingApps.map(a => a.app_id), ["org.example.T1", "org.example.T2", "org.example.T3"]);
        compare(b.mobileApps.map(a => a.app_id), ["org.example.M1", "org.example.M2"]);
        compare(b.newApps.map(a => a.app_id), ["org.example.N1"]);
        compare(b.topApps.length, 2);
        compare(b.catalogAppCount, 12);
    }

    function test_onlyAarch64Kept() {
        const b = makeBackend();
        const hits = [{ "app_id": "a.b.C", "arches": ["x86_64"] }, { "app_id": "a.b.D", "arches": ["x86_64", "aarch64"] }];
        compare(b.pickAarch64(hits).map(a => a.app_id), ["a.b.D"]);
    }

    function test_urlClamps() {
        const b = makeBackend();
        compare(b.safeImageUrl("https://dl.flathub.org/x.png"), "https://dl.flathub.org/x.png");
        compare(b.safeImageUrl("http://192.168.1.1/x.png"), "");
        compare(b.safeImageUrl("file:///etc/passwd"), "");
        let err = "";
        b.fetchJson("https://evil.example/api", null, (d, e) => err = e);
        compare(err, "refusing url outside Flathub and ODRS");
    }

    function test_validRefs() {
        const b = makeBackend();
        verify(b.isValidRef("org.gnome.Maps"));
        verify(!b.isValidRef("org..gnome"));
        verify(!b.isValidRef("rm -rf"));
        verify(!b.isValidRef("../etc"));
        b.installApp("bad ref");
        compare(b.opened, []);
    }

    function test_formatting() {
        const b = makeBackend();
        compare(b.formatCount(0), "–");
        compare(b.formatCount(999), "999");
        compare(b.formatCount(1500), "1.5k");
        compare(b.formatCount(25000), "25k");
        compare(b.formatCount(2500000), "2.5M");
        compare(b.formatSize(512), "1 KB");
        compare(b.formatSize(5242880), "5.0 MB");
        compare(b.formatSize(2147483648), "2.0 GB");
        compare(b.cleanMarkup("<p>a\n   b</p><img src=\"x\">"), "<p>a b</p>");
    }

    function test_permissionsInPlainWords() {
        const b = makeBackend();
        const perms = b.describePermissions(Fixtures.summary().metadata.permissions);
        compare(perms.map(p => p.label), ["Internet", "All your files", "Audio"]);
        verify(perms[1].risky);
        compare(perms.map(p => p.icon), ["world", "file-folder", "speaker"]);
        compare(b.describePermissions(null), []);
    }

    function test_installStartsJob() {
        const b = makeBackend();
        b.appstreamCache = {
            "org.gnome.Maps": {
                "name": "GNOME Maps"
            }
        };
        b.installApp("org.gnome.Maps");
        compare(b.opened, ["marathon-store://install/org.gnome.Maps?name=GNOME%20Maps"]);
        compare(b.jobFor("org.gnome.Maps").state, "pending");
        compare(b.activeJobId, "org.gnome.Maps");
        b.uninstallApp("org.gnome.Maps");
        compare(b.jobFor("org.gnome.Maps").state, "removing");
        compare(b.opened[1], "marathon-store://uninstall/org.gnome.Maps");
        b.openApp("org.gnome.Maps");
        compare(b.opened[2], "marathon-store://open/org.gnome.Maps");
    }

    function test_installedAndUpdatesFromState() {
        const b = makeBackend();
        b.loadInstalled();
        b.loadUpdates();
        tryVerify(() => b.installedApps.length === 2);
        tryVerify(() => b.pendingUpdates.length === 1);
        verify(b.isInstalled("org.gnome.Maps"));
        verify(!b.isInstalled("org.example.Nope"));
        verify(b.hasUpdate("org.example.Old"));
        compare(b.updateApps[0].name, "Old Thing");
        compare(b.nameOf("org.gnome.Maps"), "Maps");
    }

    function test_finishedJobReported() {
        const b = makeBackend();
        b.installApp("org.example.Done");
        tryCompare(finishedSpy, "count", 1, 3000);
        compare(finishedSpy.signalArguments[0][0], "org.example.Done");
        compare(finishedSpy.signalArguments[0][1], "install");
        compare(finishedSpy.signalArguments[0][2].state, "done");
        verify(b.isInstalled("org.example.Done"));
        compare(b.activeJobId, "");
    }

    function test_failedJobExplained() {
        const b = makeBackend();
        b.updateApp("org.example.Fail");
        tryCompare(finishedSpy, "count", 1, 3000);
        compare(finishedSpy.signalArguments[0][1], "update");
        compare(b.jobError(b.jobFor("org.example.Fail")), "Not enough storage space on this phone.");
        compare(b.jobError({ "error": "error: No remote refs found for 'x'" }), "Flathub doesn't have this app for this phone any more.");
        compare(b.jobError({ "error": "GPG verification enabled, but no signatures found" }), "The download couldn't be verified. Try again later.");
        compare(b.jobError({ "error": "weird thing 0x42" }), "Couldn't finish. Try again later.");
        compare(b.jobError(null), "Couldn't finish. Try again later.");
    }

    function test_updateAllMarksEveryUpdate() {
        const b = makeBackend();
        b.pendingUpdates = [{ "app_id": "org.example.A" }, { "app_id": "org.example.B" }];
        b.updateAll();
        compare(b.opened, ["marathon-store://update-all/x"]);
        compare(b.jobFor("org.example.A").state, "pending");
        compare(b.jobFor("org.example.B").state, "pending");
    }

    function test_cancelStopsTheJob() {
        const b = makeBackend();
        b.installApp("org.example.Cancelled");
        b.cancelJob("org.example.Cancelled");
        compare(b.opened[1], "marathon-store://cancel/org.example.Cancelled");
        compare(b.jobFor("org.example.Cancelled").state, "cancelling");
        compare(b.activeJobId, "org.example.Cancelled");
        tryCompare(finishedSpy, "count", 1, 3000);
        compare(finishedSpy.signalArguments[0][2].state, "cancelled");
        verify(!b.isInstalled("org.example.Cancelled"));
        compare(b.activeJobId, "");
    }

    function test_onlyRunningInstallsCancel() {
        const b = makeBackend();
        b.cancelJob("org.gnome.Maps");
        b.uninstallApp("org.gnome.Maps");
        b.cancelJob("org.gnome.Maps");
        compare(b.opened, ["marathon-store://uninstall/org.gnome.Maps"]);
        compare(b.jobFor("org.gnome.Maps").state, "removing");
    }

    function test_cancellingIgnoresStaleProgress() {
        const b = makeBackend();
        b.stateDir = Qt.resolvedUrl("data/resume").toString().replace("file://", "");
        b.installApp("org.example.Late");
        b.cancelJob("org.example.Late");
        wait(1000);
        compare(b.jobFor("org.example.Late").state, "cancelling");
    }

    function test_silentHelperFailsTheJob() {
        const b = makeBackend();
        b.helperTimeout = 0;
        b.installApp("org.example.Nobody");
        tryCompare(finishedSpy, "count", 1, 3000);
        compare(b.jobFor("org.example.Nobody").state, "failed");
        compare(b.jobError(b.jobFor("org.example.Nobody")), "The Store helper didn't respond. Try again.");
    }

    function test_reopenedStoreResumesRunningJobs() {
        const b = makeBackend();
        b.stateDir = Qt.resolvedUrl("data/resume").toString().replace("file://", "");
        tryVerify(() => b.jobFor("org.example.Busy") !== null, 3000);
        compare(b.jobFor("org.example.Busy").percent, 40);
        compare(b._verbs["org.example.Busy"], "update");
        verify(b.jobFor("org.example.Late") !== null);
        compare(b.jobFor("org.example.Stale"), null);
        compare(b.jobFor("org.example.Gone"), null);
    }

    function test_catalogSurvivesGoingOffline() {
        const first = makeBackend();
        first.collections = Fixtures.collections();
        first.saveCatalog();
        tryVerify(() => first._cache.value("catalog", "") !== "", 2000);
        first.saveJson("list/collection/mobile", { "ts": 1000, "apps": [{ "app_id": "org.example.M1" }] });
        const b = createTemporaryObject(backendComponent, testCase, { "cacheFile": first.cacheFile });
        b.loadCatalog();
        compare(b.catalogAppCount, 12);
        verify(b.catalogSavedAt > 0);
        tryCompare(b, "catalogLoading", false, 10000);
        compare(b.catalogAppCount, 12);
        verify(b.showingSavedCatalog);
        let got = null;
        b.loadList("collection/mobile", (list, err, savedAt) => got = { list, err, savedAt });
        tryVerify(() => got !== null, 10000);
        compare(got.list.map(a => a.app_id), ["org.example.M1"]);
        verify(got.err !== "");
        compare(got.savedAt, 1000);
    }

    // Flathub's flag, the handler's index and an /appstream entry's
    // relations each make an app a phone app; Android apps always are.
    function test_phoneFilter() {
        const b = makeBackend();
        b.phoneOnly = true;
        b.phoneApps = { "org.example.Indexed": true };
        const list = [
            { "app_id": "org.example.Flagged", "isMobileFriendly": true },
            { "app_id": "org.example.Desktop", "isMobileFriendly": false },
            { "app_id": "org.example.Indexed" },
            { "app_id": "org.example.Unknown" },
            { "app_id": "org.example.Relations", "requires": [{ "type": "display_length", "value": "360" }], "supports": [{ "type": "control", "value": "touch" }] },
            { "app_id": "android:org.example.clock", "antiFeatures": [] }
        ];
        compare(b.shown(list).map(a => a.app_id), ["org.example.Flagged", "org.example.Indexed", "org.example.Relations", "android:org.example.clock"]);
        compare(b.hiddenCount(list), 2);
        compare(b.shown(list, true).length, 6);
        b.phoneOnly = false;
        compare(b.shown(list).length, 6);
        compare(b.hiddenCount(list), 0);
    }

    function test_relationsAsTheHandlerReadsThem() {
        const b = makeBackend();
        const touch = { "type": "control", "value": "touch" };
        verify(b.relationsFit({ "recommends": [{ "type": "display_length", "value": "300" }, touch] }));
        verify(!b.relationsFit({ "requires": [{ "type": "display_length", "value": "768" }], "recommends": [{ "type": "display_length", "compare": "le", "value": "1200" }, touch] }));
        verify(!b.relationsFit({ "requires": [{ "type": "display_length", "compare": "gt", "value": "360" }], "recommends": [touch] }));
        verify(!b.relationsFit({ "recommends": [{ "type": "display_length", "value": "360" }] }));
        verify(!b.relationsFit({ "requires": [{ "type": "display_length", "side": "longest", "value": "360" }], "recommends": [touch] }));
        verify(!b.relationsFit({}));
    }

    function test_heroAndSectionsFollowTheFilter() {
        const b = makeBackend();
        b.collections = Fixtures.collections();
        b.phoneOnly = true;
        compare(b.trendingApps, []);
        b.phoneApps = { "org.example.T2": true, "org.example.P1": true };
        compare(b.trendingApps.map(a => a.app_id), ["org.example.T2"]);
        compare(b.heroApp.app_id, "org.example.P1");
    }

    function test_sourcesAndAntiFeatures() {
        const b = makeBackend();
        const list = [
            { "app_id": "org.example.Flathub", "isMobileFriendly": true },
            { "app_id": "android:org.example.clean", "antiFeatures": [] },
            { "app_id": "android:org.example.ads", "antiFeatures": ["Ads"] }
        ];
        compare(b.shown(list).length, 3);
        b.storeSettings = Object.assign({}, b.defaultSettings, { "antiFeatures": false });
        compare(b.shown(list).map(a => a.app_id), ["org.example.Flathub", "android:org.example.clean"]);
        b.storeSettings = Object.assign({}, b.defaultSettings, { "fdroid": false });
        compare(b.shown(list).map(a => a.app_id), ["org.example.Flathub"]);
        b.storeSettings = Object.assign({}, b.defaultSettings, { "flathub": false });
        compare(b.shown(list).map(a => a.app_id), ["android:org.example.clean", "android:org.example.ads"]);
        let got = null;
        b.searchApps("clock", (hits, err) => got = hits);
        verify(got !== null);
    }

    function test_settingsAndIndexFromTheHandler() {
        const b = makeBackend();
        b.loadStoreSettings();
        tryVerify(() => b.storeSettings.updateOnMetered === true);
        compare(b.storeSettings.autoUpdate, false);
        compare(b.storeSettings.fdroid, true);
        tryVerify(() => b.phoneApps["org.example.Indexed"] === true);
    }

    function test_compatibility() {
        const b = makeBackend();
        // Before Android answered: only what the .apk alone shows.
        compare(b.compatibility({ "abis": ["armeabi-v7a", "x86"], "minSdk": 21, "features": ["android.hardware.nfc"] }),
                [{ "severity": "block", "text": "Has no code for this phone's processor (only armeabi-v7a, x86)" }]);
        compare(b.compatibility({ "abis": ["arm64-v8a"], "minSdk": 34 }), [{ "severity": "block", "text": "Needs Android 14 or newer" }]);
        b.androidDevice = { "features": ["android.hardware.camera", "android.hardware.wifi"], "libraries": ["org.apache.http.legacy"], "abis": ["arm64-v8a"], "sdk": 33, "gms": false };
        const issues = b.compatibility({
            "features": ["android.hardware.telephony", "android.hardware.telephony.gsm", "android.hardware.camera", "android.hardware.nfc", "com.example.thing"],
            "libraries": ["com.google.android.maps", "org.apache.http.legacy"],
            "gms": true,
            "abis": [],
            "minSdk": 26
        });
        compare(issues.map(i => i.severity + ": " + i.text), [
            "block: Needs Google Maps, which this phone doesn't have",
            "warn: Needs Google Play services, so it may not work",
            "warn: Needs a phone radio",
            "warn: Needs NFC",
            "warn: Needs com.example.thing, which this phone doesn't have"
        ]);
        compare(b.compatibility({ "features": [], "antiFeatures": ["NonFreeDep"] }).map(i => i.severity), ["warn"]);
        compare(b.compatibility({ "features": ["android.hardware.camera"], "abis": ["arm64-v8a", "armeabi-v7a"] }), []);
        compare(b.catalogueNeeds({ "antiFeatures": ["Ads"], "version": { "minSdk": 21, "features": ["android.hardware.nfc"] } }),
                { "features": ["android.hardware.nfc"], "minSdk": 21, "antiFeatures": ["Ads"] });
    }

    function test_slimKeepsListFields() {
        const b = makeBackend();
        compare(b.slim({ "app_id": "a.b.C", "name": "C", "description": "long", "screenshots": [], "isMobileFriendly": true }), { "app_id": "a.b.C", "name": "C", "isMobileFriendly": true });
    }

    function test_cachedLookupsSkipTheNetwork() {
        const b = makeBackend();
        const cache = {};
        cache["org.gnome.Maps"] = Fixtures.fullApp("org.gnome.Maps");
        b.appstreamCache = cache;
        let got = null;
        b.loadAppstream("org.gnome.Maps", full => got = full);
        compare(got.name, "Maps");
        compare(b.categoryLabel(got), "Utilities");
        verify(b.isVerified(got));
        const rows = b.infoRows(got, Fixtures.summary());
        compare(rows.map(r => r.label), ["Developer", "Version", "Updated", "Installed size", "License"]);
    }

    function test_offlineCatalogEndsLoading() {
        const b = makeBackend();
        b.loadCatalog();
        verify(b.catalogLoading);
        tryCompare(b, "catalogLoading", false, 10000);
        compare(b.catalogAppCount, 0);
        verify(b.lastError !== "");
    }

    function loadAndroid(b) {
        b.loadAndroidCatalog(false);
        tryVerify(() => b.androidApps.length === 2);
    }

    function test_androidCatalogue() {
        const b = makeBackend();
        loadAndroid(b);
        verify(b.isValidRef("android:org.example.clock"));
        verify(!b.isValidRef("android:../etc"));
        compare(b.nameOf("android:org.example.clock"), "Tick");
        compare(b.recentAndroid(5).map(a => a.pkg), ["org.example.game", "org.example.clock"]);
        compare(b.searchAndroid("clock", 10).map(a => a.pkg), ["org.example.clock"]);
        compare(b.searchAndroid("roll", 10).map(a => a.pkg), ["org.example.game"]);
        compare(b.androidInCategory("game").map(a => a.pkg), ["org.example.game"]);
        compare(b.iconFor(b.androidApp("android:org.example.clock")), "https://f-droid.org/repo/org.example.clock/en-US/icon.png");
        compare(b.iconFor(b.androidApp("android:org.example.game")), "");
        compare(b.describeAndroidPermissions(b.androidApp("android:org.example.clock").version.permissions), ["Use the internet", "Use the camera"]);
    }

    function test_androidInstallGoesToTheHandler() {
        const b = makeBackend();
        loadAndroid(b);
        b.installApp("android:org.example.clock");
        compare(b.opened[b.opened.length - 1], "marathon-store://install/android:org.example.clock?name=Tick");
        b.openApp("android:org.example.clock");
        compare(b.opened[b.opened.length - 1], "marathon-store://open/waydroid.org.example.clock");
        b.installApk("/home/user/Downloads/a b.apk", "org.example.clock", "Tick");
        compare(b.opened[b.opened.length - 1], "marathon-store://apk-install/%2Fhome%2Fuser%2FDownloads%2Fa%20b.apk?pkg=org.example.clock&name=Tick");
        compare(b.jobFor("android:org.example.clock").state, "pending");
    }
}
