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

    // ── Stiffness ladder · M3 Expressive 4-rung ──────────────
    // M3 Expressive ships a 4-step stiffness ladder
    // (HIGH/MEDIUM/LOW/VERY_LOW) so motion feels physical rather
    // than duration-driven. Qt's SpringAnimation `spring` property
    // is acceleration-flavoured (m/s²), NOT a Hookean N/m, so
    // these constants are calibrated values, not the M3E
    // 10000/1500/200/50 numbers transliterated verbatim. Mapping:
    //
    //   High    → snap, micro-press, instant settles
    //   Medium  → standard tap / hover / chip toggle (default)
    //   Low     → drawers, sheets, panel pulls
    //   VeryLow → hero, page-level grand transitions
    readonly property real stiffnessHigh: 4.0
    readonly property real stiffnessMedium: 2.0
    readonly property real stiffnessLow: 1.0
    readonly property real stiffnessVeryLow: 0.5

    // ── Damping ratio · two-family physics ────────────────────
    // Damping semantics follow textbook 2nd-order ODE physics:
    //   Critical (1.0)     no overshoot, shortest settle
    //   Underdamped (0.5)  visible overshoot, springy
    //   Overdamped (1.4)   slow approach, no ring
    //
    // Two motion families per M3 Expressive:
    //   spatial — position, size, rotation. Defaults to underdamped
    //             so spatial motion has the springy "alive" feel.
    //   effects — color, opacity. Defaults to CRITICAL — colour
    //             and opacity must never ring (a button bg that
    //             overshoots to a darker shade looks broken).
    //
    // Qt's `damping` units don't strictly map to the dimensionless
    // ratio (it's also acceleration-flavoured), so these are
    // calibrated for Qt SpringAnimation by feel.
    readonly property real dampingCritical: 1.0
    readonly property real dampingUnderdamped: 0.5
    readonly property real dampingOverdamped: 1.4

    // ── Predictive back gesture spec ──────────────────────────
    // Android's published predictive-back motion is fully tokenised
    // (developer.android.com/design/ui/mobile/guides/patterns/
    // predictive-back). Marathon adopts the same ratios so the
    // page-pop gesture behaves consistently across the shell.
    //
    //   Exit screen scales 100% → 90% as the gesture progresses
    //   Enter screen scales 110% → 100% (subtle overshoot in,
    //     emphasises "the previous screen has been here all along")
    //   Fade-through threshold at 35% of progress: below, exit fully
    //     visible; above, enter fades up over the exit
    //   Shared-element shift uses a per-axis dp formula clamped to
    //     leave a hard 8 dp margin from each screen edge
    //   Easing matches SystemUI's standard curve: (0.1, 0.1, 0, 1)
    readonly property real backExitScaleStart: 1.0
    readonly property real backExitScaleEnd: 0.9
    readonly property real backEnterScaleStart: 1.1
    readonly property real backEnterScaleEnd: 1.0
    readonly property real backFadeThreshold: 0.35
    readonly property real backEdgeClampDp: 8

    readonly property var predictiveBackCurve: [0.1, 0.1, 0.0, 1.0]
    readonly property var pathDecelerateCurve: [0.0, 0.0, 0.0, 1.0]

    // Shared-element shift helpers — return px offset for the
    // entering surface during the gesture's commit phase. The
    // (width/20) - 8 formula matches AndroidX's published spec; the
    // Math.max(0, ...) keeps the shift non-negative on tiny screens
    // (a 160 px window would otherwise return zero anyway).
    function backSharedShiftX(width) {
        return Math.max(0, (width / 20) - backEdgeClampDp);
    }
    function backSharedShiftY(height) {
        return Math.max(0, (height / 20) - backEdgeClampDp);
    }

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

    // ── Reduce blur (translucency) ────────────────────────────
    // Companion to reduceMotion. When true, MGlass short-circuits
    // its ShaderEffectSource + MultiEffect path and renders an
    // opaque chrome surface instead — saves GPU cost on etnaviv
    // GLES2 and is the accessibility affordance Apple shipped as
    // the iOS 26 "Reduce Transparency" toggle. Bind from
    // gsettings org.gnome.desktop.a11y reduce-transparency at
    // shell startup; for now the property is writable from
    // SettingsManager.
    //
    // translucencyLevel is the soft knob (0.0..1.0) Apple exposes
    // as iOS 27's translucency slider. Multiplies blur radius and
    // tint opacity proportionally. At 0.0 it collapses to reduceBlur
    // behaviour. At 1.0 every chrome surface gets its full effect.
    property bool reduceBlur: false
    property real translucencyLevel: 1.0

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
                damping: 0.4,
                spatial: {
                    stiffness: stiffnessHigh,
                    damping: dampingCritical
                },
                effects: {
                    stiffness: stiffnessHigh,
                    damping: dampingCritical
                }
            },
            "press": {
                duration: 80,
                easing: Easing.OutQuad,
                curve: [0.2, 0.8, 0.4, 1.0],
                spring: 3.0,
                damping: dampingCritical,
                spatial: {
                    stiffness: stiffnessHigh,
                    damping: dampingCritical
                },
                effects: {
                    stiffness: stiffnessHigh,
                    damping: dampingCritical
                }
            },
            "tap": {
                duration: 120,
                easing: Easing.OutCubic,
                curve: [0.2, 0, 0.2, 1.0],
                spring: 2.5,
                damping: 0.35,
                spatial: {
                    stiffness: stiffnessMedium,
                    damping: 0.35
                },
                effects: {
                    stiffness: stiffnessMedium,
                    damping: dampingCritical
                }
            },
            "hover": {
                duration: 150,
                easing: Easing.InOutQuad,
                curve: [0.4, 0, 0.6, 1.0],
                spring: 2.0,
                damping: 0.3,
                spatial: {
                    stiffness: stiffnessMedium,
                    damping: 0.3
                },
                effects: {
                    stiffness: stiffnessMedium,
                    damping: dampingCritical
                }
            },
            "nav": {
                duration: 220,
                easing: Easing.Bezier,
                curve: [0.2, 0, 0.0, 1.0],
                spring: 1.8,
                damping: 0.25,
                // Page nav lives at the bottom of the M3E ladder —
                // VeryLow stiffness gives the grand, deliberate feel
                // of an iOS push without the duration-driven cubic.
                spatial: {
                    stiffness: stiffnessVeryLow,
                    damping: 0.25
                },
                effects: {
                    stiffness: stiffnessLow,
                    damping: dampingCritical
                }
            },
            "hero": {
                duration: 320,
                easing: Easing.Bezier,
                curve: [0.2, 0, 0.0, 1.0],
                spring: 1.0,
                damping: 0.18,
                // Hero / page-level transitions. Underdamped so it
                // settles with a hint of overshoot — reads as
                // momentum, not as oscillation (damping 0.18 is one
                // step softer than spatial Underdamped 0.5).
                spatial: {
                    stiffness: stiffnessVeryLow,
                    damping: 0.18
                },
                effects: {
                    stiffness: stiffnessLow,
                    damping: dampingCritical
                }
            },
            "predictiveBack": {
                duration: 220,
                easing: Easing.Bezier,
                curve: [0.1, 0.1, 0.0, 1.0],
                spring: 1.0,
                damping: dampingCritical,
                // Critically damped — the gesture itself supplies the
                // motion, the spring's only job is to settle on
                // commit/cancel without overshoot.
                spatial: {
                    stiffness: stiffnessLow,
                    damping: dampingCritical
                },
                effects: {
                    stiffness: stiffnessLow,
                    damping: dampingCritical
                }
            },
            "modal": {
                duration: 240,
                easing: Easing.Bezier,
                curve: [0.34, 1.2, 0.64, 1.0],
                spring: 1.6,
                damping: 0.22,
                spatial: {
                    stiffness: stiffnessLow,
                    damping: 0.22
                },
                effects: {
                    stiffness: stiffnessLow,
                    damping: dampingCritical
                }
            },
            "panel": {
                duration: 300,
                easing: Easing.Bezier,
                curve: [0, 0, 0.2, 1.0],
                spring: 1.5,
                damping: 0.2,
                spatial: {
                    stiffness: stiffnessLow,
                    damping: 0.2
                },
                effects: {
                    stiffness: stiffnessLow,
                    damping: dampingCritical
                }
            },
            "sheet": {
                duration: 320,
                easing: Easing.Bezier,
                curve: [0, 0, 0.2, 1.0],
                spring: 1.4,
                damping: 0.2,
                spatial: {
                    stiffness: stiffnessLow,
                    damping: 0.2
                },
                effects: {
                    stiffness: stiffnessLow,
                    damping: dampingCritical
                }
            },
            "entrance": {
                duration: 220,
                easing: Easing.Bezier,
                curve: [0, 0, 0.2, 1.0],
                spring: 1.8,
                damping: 0.25,
                spatial: {
                    stiffness: stiffnessLow,
                    damping: 0.25
                },
                effects: {
                    stiffness: stiffnessLow,
                    damping: dampingCritical
                }
            },
            "pulse": {
                duration: 1200,
                easing: Easing.InOutSine,
                curve: [0.4, 0, 0.6, 1.0],
                spring: 1.0,
                damping: 0.15,
                spatial: {
                    stiffness: stiffnessLow,
                    damping: 0.15
                },
                effects: {
                    stiffness: stiffnessLow,
                    damping: dampingCritical
                }
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

    // ── Spatial / effects family accessors (M3 Expressive) ────
    // New call sites should use these in preference to springFor /
    // dampingFor. They split spring physics across the two M3E
    // families so colour/opacity don't ring while position/size do.
    //
    //   SpringAnimation { spring: MMotion.stiffnessSpatialFor("nav")
    //                     damping: MMotion.dampingSpatialFor("nav")
    //                     epsilon: MMotion.epsilon }
    //
    //   ColorAnimation  { duration: MMotion.durationFor("hover") }
    //                     // colour is an effect; keep on duration+ease
    //                     // OR a SpringAnimation with effects damping
    //                     // (no ring).
    //
    // Falls back to the legacy `spring`/`damping` fields if a role
    // hasn't been migrated yet — keeps the table forward-compatible.
    function stiffnessSpatialFor(role) {
        var r = _role(role);
        return r.spatial ? r.spatial.stiffness : r.spring;
    }
    function dampingSpatialFor(role) {
        var r = _role(role);
        return r.spatial ? r.spatial.damping : r.damping;
    }
    function stiffnessEffectsFor(role) {
        var r = _role(role);
        return r.effects ? r.effects.stiffness : r.spring;
    }
    function dampingEffectsFor(role) {
        var r = _role(role);
        return r.effects ? r.effects.damping : dampingCritical;
    }

    // Gate `running:` on an infinite/attention loop. When the user has
    // turned motion off the loop never runs, even if its visibility
    // condition is true. Use it like:
    //   SequentialAnimation { running: MMotion.gate(callOverlay.isRinging); ... }
    function gate(cond) {
        return !reduceMotion && cond;
    }
}
