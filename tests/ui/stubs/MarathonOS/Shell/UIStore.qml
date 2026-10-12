pragma Singleton
import QtQml
QtObject {
    property var opened: []
    function openApp(appId, name, icon) { opened = opened.concat([appId]); }
}
