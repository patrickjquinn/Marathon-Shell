import QtQuick
import QtQuick.Controls
import MarathonUI.Theme

// MStackView — Marathon's StackView with native-feeling push/pop
// transitions baked in.
//
// The Qt default StackView transition is a 200 ms crossfade. It reads
// as "the OS reloaded a page," not "I navigated." This wrapper ships
// the canonical Marathon page push: the incoming page slides in from
// the right, the outgoing page slides slightly left with a subtle
// parallax (30%) and a 4% scale-down, both running on the "nav" role
// from MMotion. Pop reverses the curve.
//
// Why a wrapper rather than per-app override: every page transition in
// the system should feel the same. One curve, one duration, one
// parallax magnitude, one place to tune.
//
// Drop-in: replace `StackView { ... }` with `MStackView { ... }`. All
// other StackView API is preserved (pushEnter/pushExit can still be
// overridden by the caller).
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

    // Subtle scale-down on the outgoing page. Reads as depth.
    property real outgoingScale: MMotion.pageScaleOut

    pushEnter: Transition {
        ParallelAnimation {
            NumberAnimation {
                property: "x"
                from: stack.travel
                to: 0
                duration: MMotion.durationFor("nav")
                easing.type: Easing.Bezier
                easing.bezierCurve: MMotion.easingCurveFor("nav")
            }
            NumberAnimation {
                property: "opacity"
                from: 0
                to: 1
                duration: MMotion.durationFor("nav")
                easing.type: Easing.OutQuad
            }
        }
    }

    pushExit: Transition {
        ParallelAnimation {
            NumberAnimation {
                property: "x"
                from: 0
                to: -stack.travel * stack.parallax
                duration: MMotion.durationFor("nav")
                easing.type: Easing.Bezier
                easing.bezierCurve: MMotion.easingCurveFor("nav")
            }
            NumberAnimation {
                property: "scale"
                from: 1
                to: stack.outgoingScale
                duration: MMotion.durationFor("nav")
                easing.type: Easing.Bezier
                easing.bezierCurve: MMotion.easingCurveFor("nav")
            }
        }
    }

    popEnter: Transition {
        ParallelAnimation {
            NumberAnimation {
                property: "x"
                from: -stack.travel * stack.parallax
                to: 0
                duration: MMotion.durationFor("nav")
                easing.type: Easing.Bezier
                easing.bezierCurve: MMotion.easingCurveFor("nav")
            }
            NumberAnimation {
                property: "scale"
                from: stack.outgoingScale
                to: 1
                duration: MMotion.durationFor("nav")
                easing.type: Easing.Bezier
                easing.bezierCurve: MMotion.easingCurveFor("nav")
            }
        }
    }

    popExit: Transition {
        ParallelAnimation {
            NumberAnimation {
                property: "x"
                from: 0
                to: stack.travel
                duration: MMotion.durationFor("nav")
                easing.type: Easing.Bezier
                easing.bezierCurve: MMotion.easingCurveFor("nav")
            }
            NumberAnimation {
                property: "opacity"
                from: 1
                to: 0
                duration: MMotion.durationFor("nav")
                easing.type: Easing.InQuad
            }
        }
    }
}
