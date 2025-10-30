pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    readonly property string fontFamily: Qt.platform.os === "osx" ? 
        ".AppleSystemUIFont" : "Roboto"
    
    // Responsive font sizes that scale with Constants.scaleFactor
    // Base sizes (at 1.0 scale): 28, 20, 16, 14, 12
    readonly property int sizeXLarge: Math.round(28 * (Constants.scaleFactor || 1.0))
    readonly property int sizeLarge: Math.round(20 * (Constants.scaleFactor || 1.0))
    readonly property int sizeBody: Math.round(16 * (Constants.scaleFactor || 1.0))
    readonly property int sizeSmall: Math.round(14 * (Constants.scaleFactor || 1.0))
    readonly property int sizeXSmall: Math.round(12 * (Constants.scaleFactor || 1.0))
    
    readonly property int weightBold: Font.Bold
    readonly property int weightMedium: Font.DemiBold
}

