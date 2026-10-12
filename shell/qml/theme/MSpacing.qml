pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {

    readonly property int xs: Math.round(4 * (Constants.scaleFactor || 1.0))
    readonly property int sm: Math.round(8 * (Constants.scaleFactor || 1.0))
    readonly property int md: Math.round(16 * (Constants.scaleFactor || 1.0))
    readonly property int lg: Math.round(24 * (Constants.scaleFactor || 1.0))
    readonly property int xl: Math.round(32 * (Constants.scaleFactor || 1.0))
    readonly property int xxl: Math.round(40 * (Constants.scaleFactor || 1.0))
}
