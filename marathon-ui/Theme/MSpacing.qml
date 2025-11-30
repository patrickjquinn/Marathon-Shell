pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    // Aligned with marathon-config.json spacing system - scaled with Constants.scaleFactor
    readonly property int xs: Math.round(5 * (Constants.scaleFactor || 1.0))       // xsmall: 5
    readonly property int sm: Math.round(10 * (Constants.scaleFactor || 1.0))      // small: 10
    readonly property int md: Math.round(16 * (Constants.scaleFactor || 1.0))      // medium: 16
    readonly property int lg: Math.round(20 * (Constants.scaleFactor || 1.0))      // large: 20
    readonly property int xl: Math.round(32 * (Constants.scaleFactor || 1.0))     // xlarge: 32
    readonly property int xxl: Math.round(40 * (Constants.scaleFactor || 1.0))     // xxlarge: 40

    // Touch targets aligned with marathon-config.json - scaled with Constants.scaleFactor
    readonly property int touchTargetMin: Math.round(45 * (Constants.scaleFactor || 1.0))      // minimum: 45
    readonly property int touchTargetSmall: Math.round(60 * (Constants.scaleFactor || 1.0))    // small: 60
    readonly property int touchTargetMedium: Math.round(70 * (Constants.scaleFactor || 1.0))   // medium: 70
    readonly property int touchTargetLarge: Math.round(90 * (Constants.scaleFactor || 1.0))    // large: 90
}
