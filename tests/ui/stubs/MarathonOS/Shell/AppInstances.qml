pragma Singleton
import QtQml
QtObject {
    function register(appId, instance) {}
    function unregister(appId) {}
    function get(appId) { return null; }
}
