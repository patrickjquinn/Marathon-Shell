pragma Singleton
import QtQuick

// Marathon DS · Blur radius scale.
//
// Blur radii were literal numbers in 13+ files (2/4/8/16/24/32);
// every one was a copy of someone else's "this looks about right".
// This singleton centralises the scale so:
//   1. The Marathon DS has ONE answer to "how much blur for a sheet?"
//   2. MGlass / the chrome layers can clamp to a Reduce-Blur path in
//      one place by reading MMotion.reduceBlur — see MGlass.qml.
//   3. Call sites read blurFor(role) instead of magic numbers.
//
// Caller pattern (preferred):
//   MGlass { blurMaxRadius: MBlur.blurFor("chrome") }
//
// Direct constants stay exposed for cases that legitimately want a
// fixed scale step (e.g. a button's halo). The accessibility clamp
// is applied by MGlass / consumers, not here — MBlur is a leaf.
QtObject {
    // Scale (px). Powers-of-two so doubling/halving stays predictable.
    readonly property real none: 0
    readonly property real xxs: 2
    readonly property real xs: 4
    readonly property real sm: 8
    readonly property real md: 16
    readonly property real lg: 24
    readonly property real xl: 32

    // Role map — keep in sync with the chrome layers we ship.
    //   chrome    — status bar, top bar, nav bar, dock, NowBar
    //   sheet     — modal sheets, full-bleed sheets, QS shade
    //   dropdown  — combo dropdowns, autocomplete popovers
    //   halo      — focus/halo glows around buttons / sliders
    //   hairline  — sub-1px glass tint on flat surfaces
    function blurFor(role) {
        switch (role) {
        case "chrome":
            return lg;
        case "sheet":
            return lg;
        case "dropdown":
            return sm;
        case "halo":
            return sm;
        case "hairline":
            return xxs;
        }
        return md;
    }
}
