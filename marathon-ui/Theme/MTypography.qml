pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    // Aligned with marathon-config.json typography
    readonly property string fontFamily: "Slate"                 // Shell uses Slate font
    readonly property string fontFamilyMono: "JetBrains Mono"   // Shell uses JetBrains Mono

    // Font sizes aligned with marathon-config.json - scaled with Constants.scaleFactor
    readonly property int sizeXSmall: Math.round(12 * (Constants.scaleFactor || 1.0))     // xsmall: 12
    readonly property int sizeSmall: Math.round(14 * (Constants.scaleFactor || 1.0))      // small: 14
    readonly property int sizeBody: Math.round(16 * (Constants.scaleFactor || 1.0))       // medium: 16
    readonly property int sizeLarge: Math.round(18 * (Constants.scaleFactor || 1.0))      // large: 18
    readonly property int sizeXLarge: Math.round(24 * (Constants.scaleFactor || 1.0))     // xlarge: 24
    readonly property int sizeXXLarge: Math.round(32 * (Constants.scaleFactor || 1.0))    // xxlarge: 32
    readonly property int sizeHuge: Math.round(48 * (Constants.scaleFactor || 1.0))       // huge: 48
    readonly property int sizeGigantic: Math.round(96 * (Constants.scaleFactor || 1.0))   // gigantic: 96 (lock screen clock)

    // Font weights
    readonly property int weightLight: Font.Light
    readonly property int weightNormal: Font.Normal
    readonly property int weightMedium: Font.Medium
    readonly property int weightDemiBold: Font.DemiBold
    readonly property int weightBold: Font.Bold
    readonly property int weightBlack: Font.Black
}
