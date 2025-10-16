pragma Singleton
import QtQuick

QtObject {
    readonly property color background: "#000000"
    readonly property color backgroundDark: "#0A0A0A"
    readonly property color backgroundBlue: "#1a2840"
    readonly property color surface: "#1A1A1A"
    readonly property color surfaceLight: "#2A2A2A"
    readonly property color surfaceDark: "#0A0A0A"
    readonly property color accent: "#14B8A6"  // BB10-inspired teal - bright enough for contrast
    readonly property color accentHover: "#0F9888"
    readonly property color accentLight: "#5FD4C1"
    readonly property color accentDark: "#0A7A6A"
    readonly property color text: "#FFFFFF"
    readonly property color textSecondary: "#999999"  // Lighter for better readability
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

