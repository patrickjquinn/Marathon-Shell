pragma Singleton
import QtQml
QtObject {
    property var names: ({})
    property var icons: ({})
    readonly property var apps: Object.keys(names)
    function getAppName(appId) { return names[appId] || appId; }
    function getAppIcon(appId) { return icons[appId] || ""; }
    function getApp(appId) { return names[appId] ? { name: names[appId] } : null; }
}
