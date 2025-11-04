pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    // Aligned with marathon-config.json borders (BB10-sharp aesthetic) - scaled with Constants.scaleFactor
    readonly property int none: 0       // radiusSharp: 0
    readonly property int sm: Math.round(4 * (Constants.scaleFactor || 1.0))         // radiusSmall: 4
    readonly property int md: Math.round(8 * (Constants.scaleFactor || 1.0))         // radiusMedium: 8
    readonly property int lg: Math.round(12 * (Constants.scaleFactor || 1.0))        // radiusLarge: 12
    readonly property int xl: Math.round(20 * (Constants.scaleFactor || 1.0))        // radiusXLarge: 20
    
    // Special cases (not scaled)
    readonly property int pill: 999
    readonly property int circle: 999
}

