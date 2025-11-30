pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    id: platform

    readonly property string os: Qt.platform.os
    readonly property bool isLinux: os === "linux"
    readonly property bool isMacOS: os === "osx"
    readonly property bool isAndroid: os === "android"
    readonly property bool isIOS: os === "ios"

    readonly property bool hasDBus: isLinux || isAndroid
    readonly property bool hasSystemdLogind: isLinux
    readonly property bool hasUPower: isLinux
    readonly property bool hasNetworkManager: isLinux
    readonly property bool hasModemManager: isLinux
    readonly property bool hasPulseAudio: isLinux

    // Hardware keyboard detection (via C++ Platform backend)
    readonly property bool hasHardwareKeyboard: typeof PlatformCpp !== 'undefined' ? PlatformCpp.hasHardwareKeyboard : true  // Default to true for safety

    readonly property string backend: {
        if (isLinux)
            return "linux";
        if (isMacOS)
            return "macos";
        if (isAndroid)
            return "android";
        if (isIOS)
            return "ios";
        return "unknown";
    }

    Component.onCompleted: {
        Logger.info("Platform", "Detected OS: " + os);
        Logger.info("Platform", "Backend: " + backend);
        Logger.info("Platform", "D-Bus available: " + hasDBus);
        Logger.info("Platform", "Hardware keyboard: " + hasHardwareKeyboard);
    }
}
