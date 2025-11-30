pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: logger

    enum Level {
        DEBUG = 0,
        INFO = 1,
        WARN = 2,
        ERROR = 3
    }

    // Set to INFO level by default so we can see important logs
    property int currentLevel: Logger.Level.INFO

    function debug(component, message) {
        if (currentLevel <= Logger.Level.DEBUG && Constants.debugMode) {
            console.log("[DEBUG]", component + ":", message);
        }
    }

    function info(component, message) {
        if (currentLevel <= Logger.Level.INFO) {
            console.log("[INFO]", component + ":", message);
        }
    }

    function warn(component, message) {
        if (currentLevel <= Logger.Level.WARN) {
            console.warn("[WARN]", component + ":", message);
        }
    }

    function error(component, message) {
        if (currentLevel <= Logger.Level.ERROR) {
            console.error("[ERROR]", component + ":", message);
        }
    }

    function gesture(component, action, data) {
        if (currentLevel <= Logger.Level.DEBUG && Constants.debugMode) {
            console.log("[GESTURE]", component + ":", action, JSON.stringify(data || {}));
        }
    }

    function state(component, from, to) {
        if (currentLevel <= Logger.Level.INFO) {
            console.log("[STATE]", component + ":", from, "→", to);
        }
    }

    function nav(from, to, method) {
        if (currentLevel <= Logger.Level.INFO) {
            console.log("[NAV]", from, "→", to, "(" + method + ")");
        }
    }
}
