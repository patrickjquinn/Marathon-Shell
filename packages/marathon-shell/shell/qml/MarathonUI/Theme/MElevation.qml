pragma Singleton
import QtQuick

QtObject {
    // Elevation system - uses border-only depth (no shadows for performance)
    // Level 0: Flush with background
    // Level 1: Slightly raised (cards, buttons)
    // Level 2: Raised (modals, popovers)
    // Level 3-5: Higher elevation (tooltips, menus, popovers)
    
    // Surface colors for each elevation level (hardcoded to avoid circular dependency)
    function getSurface(level) {
        switch(level) {
            case 0: return "#09090B"  // surface0
            case 1: return "#18181B"  // surface1
            case 2: return "#27272A"  // surface2
            case 3: return "#3F3F46"  // surface3
            case 4: return "#52525B"  // surface4
            case 5: return "#71717A"  // surface5
            default: return "#18181B"
        }
    }
    
    // Outer border colors (darker for depth)
    function getBorderOuter(level) {
        switch(level) {
            case 0: return Qt.rgba(0, 0, 0, 1.0)
            case 1: return Qt.rgba(0, 0, 0, 1.0)
            case 2: return Qt.rgba(0, 0, 0, 1.0)
            case 3: return Qt.rgba(0, 0, 0, 1.0)
            case 4: return Qt.rgba(0, 0, 0, 1.0)
            case 5: return Qt.rgba(0, 0, 0, 1.0)
            default: return Qt.rgba(0, 0, 0, 1.0)
        }
    }
    
    // Inner border colors (lighter for highlight)
    function getBorderInner(level) {
        switch(level) {
            case 0: return Qt.rgba(1, 1, 1, 0.0)
            case 1: return Qt.rgba(1, 1, 1, 0.03)
            case 2: return Qt.rgba(1, 1, 1, 0.05)
            case 3: return Qt.rgba(1, 1, 1, 0.08)
            case 4: return Qt.rgba(1, 1, 1, 0.10)
            case 5: return Qt.rgba(1, 1, 1, 0.12)
            default: return Qt.rgba(1, 1, 1, 0.08)
        }
    }
    
    // Apply elevation to a Rectangle (convenience function)
    function applyElevation(rect, level) {
        rect.color = getSurface(level)
        rect.border.color = getBorderOuter(level)
    }
}
