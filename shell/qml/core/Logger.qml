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

    // Default to INFO (1); the shell can flip currentLevel to 0 at boot
    // via SettingsManagerCpp / a CLI flag if verbose logging is desired.
    // Avoid cross-singleton lookup of Constants.debugMode — composite
    // singleton resolution is fragile under qmllint.
    readonly property bool _debugMode: currentLevel <= 0
    property int currentLevel: 2

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
