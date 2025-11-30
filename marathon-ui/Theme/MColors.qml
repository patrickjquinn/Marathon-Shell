pragma Singleton
import QtQuick

QtObject {
    readonly property color bb10Black: "#040404"
    readonly property color bb10Deep: "#070707"
    readonly property color bb10Surface: "#0d0d0e"
    readonly property color bb10Elevated: "#161718"
    readonly property color bb10Card: "#1a1b1c"

    readonly property color marathonTealDarkest: "#006b5d"
    readonly property color marathonTealDark: "#00897b"
    readonly property color marathonTeal: "#00bfa5"
    readonly property color marathonTealBright: "#1de9b6"
    readonly property color marathonTealGlow: "#5dffdc"

    readonly property color textPrimary: "#f5f5f5"
    readonly property color textSecondary: "#6a6a6a"
    readonly property color textTertiary: "#4a4a4a"
    readonly property color textHint: "#2a2a2a"
    readonly property color textOnAccent: "#ffffff"

    readonly property color glassTitlebar: Qt.rgba(13 / 255, 13 / 255, 14 / 255, 0.72)
    readonly property color glassTabbar: Qt.rgba(16 / 255, 16 / 255, 17 / 255, 0.78)
    readonly property color glassActionbar: Qt.rgba(11 / 255, 11 / 255, 12 / 255, 0.82)
    readonly property color glassHeader: Qt.rgba(18 / 255, 18 / 255, 19 / 255, 0.85)

    readonly property color borderGlass: Qt.rgba(1, 1, 1, 0.08)
    readonly property color borderSubtle: Qt.rgba(1, 1, 1, 0.05)
    readonly property color borderDark: Qt.rgba(0, 0, 0, 0.7)

    readonly property color highlightSubtle: Qt.rgba(1, 1, 1, 0.03)
    readonly property color highlightMedium: Qt.rgba(1, 1, 1, 0.06)

    readonly property color hover: Qt.rgba(1, 1, 1, 0.04)
    readonly property color pressed: Qt.rgba(0, 0, 0, 0.1)
    readonly property color ripple: Qt.rgba(0, 191 / 255, 165 / 255, 0.12)

    readonly property color overlay: Qt.rgba(0, 0, 0, 0.85)
    readonly property color overlayLight: Qt.rgba(0, 0, 0, 0.7)

    readonly property color success: "#10B981"
    readonly property color successDim: "#059669"
    readonly property color warning: "#F59E0B"
    readonly property color warningDim: "#D97706"
    readonly property color error: "#EF4444"
    readonly property color errorDim: "#DC2626"
    readonly property color info: "#3B82F6"
    readonly property color infoDim: "#2563EB"

    readonly property color background: bb10Black
    readonly property color surface: bb10Surface
    readonly property color elevated: bb10Elevated
    readonly property color text: textPrimary
    readonly property color accent: marathonTeal
    readonly property color accentBright: marathonTealBright
    readonly property color accentDark: marathonTealDark
    readonly property color border: borderGlass

    // Pre-computed colors for gradients and effects (used frequently in UI)
    readonly property color marathonTealHoverGradient: Qt.rgba(0, 191 / 255, 165 / 255, 0.03)
    readonly property color marathonTealPressGradient: Qt.rgba(0, 191 / 255, 165 / 255, 0.12)
    readonly property color marathonTealGlowTop: Qt.rgba(0, 191 / 255, 165 / 255, 0.18)
    readonly property color marathonTealGlowMid: Qt.rgba(0, 191 / 255, 165 / 255, 0.10)
    readonly property color marathonTealGlowBottom: Qt.rgba(0, 191 / 255, 165 / 255, 0.02)
    readonly property color marathonTealBorder: Qt.rgba(0, 191 / 255, 165 / 255, 0.35)
    readonly property color marathonTealBorderHover: Qt.rgba(0, 191 / 255, 165 / 255, 0.4)

    // Shadow colors (precomputed for performance)
    readonly property color shadowDefault: Qt.rgba(0, 0, 0, 0.4)
    readonly property color shadowStrong: Qt.rgba(0, 0, 0, 0.6)
    readonly property color shadowHeavy: Qt.rgba(0, 0, 0, 0.7)

    // White overlays (used in gradients)
    readonly property color whiteOverlay02: Qt.rgba(1, 1, 1, 0.02)
    readonly property color whiteOverlay03: Qt.rgba(1, 1, 1, 0.03)
    readonly property color whiteOverlay04: Qt.rgba(1, 1, 1, 0.04)
    readonly property color whiteOverlay05: Qt.rgba(1, 1, 1, 0.05)
    readonly property color whiteOverlay06: Qt.rgba(1, 1, 1, 0.06)
    readonly property color whiteOverlay08: Qt.rgba(1, 1, 1, 0.08)
    readonly property color whiteOverlay10: Qt.rgba(1, 1, 1, 0.10)
    readonly property color whiteOverlay12: Qt.rgba(1, 1, 1, 0.12)
    readonly property color whiteOverlay15: Qt.rgba(1, 1, 1, 0.15)
    readonly property color whiteOverlay30: Qt.rgba(1, 1, 1, 0.30)
    readonly property color whiteOverlay40: Qt.rgba(1, 1, 1, 0.40)

    // Black overlays (used in shadows)
    readonly property color blackOverlay15: Qt.rgba(0, 0, 0, 0.15)
    readonly property color blackOverlay40: Qt.rgba(0, 0, 0, 0.4)
}
