pragma Singleton
import QtQuick

QtObject {
    // Background colors - match Settings app exactly
    readonly property color background: "#000000"      // Pure black
    readonly property color backgroundDark: "#0A0A0A"  // Settings app background
    readonly property color backgroundBlue: "#1a2840"  // Settings app blue
    
    // Surface elevation levels - match Settings app colors
    readonly property color surface: "#1A1A1A"         // Settings app surface
    readonly property color surface0: "#0A0A0A"        // Settings app backgroundDark
    readonly property color surface1: "#1A1A1A"        // Settings app surface
    readonly property color surface2: "#2A2A2A"        // Settings app surfaceLight
    readonly property color surface3: "#333333"        // Settings app border
    readonly property color surface4: "#404040"        // Elevated
    readonly property color surface5: "#4A4A4A"        // Highest elevation
    
    // Legacy surface aliases (for backward compatibility)
    readonly property color surfaceLight: surface2
    readonly property color surfaceDark: surface0
    
    // Teal accent palette - optimized for dark UI with proper contrast
    readonly property color accent: "#14B8A6"          // Primary teal (4.5:1 contrast on black)
    readonly property color accentBright: "#14B8A6"    // Bright teal for borders/highlights
    readonly property color accentDim: "#0D9488"       // Dimmed teal for subtle accents
    readonly property color accentHover: "#0F766E"     // Darker teal for hover states
    readonly property color accentLight: "#2DD4BF"     // Lighter teal for emphasis
    readonly property color accentDark: "#0D9488"      // Dark teal for pressed states
    
    // Text colors - match Settings app exactly
    readonly property color text: "#FFFFFF"            // Settings app text
    readonly property color textSecondary: "#999999"   // Settings app textSecondary
    readonly property color textTertiary: "#666666"    // Settings app textTertiary
    readonly property color textDisabled: "#333333"    // Settings app border
    
    // Border colors - match Settings app exactly
    readonly property color border: "#333333"          // Settings app border
    readonly property color borderLight: "#2A2A2A"     // Settings app borderLight
    readonly property color borderFocus: accent        // Teal border on focus
    
    // Elevation borders (for dual-border depth technique)
    readonly property color borderOuter: "#000000"                // Outer shadow edge (pure black)
    readonly property color borderInner: Qt.rgba(1, 1, 1, 0.05)   // Inner highlight (subtle white)
    readonly property color borderHighlight: Qt.rgba(1, 1, 1, 0.08) // Stronger highlight
    readonly property color borderShadow: Qt.rgba(0, 0, 0, 0.6)   // Soft shadow
    
    readonly property color success: "#00c853"
    readonly property color warning: "#ffc107"
    readonly property color error: "#FF3B30"
    readonly property color info: accentLight
    
    readonly property color overlay: Qt.rgba(0, 0, 0, 0.8)
    readonly property color overlayLight: Qt.rgba(0, 0, 0, 0.6)
    readonly property color glass: Qt.rgba(0.05, 0.05, 0.05, 0.97)
    readonly property color glassLight: Qt.rgba(0.08, 0.08, 0.08, 0.98)
    readonly property color glassBorder: Qt.rgba(1, 1, 1, 0.12)
}

