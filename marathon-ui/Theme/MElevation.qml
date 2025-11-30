pragma Singleton
import QtQuick

QtObject {
    // More dramatic elevation steps for better depth perception
    function getSurface(level) {
        switch (level) {
        case 0:
            return "#040404";  // Base/background
        case 1:
            return "#0a0a0b";  // Very subtle lift
        case 2:
            return "#121213";  // Standard surface
        case 3:
            return "#1c1c1d";  // Elevated surface
        case 4:
            return "#282829";  // Higher elevation
        case 5:
            return "#353536";  // Highest elevation
        default:
            return "#121213";
        }
    }

    // Sharper, more defined outer borders
    function getBorderOuter(level) {
        switch (level) {
        case 0:
            return Qt.rgba(0, 0, 0, 0.9);
        case 1:
            return Qt.rgba(0, 0, 0, 1.0);
        case 2:
            return Qt.rgba(0, 0, 0, 1.0);
        case 3:
            return Qt.rgba(0, 0, 0, 0.95);
        case 4:
            return Qt.rgba(0, 0, 0, 0.90);
        case 5:
            return Qt.rgba(0, 0, 0, 0.85);
        default:
            return Qt.rgba(0, 0, 0, 1.0);
        }
    }

    // More visible inner borders for layered effect
    function getBorderInner(level) {
        switch (level) {
        case 0:
            return Qt.rgba(1, 1, 1, 0.0);
        case 1:
            return Qt.rgba(1, 1, 1, 0.04);
        case 2:
            return Qt.rgba(1, 1, 1, 0.06);
        case 3:
            return Qt.rgba(1, 1, 1, 0.09);
        case 4:
            return Qt.rgba(1, 1, 1, 0.12);
        case 5:
            return Qt.rgba(1, 1, 1, 0.15);
        default:
            return Qt.rgba(1, 1, 1, 0.06);
        }
    }
}
