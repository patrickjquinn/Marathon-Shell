pragma Singleton
import QtQuick

QtObject {
    // Aligned with marathon-config.json animations (snappy for 60Hz)
    readonly property int instant: 0
    readonly property int fast: 150        // fast: 150
    readonly property int normal: 200      // normal: 200
    readonly property int slow: 300        // slow: 300
    readonly property int slower: 400      // slower: 400 (was durationSlow)

    // Legacy aliases for compatibility
    readonly property int xs: fast
    readonly property int sm: normal
    readonly property int md: slow
    readonly property int lg: slower

    readonly property int micro: 80
    readonly property int quick: 160
    readonly property int moderate: 240

    // Spring physics
    readonly property real springLight: 1.5
    readonly property real springMedium: 2.0
    readonly property real springHeavy: 3.0

    readonly property real dampingLight: 0.15
    readonly property real dampingMedium: 0.25
    readonly property real dampingHeavy: 0.4
    readonly property real epsilon: 0.01

    // Easing curves (BB10-inspired)
    readonly property int easingStandard: Easing.Bezier
    readonly property var easingStandardCurve: [0.2, 0, 0.2, 1]

    readonly property int easingDecelerate: Easing.Bezier
    readonly property var easingDecelerateCurve: [0, 0, 0.2, 1]

    readonly property int easingAccelerate: Easing.Bezier
    readonly property var easingAccelerateCurve: [0.4, 0, 1, 1]

    readonly property int easingSpring: Easing.Bezier
    readonly property var easingSpringCurve: [0.34, 1.56, 0.64, 1]

    // Choreography
    readonly property int staggerMicro: 20
    readonly property int staggerShort: 50
    readonly property int staggerMedium: 80
    readonly property int staggerLong: 120

    // Page transitions
    readonly property real pageParallaxOffset: 0.3
    readonly property real pageScaleOut: 0.92

    // Ripple effect
    readonly property int rippleDuration: slow
    readonly property real rippleMaxRadius: 2.5
    readonly property real rippleOpacity: 0.12

    // Scroll physics (from marathon-config.json)
    readonly property int flickDecelerationFast: 8000
    readonly property int flickVelocityMax: 5000
    readonly property int touchFlickDeceleration: 25000
    readonly property int touchFlickVelocity: 8000
}
