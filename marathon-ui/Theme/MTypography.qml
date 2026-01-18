pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {

    readonly property string fontFamily: "Slate"
    readonly property string fontFamilyMono: "JetBrains Mono"
    readonly property string fontMonospace: fontFamilyMono

    readonly property int sizeXSmall: Math.round(12 * (Constants.scaleFactor || 1.0))
    readonly property int sizeSmall: Math.round(14 * (Constants.scaleFactor || 1.0))
    readonly property int sizeBody: Math.round(16 * (Constants.scaleFactor || 1.0))
    readonly property int sizeLarge: Math.round(18 * (Constants.scaleFactor || 1.0))
    readonly property int sizeXLarge: Math.round(24 * (Constants.scaleFactor || 1.0))
    readonly property int sizeXXLarge: Math.round(32 * (Constants.scaleFactor || 1.0))
    readonly property int sizeDisplay: Math.round(40 * (Constants.scaleFactor || 1.0))
    readonly property int sizeHuge: Math.round(48 * (Constants.scaleFactor || 1.0))
    readonly property int sizeGigantic: Math.round(96 * (Constants.scaleFactor || 1.0))

    readonly property int weightLight: Font.Light
    readonly property int weightRegular: Font.Normal
    readonly property int weightNormal: Font.Normal
    readonly property int weightMedium: Font.Medium
    readonly property int weightDemiBold: Font.DemiBold
    readonly property int weightBold: Font.Bold
    readonly property int weightBlack: Font.Black
}
