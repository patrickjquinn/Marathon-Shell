pragma Singleton
import QtQuick

QtObject {
    id: logger

    enum Level {
        DEBUG = 0,
        INFO = 1,
        WARN = 2,
        ERROR = 3
    }

    readonly property bool _debugMode: typeof Constants !== "undefined" && Constants ? Constants.debugMode : false
    property int currentLevel: _debugMode ? 0 : 2

    function debug(component, message) {
        if (currentLevel <= 0 && _debugMode)
            console.log("[DEBUG]", component + ":", message);
    }

    function info(component, message) {
        if (currentLevel <= 1 && _debugMode)
            console.log("[INFO]", component + ":", message);
    }

    function warn(component, message) {
        if (currentLevel <= 2)
            console.warn("[WARN]", component + ":", message);
    }

    function error(component, message) {
        if (currentLevel <= 3)
            console.error("[ERROR]", component + ":", message);
    }

    function gesture(component, action, data) {
        if (currentLevel <= 0 && _debugMode)
            console.log("[GESTURE]", component + ":", action, JSON.stringify(data || {}));
    }

    function state(component, from, to) {
        if (currentLevel <= 0 && _debugMode)
            console.log("[STATE]", component + ":", from, "→", to);
    }

    function nav(from, to, method) {
        if (currentLevel <= 0 && _debugMode)
            console.log("[NAV]", from, "→", to, "(" + method + ")");
    }
}
