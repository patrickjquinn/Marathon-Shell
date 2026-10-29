pragma Singleton
import QtQml

QtObject {
    readonly property int micro: 0
    readonly property int quick: 0
    readonly property int fast: 0
    readonly property int moderate: 0
    readonly property int normal: 0
    readonly property var easingDecelerateCurve: [0, 0, 0.2, 1, 1, 1]
    property bool reduceMotion: false
    readonly property int flickDecelerationFast: 8000
    readonly property int tapTimeout: 0
    readonly property real pagerFlickVelocity: 10000
    readonly property int staggerMicro: 0
    readonly property int staggerHome: 100
    function durationFor(role) {
        return 0;
    }
    function gate(running) {
        return running;
    }
    function easingFor(role) {
        return 0;
    }
    function stiffnessSpatialFor(role) {
        return 4;
    }
    function dampingSpatialFor(role) {
        return 0.5;
    }
    readonly property real epsilon: 0.01
}
