import QtQuick
import QtQuick.Controls
import MarathonUI.Theme

// MStackView — Marathon's StackView with native-feeling push/pop
// transitions baked in.
//
// The Qt default StackView transition is a 200 ms crossfade. It reads
// as "the OS reloaded a page," not "I navigated." This wrapper ships
// the canonical Marathon drill-in: a clean, decisive iOS-style slide
// with parallax on the outgoing page. One curve, one place to tune.
//
// WHY DURATION-BOUNDED, NOT A RAW SpringAnimation (measured, not assumed):
//   StackView BLOCKS input on the incoming page for its entire `busy`
//   window, and `busy` stays true until the transition's animations
//   *converge*. A raw SpringAnimation on the 0..width (~720 px) `x`
//   converges via a long low-velocity tail: on-device the page arrived
//   in ~1 s but `busy` (a visible probe) stayed lit for ~4-5 s AFTER —
//   the page looked settled yet ignored every tap. This held at Qt's
//   MAX useful stiffness AND at CRITICAL damping — spring frequency
//   scales with sqrt(stiffness), so no in-range value clears the tail.
//   Raw SpringAnimation is simply the wrong tool for a StackView
//   transition. A time-bounded NumberAnimation ends when it says it
//   ends, so `busy` (and the input block) clears with the motion.
//
//   Physical, velocity-responsive spring motion still belongs in the
//   product — in the INTERACTIVE back-swipe gesture (where the finger's
//   release velocity drives the settle) — just not in a discrete,
//   tap-driven page push, where "responds to velocity" is meaningless
//   and "blocks input for 5 s" is unacceptable.
//
// DESIGN NOTES (do not "restore" these — each fixed a real regression):
//   • NO opacity crossfade. Pages stay fully OPAQUE. A fade made both
//     pages translucent mid-slide so you saw one bleeding through the
//     other. The incoming page slides in and covers — that's navigation.
//   • NO scale ladder. The predictive-back scale (exit→0.90) shrank the
//     outgoing page and opened gaps around it ("jacked up"). The scale
//     ladder is for the back GESTURE, not a tap push. Slide + parallax.
//   • Silky decelerate curve ([0.22, 1, 0.36, 1], easeOutQuint) — fast
//     departure, long smooth settle. Reads as momentum without a bounce
//     that, on a full-width slide, would fling the page past its edge.
//
// Drop-in: replace `StackView { ... }` with `MStackView { ... }`.
//
//   Push enter:  x  travel → 0                incoming slides in, opaque
//   Push exit:   x  0 → -travel * parallax    outgoing lags by parallax
//   Pop enter:   x  -travel * parallax → 0     outgoing returns
//   Pop exit:    x  0 → travel                 top page slides back out
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

    // Bounded so StackView.busy — which gates input on the new page —
    // clears the instant the slide ends. Tuned for a decisive drill-in.
    readonly property int navDuration: MMotion.reduceMotion ? MMotion.micro : 280
    // easeOutQuint — silky, momentum-flavoured deceleration, no overshoot
    // (overshoot on a full-width slide flings the page past the edge).
    readonly property var navCurve: [0.22, 1, 0.36, 1]

    pushEnter: Transition {
        NumberAnimation {
            property: "x"
            from: stack.travel
            to: 0
            duration: stack.navDuration
            easing.type: Easing.Bezier
            easing.bezierCurve: stack.navCurve
        }
    }

    pushExit: Transition {
        NumberAnimation {
            property: "x"
            from: 0
            to: -stack.travel * stack.parallax
            duration: stack.navDuration
            easing.type: Easing.Bezier
            easing.bezierCurve: stack.navCurve
        }
    }

    popEnter: Transition {
        NumberAnimation {
            property: "x"
            from: -stack.travel * stack.parallax
            to: 0
            duration: stack.navDuration
            easing.type: Easing.Bezier
            easing.bezierCurve: stack.navCurve
        }
    }

    popExit: Transition {
        NumberAnimation {
            property: "x"
            from: 0
            to: stack.travel
            duration: stack.navDuration
            easing.type: Easing.Bezier
            easing.bezierCurve: stack.navCurve
        }
    }
}
