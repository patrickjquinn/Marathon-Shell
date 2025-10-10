pragma Singleton
import QtQuick

QtObject {
    readonly property real designUnitScale: 9
    function du(value) { return value * designUnitScale }
    
    readonly property real paddingSmall: du(1)
    readonly property real paddingMedium: du(2)
    readonly property real paddingLarge: du(3)
    
    readonly property real statusBarHeight: du(7)
    readonly property real iconSize: du(12)
    readonly property real activeFrameSize: 180
    readonly property real hubWidth: 350
    
    readonly property int durationFast: 150
    readonly property int durationMedium: 250
    readonly property int durationSlow: 350
    readonly property int easingStandard: Easing.OutCubic
    readonly property int easingOvershoot: Easing.OutBack
    
    readonly property real peekThreshold: du(8)
    readonly property real commitThreshold: du(30)
    readonly property real edgeGestureWidth: du(4)
}

