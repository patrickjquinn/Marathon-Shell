pragma Singleton
import QtQuick

QtObject {
    id: hapticService
    
    readonly property bool isAvailable: Platform.isLinux || Platform.isAndroid
    
    property bool enabled: true
    
    function light() {
        if (!enabled || !isAvailable) return
        vibrate(10)
    }
    
    function medium() {
        if (!enabled || !isAvailable) return
        vibrate(25)
    }
    
    function heavy() {
        if (!enabled || !isAvailable) return
        vibrate(50)
    }
    
    function pattern(durations) {
        if (!enabled || !isAvailable) return
        console.log("[HapticService] Vibration pattern:", durations)
    }
    
    function vibrate(duration) {
        if (!enabled || !isAvailable) return
        
        console.log("[HapticService] Vibrate:", duration + "ms")
        
        if (Platform.isLinux) {
            _vibrateLinux(duration)
        } else if (Platform.isAndroid) {
            _vibrateAndroid(duration)
        }
    }
    
    function _vibrateLinux(duration) {
        console.log("[HapticService] Linux vibration via /sys/class/leds/vibrator/brightness")
    }
    
    function _vibrateAndroid(duration) {
        console.log("[HapticService] Android vibration via Qt.Vibration")
    }
    
    Component.onCompleted: {
        console.log("[HapticService] Initialized")
        console.log("[HapticService] Haptics available:", isAvailable)
    }
}

