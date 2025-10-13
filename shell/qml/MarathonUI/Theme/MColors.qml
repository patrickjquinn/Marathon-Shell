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
    readonly property color textDisabled: "#555555"
    
    readonly property color border: "#333333"
    readonly property color borderLight: "#2A2A2A"
    readonly property color borderFocus: accent
    
    readonly property color success: "#00c853"
    readonly property color warning: "#ffc107"
    readonly property color error: "#FF3B30"
    readonly property color info: accentLight
    
    readonly property color overlay: Qt.rgba(0, 0, 0, 0.8)
    readonly property color glass: Qt.rgba(255, 255, 255, 0.04)
    readonly property color glassBorder: Qt.rgba(255, 255, 255, 0.12)
}

