pragma Singleton
import QtQml

// Mirrors src/AndroidApps: deckardd's answers are set by the tests.
QtObject {
    property bool available: true
    property var runtime: ({})
    property var apps: []
    property var calls: []
    property var details: ({})
    property var access: ({})

    signal appLoaded(string pkg, var app)
    signal appChanged(string pkg)
    signal appRemoved(string pkg)
    signal specialAccessLoaded(string kind, var apps)
    signal done(string pkg, string action)
    signal failed(string pkg, string action, string error)

    function reset() {
        available = true;
        runtime = { state: "running", memoryBytes: 734003200, androidVersion: "13", uptimeSeconds: 7500, startAtLogin: true, hasApps: true };
        apps = [{ pkg: "org.fdroid.fdroid", id: "waydroid.org.fdroid.fdroid", name: "F-Droid", version: "1.20", icon: "" }];
        calls = [];
        details = {
            "org.fdroid.fdroid": {
                pkg: "org.fdroid.fdroid", label: "F-Droid", versionName: "1.20", appBytes: 12582912, dataBytes: 5242880, cacheBytes: 1048576,
                notifications: true, links: false, domains: ["f-droid.org"], battery: "optimized",
                permissions: [{ group: "nearby", granted: true, fixed: false }, { group: "camera", granted: false, fixed: true }]
            }
        };
        access = { install_apps: [{ pkg: "org.fdroid.fdroid", label: "F-Droid", granted: true }] };
    }
    function record(name, args) {
        calls = calls.concat([[name].concat(args)]);
    }
    function refresh() { record("refresh", []); }
    function refreshRuntime() { record("refreshRuntime", []); }
    function start() { record("start", []); }
    function stop() { record("stop", []); }
    function restart() { record("restart", []); }
    function setStartAtLogin(enabled) { record("setStartAtLogin", [enabled]); }
    function resetAndroid() { record("resetAndroid", []); }
    function loadApp(pkg) {
        record("loadApp", [pkg]);
        if (details[pkg])
            appLoaded(pkg, details[pkg]);
    }
    function setPermission(pkg, group, granted) { record("setPermission", [pkg, group, granted]); }
    function setNotifications(pkg, enabled) { record("setNotifications", [pkg, enabled]); }
    function setOpenLinks(pkg, enabled) { record("setOpenLinks", [pkg, enabled]); }
    function setBattery(pkg, mode) { record("setBattery", [pkg, mode]); }
    function forceStop(pkg) { record("forceStop", [pkg]); }
    function clearCache(pkg) { record("clearCache", [pkg]); }
    function clearData(pkg) { record("clearData", [pkg]); }
    function uninstall(pkg) { record("uninstall", [pkg]); }
    function loadSpecialAccess(kind) {
        record("loadSpecialAccess", [kind]);
        specialAccessLoaded(kind, access[kind] || []);
    }
    function setSpecialAccess(kind, pkg, granted) { record("setSpecialAccess", [kind, pkg, granted]); }
}
