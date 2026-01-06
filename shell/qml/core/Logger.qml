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

    // Default to WARN in production; allow full verbosity in debug.
    // This keeps the core experience quiet + fast on low-end devices.
    property int currentLevel: Constants.debugMode ? Logger.Level.DEBUG : Logger.Level.WARN

    function debug(component, message) {
        if (currentLevel <= Logger.Level.DEBUG && Constants.debugMode)
            console.log("[DEBUG]", component + ":", message);
    }

    function info(component, message) {
        if (currentLevel <= Logger.Level.INFO && Constants.debugMode)
            console.log("[INFO]", component + ":", message);
    }

    function warn(component, message) {
        if (currentLevel <= Logger.Level.WARN)
            console.warn("[WARN]", component + ":", message);
    }

    function error(component, message) {
        if (currentLevel <= Logger.Level.ERROR)
            console.error("[ERROR]", component + ":", message);
    }

    function gesture(component, action, data) {
        if (currentLevel <= Logger.Level.DEBUG && Constants.debugMode)
            console.log("[GESTURE]", component + ":", action, JSON.stringify(data || {}));
    }

    function state(component, from, to) {
        if (currentLevel <= Logger.Level.DEBUG && Constants.debugMode)
            console.log("[STATE]", component + ":", from, "→", to);
    }

    function nav(from, to, method) {
        if (currentLevel <= Logger.Level.DEBUG && Constants.debugMode)
            console.log("[NAV]", from, "→", to, "(" + method + ")");
    }
}
