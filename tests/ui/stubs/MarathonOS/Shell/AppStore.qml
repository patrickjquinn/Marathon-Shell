pragma Singleton
import QtQml
QtObject {
    property var names: ({})
    function getAppName(appId) { return names[appId] || appId; }
}
