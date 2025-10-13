pragma Singleton
import QtQuick

QtObject {
    readonly property int xs: 4
    readonly property int sm: 8
    readonly property int md: 12
    readonly property int lg: 16
    readonly property int xl: 24
    readonly property int xxl: 32
    readonly property int xxxl: 48
    
    readonly property int touchTargetMin: 45
    readonly property int touchTargetSmall: 60
    readonly property int touchTargetMedium: 70
    readonly property int touchTargetLarge: 90
}

