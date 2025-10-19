pragma Singleton
import QtQuick

QtObject {
    // =========================================================================
    // BACKGROUND - Pure black foundation
    // =========================================================================
    readonly property color background: "#000000"      // Pure black (OLED-friendly)
    readonly property color backgroundDark: "#000000"  // Consistency
    
    // =========================================================================
    // SURFACE ELEVATION - Dark grey cards with clear hierarchy
    // =========================================================================
    readonly property color surface: "#1A1A1A"         // Default card surface
    readonly property color surface0: "#0A0A0A"        // Sunken (inset fields)
    readonly property color surface1: "#1A1A1A"        // Base cards
    readonly property color surface2: "#242424"        // Raised elements
    readonly property color surface3: "#2E2E2E"        // Modals, sheets
    readonly property color surface4: "#383838"        // Floating menus
    readonly property color surface5: "#424242"        // Highest elevation (tooltips)
    
    // Legacy aliases
    readonly property color surfaceLight: surface2
    readonly property color surfaceDark: surface0
    
    // =========================================================================
    // TEAL ACCENT PALETTE - Dark teal to bright teal
    // =========================================================================
    readonly property color accent: "#14B8A6"          // Primary teal (base)
    readonly property color accentBright: "#2DD4BF"    // Bright teal (highlights, borders)
    readonly property color accentDim: "#0D9488"       // Dark teal (muted)
    readonly property color accentHover: "#0F766E"     // Hover state (darker)
    readonly property color accentPressed: "#0A5F56"   // Pressed state (darkest)
    readonly property color accentLight: "#5EEAD4"     // Light teal (emphasis)
    readonly property color accentDark: "#0D9488"      // Dark teal (borders)
    
    // Accent with opacity (for overlays, backgrounds)
    readonly property color accentSubtle: Qt.rgba(0.078, 0.722, 0.651, 0.1)   // 10% accent
    readonly property color accentGhost: Qt.rgba(0.078, 0.722, 0.651, 0.05)   // 5% accent
    readonly property color accentFaint: Qt.rgba(0.078, 0.722, 0.651, 0.02)   // 2% accent
    
    // =========================================================================
    // TEXT COLORS - High contrast on black
    // =========================================================================
    readonly property color text: "#FFFFFF"            // Primary text (white)
    readonly property color textSecondary: "#A0A0A0"   // Secondary text (light grey)
    readonly property color textTertiary: "#707070"    // Tertiary text (medium grey)
    readonly property color textDisabled: "#404040"    // Disabled text (dark grey)
    readonly property color textOnAccent: "#000000"    // Text on teal (black for contrast)
    
    // =========================================================================
    // BORDER COLORS - Subtle depth through borders
    // =========================================================================
    readonly property color border: "#2A2A2A"          // Default border
    readonly property color borderLight: "#353535"     // Lighter border
    readonly property color borderDark: "#1A1A1A"      // Darker border
    readonly property color borderFocus: accent        // Teal border on focus
    
    // Elevation borders (dual-border depth technique)
    readonly property color borderOuter: "#000000"                // Pure black outer edge
    readonly property color borderInner: Qt.rgba(1, 1, 1, 0.05)   // Subtle white inner highlight
    readonly property color borderHighlight: Qt.rgba(1, 1, 1, 0.08) // Stronger highlight
    readonly property color borderShadow: Qt.rgba(0, 0, 0, 0.6)   // Soft shadow
    
    // =========================================================================
    // SEMANTIC COLORS (with scales)
    // =========================================================================
    
    // Success (green)
    readonly property color success: "#10B981"
    readonly property color successDim: "#059669"
    readonly property color successBright: "#34D399"
    readonly property color successSubtle: Qt.rgba(0.063, 0.725, 0.506, 0.1)
    
    // Warning (amber)
    readonly property color warning: "#F59E0B"
    readonly property color warningDim: "#D97706"
    readonly property color warningBright: "#FBBF24"
    readonly property color warningSubtle: Qt.rgba(0.961, 0.620, 0.043, 0.1)
    
    // Error (red)
    readonly property color error: "#EF4444"
    readonly property color errorDim: "#DC2626"
    readonly property color errorBright: "#F87171"
    readonly property color errorSubtle: Qt.rgba(0.937, 0.267, 0.267, 0.1)
    
    // Info (blue)
    readonly property color info: "#3B82F6"
    readonly property color infoDim: "#2563EB"
    readonly property color infoBright: "#60A5FA"
    readonly property color infoSubtle: Qt.rgba(0.231, 0.510, 0.965, 0.1)
    
    // =========================================================================
    // OVERLAY & GLASS EFFECTS
    // =========================================================================
    readonly property color overlay: Qt.rgba(0, 0, 0, 0.85)        // Modal backdrop (dark)
    readonly property color overlayLight: Qt.rgba(0, 0, 0, 0.7)    // Lighter backdrop
    readonly property color overlayHeavy: Qt.rgba(0, 0, 0, 0.95)   // Heavier backdrop
    
    // Glass effects (minimal, performance-friendly)
    readonly property color glass: Qt.rgba(0.2, 0.2, 0.2, 0.95)       // Darker glass with more opacity (visible on black)
    readonly property color glassLight: Qt.rgba(0.25, 0.25, 0.25, 0.95)  // Lighter glass
    readonly property color glassBorder: Qt.rgba(1, 1, 1, 0.25)           // Glass border (much more visible)
    
    // =========================================================================
    // INTERACTION STATES
    // =========================================================================
    readonly property color hover: Qt.rgba(1, 1, 1, 0.05)      // Hover overlay
    readonly property color pressed: Qt.rgba(0, 0, 0, 0.1)     // Press overlay
    readonly property color focus: Qt.rgba(0.078, 0.722, 0.651, 0.15)  // Focus ring
    
    // =========================================================================
    // SPECIAL EFFECTS
    // =========================================================================
    readonly property color ripple: Qt.rgba(1, 1, 1, 0.12)     // Ripple effect
    readonly property color shimmer: Qt.rgba(1, 1, 1, 0.08)    // Loading shimmer
    readonly property color divider: Qt.rgba(1, 1, 1, 0.06)    // Subtle divider
}

