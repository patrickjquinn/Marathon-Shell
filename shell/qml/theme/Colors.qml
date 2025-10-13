pragma Singleton
import QtQuick

QtObject {
    readonly property color background: "#000000"
    readonly property color backgroundDark: "#0A0A0A"
    readonly property color backgroundBlue: "#1a2840"
    readonly property color surface: "#1A1A1A"
    readonly property color surfaceLight: "#2A2A2A"
    readonly property color surfaceDark: "#0A0A0A"
    readonly property color accent: "#006666"
    readonly property color accentHover: "#004d4d"
    readonly property color accentLight: "#00CCCC"
    readonly property color accentDark: "#004d4d"
    readonly property color text: "#FFFFFF"
    readonly property color textSecondary: "#888888"
    readonly property color textTertiary: "#666666"
    readonly property color border: "#333333"
    readonly property color borderLight: "#2A2A2A"
    readonly property color success: "#00c853"
    readonly property color warning: "#ffc107"
    readonly property color error: "#FF3B30"
    
    readonly property real cornerRadiusSmall: 2
    readonly property real cornerRadiusMedium: 2
    readonly property real cornerRadiusLarge: 4
    readonly property real cornerRadiusCircle: 999
}

