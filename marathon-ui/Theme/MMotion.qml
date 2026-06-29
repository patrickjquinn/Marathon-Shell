pragma Singleton
import QtQuick

QtObject {

    readonly property int instant: 0
    readonly property int fast: 150
    readonly property int normal: 200
    readonly property int slow: 300
    readonly property int slower: 400

    readonly property int xs: fast
    readonly property int sm: normal
    readonly property int md: slow
    readonly property int lg: slower

    readonly property int micro: 80
    readonly property int quick: 160
    readonly property int moderate: 240

    readonly property real springLight: 1.5
    readonly property real springMedium: 2.0
    readonly property real springHeavy: 3.0

    readonly property real dampingLight: 0.15
    readonly property real dampingMedium: 0.25
    readonly property real dampingHeavy: 0.4
    readonly property real epsilon: 0.01

    readonly property int easingStandard: Easing.Bezier
    readonly property var easingStandardCurve: [0.2, 0, 0.2, 1]

    readonly property int easingDecelerate: Easing.Bezier
    readonly property var easingDecelerateCurve: [0, 0, 0.2, 1]

    readonly property int easingAccelerate: Easing.Bezier
    readonly property var easingAccelerateCurve: [0.4, 0, 1, 1]

    readonly property int easingSpring: Easing.Bezier
    readonly property var easingSpringCurve: [0.34, 1.56, 0.64, 1]

    readonly property int staggerMicro: 20
    readonly property int staggerShort: 50
    readonly property int staggerMedium: 80
    readonly property int staggerLong: 120

    readonly property real pageParallaxOffset: 0.3
    readonly property real pageScaleOut: 0.92

    readonly property int rippleDuration: slow
    readonly property real rippleMaxRadius: 2.5
    readonly property real rippleOpacity: 0.12

    readonly property int flickDecelerationFast: 8000
    readonly property int flickVelocityMax: 5000
    readonly property int touchFlickDeceleration: 25000
    readonly property int touchFlickVelocity: 8000

    // ── Reduce motion ─────────────────────────────────────────
    // Bound at app startup from a platform signal:
    //   GNOME Mobile:  gsettings get org.gnome.desktop.interface enable-animations
    //   Plasma Mobile: kdeglobals.KAccessibilityCommon.skipFancyEffects
    // Components MUST go through dur()/ease() so the preference
    // is honoured uniformly. Per CODING_RULES C8 spirit:
    // motion is functional, not decorative — if the user turned
    // it off, the system stays still.
    property bool reduceMotion: false

    function dur(token) {
        return reduceMotion ? micro : token;
    }
    function ease(token) {
        // OutBack (Easing.Bezier-spring) overshoots — feels jarring
        // when motion is reduced. Fall back to a gentle OutQuad.
        return reduceMotion ? Easing.OutQuad : token;
    }

    // ── Role-based motion API ─────────────────────────────────
    // Every microinteraction in Marathon picks one of these roles. The
    // role is the *meaning* of the motion ("a tap settling", "a panel
    // pulling down"), not its raw duration. Components stay readable,
    // and tuning the whole system means editing this table — not 200
    // call sites.
    //
    // Picking the right role:
    //   microPress  · press-down haptic feedback (scale to 0.97). 80ms.
    //   tap         · press-release / press-cancel / chip-toggle. 120ms.
    //   hover       · state colour transition, focus ring fade. 150ms.
    //   nav         · page push / pop in MAppRouter, tab change. 220ms.
    //   modal       · dialog / sheet open / close. 240ms, gentle spring.
    //   panel       · QS shade pull-down, status-bar reveal. 300ms.
    //   sheet       · full-bleed sheet (settings deep page). 320ms.
    //   entrance    · list-item stagger, app-grid first-paint. 220ms.
    //   pulse       · infinite attention loops (chevron, ringing). 1200ms.
    //
    // For every role the table carries: duration, easing token,
    // easing bezier curve (for Easing.Bezier), spring stiffness,
    // and damping. Use durationFor()/easingFor()/easingCurveFor()/
    // springFor()/dampingFor() to read them. dur() and ease() are
    // legacy helpers preserved for compatibility — prefer the role
    // accessors in new code.
    readonly property var roles: ({
            "microPress": {
                duration: 80,
                easing: Easing.OutQuad,
                curve: [0.2, 0.8, 0.4, 1.0],
                spring: 3.0,
                damping: 0.4
            },
            "tap": {
                duration: 120,
                easing: Easing.OutCubic,
                curve: [0.2, 0, 0.2, 1.0],
                spring: 2.5,
                damping: 0.35
            },
            "hover": {
                duration: 150,
                easing: Easing.InOutQuad,
                curve: [0.4, 0, 0.6, 1.0],
                spring: 2.0,
                damping: 0.3
            },
            "nav": {
                duration: 220,
                easing: Easing.Bezier,
                curve: [0.2, 0, 0.0, 1.0],
                spring: 1.8,
                damping: 0.25
            },
            "modal": {
                duration: 240,
                easing: Easing.Bezier,
                curve: [0.34, 1.2, 0.64, 1.0],
                spring: 1.6,
                damping: 0.22
            },
            "panel": {
                duration: 300,
                easing: Easing.Bezier,
                curve: [0, 0, 0.2, 1.0],
                spring: 1.5,
                damping: 0.2
            },
            "sheet": {
                duration: 320,
                easing: Easing.Bezier,
                curve: [0, 0, 0.2, 1.0],
                spring: 1.4,
                damping: 0.2
            },
            "entrance": {
                duration: 220,
                easing: Easing.Bezier,
                curve: [0, 0, 0.2, 1.0],
                spring: 1.8,
                damping: 0.25
            },
            "pulse": {
                duration: 1200,
                easing: Easing.InOutSine,
                curve: [0.4, 0, 0.6, 1.0],
                spring: 1.0,
                damping: 0.15
            }
        })

    function _role(name) {
        var r = roles[name];
        return r ? r : roles["tap"];
    }
    function durationFor(role) {
        return reduceMotion ? micro : _role(role).duration;
    }
    function easingFor(role) {
        return reduceMotion ? Easing.OutQuad : _role(role).easing;
    }
    function easingCurveFor(role) {
        return _role(role).curve;
    }
    function springFor(role) {
        return _role(role).spring;
    }
    function dampingFor(role) {
        return _role(role).damping;
    }

    // Gate `running:` on an infinite/attention loop. When the user has
    // turned motion off the loop never runs, even if its visibility
    // condition is true. Use it like:
    //   SequentialAnimation { running: MMotion.gate(callOverlay.isRinging); ... }
    function gate(cond) {
        return !reduceMotion && cond;
    }
}
