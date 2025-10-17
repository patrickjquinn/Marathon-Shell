pragma Singleton
import QtQuick

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
    
    readonly property string backend: {
        if (isLinux) return "linux"
        if (isMacOS) return "macos"
        if (isAndroid) return "android"
        if (isIOS) return "ios"
        return "unknown"
    }
    
    Component.onCompleted: {
        console.log("[Platform] Detected OS:", os)
        console.log("[Platform] Backend:", backend)
        console.log("[Platform] D-Bus available:", hasDBus)
    }
}

