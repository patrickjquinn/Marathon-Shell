pragma Singleton
import QtQml
QtObject {
    property var closed: []
    signal appRegistered(string appId, var instance)
    signal appUnregistered(string appId)
    function launchAppWithRoute() {}
    function closeApp(appId) { closed = closed.concat([appId]); }
    function getAppInstance(appId) { return null; }
}
