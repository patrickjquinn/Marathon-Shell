pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    // Slate font family - loaded via FontLoader in MarathonShell.qml
    readonly property string fontFamily: "Slate"
    
    // Responsive font sizes that scale with Constants.scaleFactor
    // Base sizes: 32, 28, 20, 16, 14, 12, 10
    readonly property int sizeDisplay: Math.round(32 * (Constants.scaleFactor || 1.0))
    readonly property int sizeXLarge: Math.round(28 * (Constants.scaleFactor || 1.0))
    readonly property int sizeLarge: Math.round(20 * (Constants.scaleFactor || 1.0))
    readonly property int sizeBody: Math.round(16 * (Constants.scaleFactor || 1.0))
    readonly property int sizeSmall: Math.round(14 * (Constants.scaleFactor || 1.0))
    readonly property int sizeXSmall: Math.round(12 * (Constants.scaleFactor || 1.0))
    readonly property int sizeTiny: Math.round(10 * (Constants.scaleFactor || 1.0))
    
    // Slate font weights mapped to Qt font weights
    readonly property int weightBlack: Font.Black
    readonly property int weightBold: Font.Bold
    readonly property int weightDemiBold: Font.DemiBold
    readonly property int weightMedium: Font.Medium
    readonly property int weightNormal: Font.Normal
    readonly property int weightLight: Font.Light
}

