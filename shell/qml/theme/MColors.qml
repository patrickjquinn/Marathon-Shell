pragma Singleton
import QtQuick
import Sailfish.Silica 1.0 as Silica

QtObject {
    // Accent and text follow the Silica ambience (wallpaper-derived);
    // surfaces stay dark glass over it.

    // ── Surface ramp · canonical DS Theme (engineering doc) ─────
    // Six near-blacks. Cards stack one step lighter than their parent;
    // there is no light theme. Match dev.marathon.UI Silica.Theme.elev0..5 in
    // ds-engineering.jsx and marathon-tokens.css :root.
    readonly property color elev0: "#040404"   // black
    readonly property color elev1: "#0a0a0b"
    readonly property color elev2: "#121213"
    readonly property color elev3: "#1c1c1d"
    readonly property color elev4: "#282829"
    readonly property color elev5: "#353536"

    // BB10-lineage surface tokens — kept for backward compat with
    // existing consumers. New code should prefer elev0..5 above.
    // Values intentionally differ from the DS ramp (more subtle).
    readonly property color bb10Black: "#040404"
    readonly property color bb10Surface: "#0d0d0e"
    readonly property color bb10Elevated: "#161718"
    readonly property color bb10Card: "#1a1b1c"

    readonly property color marathonTeal: Silica.Theme.highlightColor
    readonly property color marathonTealBright: Qt.lighter(Silica.Theme.highlightColor, 1.2)

    readonly property color tealHalo: Silica.Theme.rgba(Silica.Theme.highlightColor, 0.18)

    readonly property color textPrimary: Silica.Theme.primaryColor
    readonly property color textSecondary: Silica.Theme.secondaryColor
    readonly property color textTertiary: Silica.Theme.secondaryColor
    // Black on teal — DS rule. The teal-bright accent is intentionally
    // light enough that black gives high-contrast labels on primary
    // buttons. (Previously #ffffff which failed WCAG against
    // tealBright.)
    readonly property color textOnAccent: "#000000"

    // Glass divider under chrome / over content. Matches
    // --border-glass in marathon-tokens.css.
    readonly property color borderGlass: Qt.rgba(1, 1, 1, 0.06)

    // The nav bar under dark and light content: Keel's overlay backgrounds.
    readonly property color barDark: Qt.rgba(0.04, 0.04, 0.06, 0.9)
    readonly property color barLight: Qt.rgba(0.96, 0.96, 0.96, 0.9)

    readonly property color ripple: Silica.Theme.rgba(Silica.Theme.highlightBackgroundColor, 0.12)

    // Marathon DS reserves only --error for destructive UI (decline
    // call, delete confirmations). No warning/success/info hues —
    // those states are surfaced with neutrals + teal accent per
    // ds-foundations.jsx 'Semantic' rule.
    readonly property color error: "#EF4444"

    // Legacy semantic token — used by older surfaces. New code should
    // NOT use it; surface state via neutrals + teal accent instead.
    readonly property color warning: "#F59E0B"

    readonly property color background: bb10Black
    readonly property color surface: bb10Surface
    readonly property color elevated: bb10Elevated
    readonly property color text: textPrimary
    readonly property color accent: marathonTeal
    readonly property color border: borderGlass

    readonly property color whiteOverlay08: Qt.rgba(1, 1, 1, 0.08)
    readonly property color whiteOverlay16: Qt.rgba(1, 1, 1, 0.16)
}

