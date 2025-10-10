pragma Singleton
import QtQuick

QtObject {
    readonly property color background: "#000000"
    readonly property color backgroundDark: "#0a0e1a"
    readonly property color backgroundBlue: "#1a2840"
    readonly property color surface: "#1e2838"
    readonly property color surfaceLight: "#2a3648"
    readonly property color accent: "#006666"
    readonly property color accentHover: "#004d4d"
    readonly property color accentLight: "#008080"
    readonly property color text: "#ffffff"
    readonly property color textSecondary: "#b8b8b8"
    readonly property color textTertiary: "#7a8090"
    readonly property color border: "#3a4658"
    readonly property color success: "#00c853"
    readonly property color warning: "#ffc107"
    readonly property color error: "#ff3b30"
    
    readonly property real cornerRadiusSmall: 6
    readonly property real cornerRadiusMedium: 8
    readonly property real cornerRadiusLarge: 12
}

