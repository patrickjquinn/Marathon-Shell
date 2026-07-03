import QtQuick
import MarathonUI.Theme

// MVelocitySpring — a real, velocity-aware spring integrator.
//
// WHY THIS EXISTS: Qt's SpringAnimation cannot do velocity HANDOFF — its
// `velocity` property is a max-speed CAP, not an initial condition — and
// it holds its target the whole ring-down (see MStackView notes). For
// interactive, interruptible motion (a flick that carries its speed into
// the settle, a drag that reverses mid-flight) you need to integrate the
// spring yourself. This is that integrator: a damped harmonic oscillator
// stepped per display frame via FrameAnimation, so it costs NOTHING when
// idle and stops the instant it converges.
//
// PARAMETERISATION follows SwiftUI's `.spring(response:dampingFraction:)`
// — the two knobs that actually map to human perception:
//   response        — the natural period in seconds (~time to "arrive").
//                     Smaller = snappier. 0.35-0.5 for UI.
//   dampingFraction — 0..1. 1.0 = critical (no overshoot, fastest settle);
//                     <1 = a proportional overshoot/bounce; >1 = sluggish.
//                     0.8-0.9 reads as "lively but controlled."
// Converted to physical (k, c) each step, so retuning is intuitive.
//
// USAGE (gesture handoff):
//   During drag:  spring.snap(fingerOffset)      // track finger, no physics
//   On release:   spring.animateTo(target, releaseVelocityPxPerSec)
//   Bind:         someItem.x: spring.value
//   React:        onSettled: ...                 // commit/cancel side-effects
// Retarget mid-flight by calling animateTo() again — velocity is preserved.
QtObject {
    id: spring

    // Live state. Bind your animated property to `value`. `velocity` is
    // readable (and settable, for handoff) in px/s.
    property real value: 0
    property real target: 0
    property real velocity: 0

    // Feel. See header. reduceMotion collapses to an instant snap.
    property real response: 0.42
    property real dampingFraction: 0.82

    // Convergence thresholds (property units). Below both → settled.
    property real restDelta: 0.5        // px from target
    property real restVelocity: 8.0     // px/s

    // Emitted once, when the spring converges and snaps exactly to target.
    signal settled()

    readonly property bool running: _frame.running

    // Track the finger (or any external driver) with no physics: kills any
    // in-flight animation, parks value, zeroes velocity.
    function snap(v) {
        _frame.running = false;
        velocity = 0;
        value = v;
    }

    // Launch (or retarget) the spring toward `t`, injecting initial
    // velocity `v0` (px/s) — THIS is the handoff. Preserves current value.
    function animateTo(t, v0) {
        target = t;
        if (v0 !== undefined)
            velocity = v0;
        if (MMotion.reduceMotion) {
            // Honour reduce-motion: no springy travel, just arrive.
            snap(t);
            settled();
            return;
        }
        if (Math.abs(value - target) < restDelta && Math.abs(velocity) < restVelocity) {
            snap(t);
            settled();
            return;
        }
        _frame.running = true;
    }

    function stop() {
        _frame.running = false;
    }

    // Per-frame integrator. Semi-implicit (symplectic) Euler is stable for
    // springs; we substep so a dropped frame (large dt) can't blow it up.
    property FrameAnimation _frame: FrameAnimation {
        running: false
        onTriggered: {
            var dt = Math.min(frameTime, 0.064);   // cap at ~4 frames
            var omega = 2 * Math.PI / Math.max(0.0001, spring.response);
            var k = omega * omega;                  // stiffness / mass
            var c = 2 * spring.dampingFraction * omega;  // damping / mass
            var substeps = Math.max(1, Math.ceil(dt / 0.008));  // ~8ms
            var h = dt / substeps;
            var v = spring.velocity;
            var x = spring.value;
            var to = spring.target;
            for (var i = 0; i < substeps; ++i) {
                var a = -k * (x - to) - c * v;      // spring + damping
                v += a * h;
                x += v * h;
            }
            spring.velocity = v;
            spring.value = x;
            if (Math.abs(x - to) < spring.restDelta && Math.abs(v) < spring.restVelocity) {
                spring.velocity = 0;
                spring.value = to;
                _frame.running = false;
                spring.settled();
            }
        }
    }
}
