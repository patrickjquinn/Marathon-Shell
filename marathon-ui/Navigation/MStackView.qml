import QtQuick
import QtQuick.Controls
import MarathonUI.Theme

// MStackView — Marathon's StackView with native-feeling push/pop
// transitions baked in.
//
// The Qt default StackView transition is a 200 ms crossfade. It reads
// as "the OS reloaded a page," not "I navigated." This wrapper ships
// the canonical Marathon page push: spring-driven slide + scale
// following the Android predictive-back ladder (exit 100→90%, enter
// 110→100%) so every push/pop in the system feels physical, not
// duration-driven. One curve, one ladder, one place to tune.
//
// Drop-in: replace `StackView { ... }` with `MStackView { ... }`. All
// other StackView API is preserved; pushEnter/pushExit can still be
// overridden by the caller for one-off transitions (sparingly).
//
// Per the world-class-design audit:
//   Push enter:  x  travel  → 0           spring, mild overshoot
//                scale 1.10 → 1.00        spring, mild overshoot
//                opacity 0  → 1           NumberAnimation, predictiveBack curve
//   Push exit:   x  0 → -travel * parallax spring, mild overshoot
//                scale 1.00 → 0.90        spring, mild overshoot
//   Pop enter:   x  -travel * parallax → 0 spring, CRITICAL (no ring)
//                scale 0.90 → 1.00        spring, CRITICAL
//   Pop exit:    x  0 → travel             spring, CRITICAL
//                scale 1.00 → 1.10        spring, CRITICAL
//                opacity 1 → 0            NumberAnimation, predictiveBack curve
StackView {
    id: stack

    // The width the outgoing/incoming pages translate across. Bound to
    // the stack's own width by default; expose for cases where the
    // stack is wider than the visible viewport (e.g. inside a SwipeView
    // with its own clip).
    property real travel: width

    // How much the OUTGOING page lags the incoming one. 0.3 → outgoing
    // moves 30% of the travel while incoming covers the full distance.
    // iOS uses ~25-30%; we land on MMotion.pageParallaxOffset.
    property real parallax: MMotion.pageParallaxOffset

    // Spring tuning per direction. Push gets mild overshoot so a new
    // page reads as "arriving" (a tiny scale-bounce on settle); pop
    // lands CRITICAL so going back is decisive — no oscillation, no
    // "did it land?" ambiguity.
    property real pushDamping: MMotion.dampingMedium     // 0.25 — mild overshoot
    property real popDamping: MMotion.dampingCritical    // 1.00 — no ring

    pushEnter: Transition {
        ParallelAnimation {
            SpringAnimation {
                property: "x"
                from: stack.travel
                to: 0
                spring: MMotion.stiffnessSpatialFor("nav")
                damping: stack.pushDamping
                epsilon: MMotion.epsilon
                mass: 1.0
            }
            SpringAnimation {
                property: "scale"
                from: MMotion.backEnterScaleStart      // 1.10
                to: MMotion.backEnterScaleEnd          // 1.00
                spring: MMotion.stiffnessSpatialFor("nav")
                damping: stack.pushDamping
                epsilon: MMotion.epsilon
                mass: 1.0
            }
            NumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                duration: MMotion.durationFor("nav")
                easing.type: Easing.Bezier
                easing.bezierCurve: MMotion.predictiveBackCurve
            }
        }
    }

    pushExit: Transition {
        ParallelAnimation {
            SpringAnimation {
                property: "x"
                from: 0
                to: -stack.travel * stack.parallax
                spring: MMotion.stiffnessSpatialFor("nav")
                damping: stack.pushDamping
                epsilon: MMotion.epsilon
                mass: 1.0
            }
            SpringAnimation {
                property: "scale"
                from: MMotion.backExitScaleStart       // 1.00
                to: MMotion.backExitScaleEnd           // 0.90
                spring: MMotion.stiffnessSpatialFor("nav")
                damping: stack.pushDamping
                epsilon: MMotion.epsilon
                mass: 1.0
            }
        }
    }

    popEnter: Transition {
        ParallelAnimation {
            SpringAnimation {
                property: "x"
                from: -stack.travel * stack.parallax
                to: 0
                spring: MMotion.stiffnessSpatialFor("nav")
                damping: stack.popDamping
                epsilon: MMotion.epsilon
                mass: 1.0
            }
            SpringAnimation {
                property: "scale"
                from: MMotion.backExitScaleEnd         // 0.90 — where it was deferred
                to: MMotion.backExitScaleStart         // 1.00
                spring: MMotion.stiffnessSpatialFor("nav")
                damping: stack.popDamping
                epsilon: MMotion.epsilon
                mass: 1.0
            }
        }
    }

    popExit: Transition {
        ParallelAnimation {
            SpringAnimation {
                property: "x"
                from: 0
                to: stack.travel
                spring: MMotion.stiffnessSpatialFor("nav")
                damping: stack.popDamping
                epsilon: MMotion.epsilon
                mass: 1.0
            }
            SpringAnimation {
                property: "scale"
                from: MMotion.backEnterScaleEnd        // 1.00
                to: MMotion.backEnterScaleStart        // 1.10 — recedes to its entry pose
                spring: MMotion.stiffnessSpatialFor("nav")
                damping: stack.popDamping
                epsilon: MMotion.epsilon
                mass: 1.0
            }
            NumberAnimation {
                property: "opacity"
                from: 1
                to: 0
                duration: MMotion.durationFor("nav")
                easing.type: Easing.Bezier
                easing.bezierCurve: MMotion.predictiveBackCurve
            }
        }
    }
}
