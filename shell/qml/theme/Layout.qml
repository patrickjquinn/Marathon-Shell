pragma Singleton
import QtQuick

QtObject {
    function dp(pixels) {
        return pixels * (Math.min(window.width, window.height) / 1440)
    }
    
    function sp(pixels) {
        return pixels * (Math.min(window.width, window.height) / 1440)
    }
    
    readonly property real minTouchTarget: 48
    
    readonly property real paddingSmall: 8
    readonly property real paddingMedium: 16
    readonly property real paddingLarge: 24
    readonly property real paddingXLarge: 32
}

