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
// WHAT MAKES IT FEEL PHYSICAL (the tuning, learned the hard way):
//   A spring released with energy does NOT decelerate from max speed with a
//   long floaty tail — that's what a pure easeOut (e.g. easeOutQuint) gives,
//   and it reads as "mechanical / not physics based." A real damped spring
//   arrives fast and SETTLES with a small overshoot — that settle is the
//   signature the eye reads as "alive."
//
//   So the ARRIVING page (pushEnter / popEnter) uses OutBack with a SMALL,
//   deliberately-tuned overshoot (`settleOvershoot`) — it slides to its
//   target, kisses ~1.5% past, and settles. The LEAVING page stays a clean
//   monotonic decel (no overshoot on the page you're covering up). Duration
//   is bounded and short so StackView.busy — which gates input on the new
//   page — clears the instant the motion ends (no 4-5s spring tail).
//
// DESIGN NOTES (do not "restore" these — each fixed a real regression):
//   • NO opacity crossfade. Pages stay fully OPAQUE. A fade made both
//     pages translucent mid-slide so you saw one bleeding through the
//     other. The incoming page slides in and covers — that's navigation.
//   • NO scale ladder. The predictive-back scale (exit→0.90) shrank the
//     outgoing page and opened gaps around it ("jacked up"). The scale
//     ladder is for the back GESTURE, not a tap push. Slide + parallax.
//   • Overshoot is SMALL (~1.5% of travel) and ONLY on the arriving page.
//     A large position overshoot on a full-width slide flings the page
//     past its edge and reveals a gap — keep `settleOvershoot` low.
//   • A true velocity-handoff spring (MVelocitySpring) belongs in the
//     INTERACTIVE back-swipe GESTURE, where the finger's release velocity
//     drives the settle and there's no StackView.busy gate — not here.
//
// Drop-in: replace `StackView { ... }` with `MStackView { ... }`.
//
//   Push enter:  x  travel → 0                incoming slides in + settles
//   Push exit:   x  0 → -travel * parallax    outgoing lags by parallax
//   Pop enter:   x  -travel * parallax → 0     outgoing returns + settles
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

    // Bounded so StackView.busy clears with the motion. Snappier than the
    // old 280ms — the overshoot settle, not the duration, carries the feel.
    readonly property int navDuration: MMotion.reduceMotion ? MMotion.micro : 235

    // OutBack overshoot amplitude for the ARRIVING page. ~0.26 → the page
    // kisses ~1.5% (~11px @ 720) past target then settles — the spring
    // signature, small enough that the trailing-edge gap is sub-perceptual.
    // reduceMotion kills it entirely (0 = plain decel, no bounce).
    readonly property real settleOvershoot: MMotion.reduceMotion ? 0 : 0.26

    // Clean decelerate for the LEAVING page (never overshoot what you cover).
    readonly property var exitCurve: [0.3, 0.9, 0.25, 1]

    pushEnter: Transition {
        NumberAnimation {
            property: "x"
            from: stack.travel
            to: 0
            duration: stack.navDuration
            easing.type: Easing.OutBack
            easing.overshoot: stack.settleOvershoot
        }
    }

    pushExit: Transition {
        NumberAnimation {
            property: "x"
            from: 0
            to: -stack.travel * stack.parallax
            duration: stack.navDuration
            easing.type: Easing.Bezier
            easing.bezierCurve: stack.exitCurve
        }
    }

    popEnter: Transition {
        NumberAnimation {
            property: "x"
            from: -stack.travel * stack.parallax
            to: 0
            duration: stack.navDuration
            easing.type: Easing.OutBack
            easing.overshoot: stack.settleOvershoot
        }
    }

    popExit: Transition {
        NumberAnimation {
            property: "x"
            from: 0
            to: stack.travel
            duration: stack.navDuration
            easing.type: Easing.Bezier
            easing.bezierCurve: stack.exitCurve
        }
    }
}
