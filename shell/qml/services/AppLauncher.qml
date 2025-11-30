pragma Singleton
import QtQuick

QtObject {
    id: appLauncher

    readonly property bool isWaylandCompositor: false
    readonly property bool canLaunchExternalApps: Platform.isLinux

    signal appSpawned(string appId, int pid)
    signal appFailed(string appId, string error)
    signal appExited(string appId, int exitCode)

    property var processMap: ({})

    function launchDesktopApp(desktopFile) {
        console.log("[AppLauncher] Launching desktop app:", desktopFile);

        if (!Platform.isLinux) {
            console.warn("[AppLauncher] External app launching only supported on Linux");
            appFailed(desktopFile, "Platform not supported");
            return false;
        }

        return _launchViaDBusActivation(desktopFile) || _launchViaExec(desktopFile);
    }

    function launchExecutable(execPath, args) {
        console.log("[AppLauncher] Launching executable:", execPath, args);

        if (!Platform.isLinux) {
            console.warn("[AppLauncher] Process spawning only supported on Linux");
            return false;
        }

        return _spawnProcess(execPath, args);
    }

    function terminateApp(appId) {
        console.log("[AppLauncher] Terminating app:", appId);

        if (processMap[appId]) {
            var pid = processMap[appId];
            _killProcess(pid);
            delete processMap[appId];
            appExited(appId, -1);
        }
    }

    function _launchViaDBusActivation(desktopFile) {
        console.log("[AppLauncher] Attempting D-Bus activation for:", desktopFile);
        return false;
    }

    function _launchViaExec(desktopFile) {
        console.log("[AppLauncher] Parsing desktop file:", desktopFile);
        return false;
    }

    function _spawnProcess(execPath, args) {
        console.log("[AppLauncher] Spawning process:", execPath);
        return false;
    }

    function _killProcess(pid) {
        console.log("[AppLauncher] Killing process:", pid);
    }
}
