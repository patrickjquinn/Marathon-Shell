pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    readonly property int none: 0
    readonly property int sm: Math.round(2 * (Constants.scaleFactor || 1.0))
    readonly property int md: Math.round(4 * (Constants.scaleFactor || 1.0))
    readonly property int lg: Math.round(6 * (Constants.scaleFactor || 1.0))
    readonly property int xl: Math.round(8 * (Constants.scaleFactor || 1.0))

    readonly property int pill: 999
    readonly property int circle: 999
}
