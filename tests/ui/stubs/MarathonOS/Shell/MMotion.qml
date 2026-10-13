pragma Singleton
import QtQml
QtObject {
    readonly property int quick: 0
    readonly property int fast: 0
    readonly property int moderate: 0
    readonly property var easingDecelerateCurve: [0, 0, 0.2, 1]
    property bool reduceMotion: false
    readonly property int staggerMicro: 0
    function durationFor(role) { return 0; }
    function easingFor(role) { return 0; }
}
