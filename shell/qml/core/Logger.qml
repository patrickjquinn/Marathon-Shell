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

    // Warnings and errors only, unless MARATHON_DEBUG=1 (main.cpp's context property).
    readonly property bool _debugMode: currentLevel <= 0
    property int currentLevel: typeof MARATHON_DEBUG_ENABLED !== "undefined" && MARATHON_DEBUG_ENABLED ? 0 : 2

    function debug(component: string, message: string): void {
        if (currentLevel <= 0 && _debugMode)
            console.log("[DEBUG]", component + ":", message);
    }

    function info(component: string, message: string): void {
        if (currentLevel <= 1 && _debugMode)
            console.log("[INFO]", component + ":", message);
    }

    function warn(component: string, message: string): void {
        if (currentLevel <= 2)
            console.warn("[WARN]", component + ":", message);
    }

    function error(component: string, message: string): void {
        if (currentLevel <= 3)
            console.error("[ERROR]", component + ":", message);
    }

    function gesture(component: string, action: string, data: var): void {
        if (currentLevel <= 0 && _debugMode)
            console.log("[GESTURE]", component + ":", action, JSON.stringify(data || {}));
    }

    function state(component: string, from: string, to: string): void {
        if (currentLevel <= 0 && _debugMode)
            console.log("[STATE]", component + ":", from, "→", to);
    }

    function nav(from: string, to: string, method: string): void {
        if (currentLevel <= 0 && _debugMode)
            console.log("[NAV]", from, "→", to, "(" + method + ")");
    }
}
