pragma Singleton
import QtQuick

QtObject {
    // ── Surface ramp · canonical DS Theme (engineering doc) ─────
    // Six near-blacks. Cards stack one step lighter than their parent;
    // there is no light theme. Match dev.marathon.UI Theme.elev0..5 in
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
    readonly property color bb10Deep: "#070707"
    readonly property color bb10Surface: "#0d0d0e"
    readonly property color bb10Elevated: "#161718"
    readonly property color bb10Card: "#1a1b1c"

    readonly property color marathonTealDarkest: "#006b5d"
    readonly property color marathonTealDark: "#00897b"
    readonly property color marathonTeal: "#00bfa5"
    readonly property color marathonTealBright: "#1de9b6"
    readonly property color marathonTealGlow: "#5dffdc"

    // 35% / 55% teal at 18% halo — used on focus rings, primary glow.
    readonly property color tealBorder: Qt.rgba(0, 191 / 255, 165 / 255, 0.35)
    readonly property color tealBorderHover: Qt.rgba(0, 191 / 255, 165 / 255, 0.55)
    readonly property color tealHalo: Qt.rgba(0, 191 / 255, 165 / 255, 0.18)

    // ── Secondary muted palette ─────────────────────────────────
    // Used ONLY where colour carries semantic meaning, never decoration.
    //   secBlue   — Maps water, Sleep focus, message identity
    //   secGreen  — Maps parks, Move ring, signal-good
    //   secAmber  — Camera permission, "use caution"
    //   secRose   — Mic permission, Activity stand ring, Health
    //   secViolet — Mentions, Linear, categorical chip
    // Each held at saturation ~40 so it sits calmly beside teal.
    readonly property color secBlue: "#3a6b9c"
    readonly property color secBlueD: "#1f3a5c"
    readonly property color secGreen: "#4a8a5e"
    readonly property color secAmber: "#c89545"
    readonly property color secRose: "#a85968"
    readonly property color secViolet: "#6b5d8f"

    readonly property color textPrimary: "#f5f5f5"
    readonly property color textSecondary: "#6a6a6a"
    readonly property color textTertiary: "#4a4a4a"
    readonly property color textHint: "#2a2a2a"
    // Black on teal — DS rule. The teal-bright accent is intentionally
    // light enough that black gives high-contrast labels on primary
    // buttons. (Previously #ffffff which failed WCAG against
    // tealBright.)
    readonly property color textOnAccent: "#000000"

    readonly property color glassTitlebar: Qt.rgba(13 / 255, 13 / 255, 14 / 255, 0.72)
    readonly property color glassTabbar: Qt.rgba(16 / 255, 16 / 255, 17 / 255, 0.78)
    readonly property color glassActionbar: Qt.rgba(11 / 255, 11 / 255, 12 / 255, 0.82)
    readonly property color glassHeader: Qt.rgba(18 / 255, 18 / 255, 19 / 255, 0.85)

    // Glass dividers — under chrome / over content. Match
    // --border-glass and --border-glass-strong in marathon-tokens.css.
    readonly property color borderGlass: Qt.rgba(1, 1, 1, 0.06)
    readonly property color borderGlassStrong: Qt.rgba(1, 1, 1, 0.10)
    readonly property color borderSubtle: Qt.rgba(1, 1, 1, 0.05)
    readonly property color borderDark: Qt.rgba(0, 0, 0, 0.7)

    readonly property color highlightSubtle: Qt.rgba(1, 1, 1, 0.03)
    readonly property color highlightMedium: Qt.rgba(1, 1, 1, 0.06)

    readonly property color hover: Qt.rgba(1, 1, 1, 0.04)
    readonly property color pressed: Qt.rgba(0, 0, 0, 0.1)
    readonly property color ripple: Qt.rgba(0, 191 / 255, 165 / 255, 0.12)

    readonly property color overlay: Qt.rgba(0, 0, 0, 0.85)
    readonly property color overlayLight: Qt.rgba(0, 0, 0, 0.7)

    // Marathon DS reserves only --error for destructive UI (decline
    // call, delete confirmations). No warning/success/info hues —
    // those states are surfaced with neutrals + teal accent per
    // ds-foundations.jsx 'Semantic' rule.
    readonly property color error: "#EF4444"
    readonly property color errorDim: "#B91C1C"

    // Legacy semantic tokens — used by older surfaces (status pills,
    // toasts). New code should NOT use these; surface state via
    // neutrals + teal accent or labelled chips instead.
    readonly property color success: "#10B981"
    readonly property color successDim: "#059669"
    readonly property color warning: "#F59E0B"
    readonly property color warningDim: "#D97706"
    readonly property color info: "#3B82F6"
    readonly property color infoDim: "#2563EB"

    readonly property color background: bb10Black
    readonly property color backgroundLight: bb10Elevated
    readonly property color surface: bb10Surface
    readonly property color elevated: bb10Elevated
    readonly property color text: textPrimary
    readonly property color textInverse: bb10Black
    readonly property color accent: marathonTeal
    readonly property color accentBright: marathonTealBright
    readonly property color accentDark: marathonTealDark
    readonly property color border: borderGlass

    readonly property color marathonTealHoverGradient: Qt.rgba(0, 191 / 255, 165 / 255, 0.03)
    readonly property color marathonTealPressGradient: Qt.rgba(0, 191 / 255, 165 / 255, 0.12)
    readonly property color marathonTealGlowTop: Qt.rgba(0, 191 / 255, 165 / 255, 0.18)
    readonly property color marathonTealGlowMid: Qt.rgba(0, 191 / 255, 165 / 255, 0.10)
    readonly property color marathonTealGlowBottom: Qt.rgba(0, 191 / 255, 165 / 255, 0.02)
    readonly property color marathonTealBorder: Qt.rgba(0, 191 / 255, 165 / 255, 0.35)
    readonly property color marathonTealBorderHover: Qt.rgba(0, 191 / 255, 165 / 255, 0.4)

    readonly property color shadowDefault: Qt.rgba(0, 0, 0, 0.4)
    readonly property color shadowStrong: Qt.rgba(0, 0, 0, 0.6)
    readonly property color shadowHeavy: Qt.rgba(0, 0, 0, 0.7)

    readonly property color whiteOverlay02: Qt.rgba(1, 1, 1, 0.02)
    readonly property color whiteOverlay03: Qt.rgba(1, 1, 1, 0.03)
    readonly property color whiteOverlay04: Qt.rgba(1, 1, 1, 0.04)
    readonly property color whiteOverlay05: Qt.rgba(1, 1, 1, 0.05)
    readonly property color whiteOverlay06: Qt.rgba(1, 1, 1, 0.06)
    readonly property color whiteOverlay08: Qt.rgba(1, 1, 1, 0.08)
    readonly property color whiteOverlay10: Qt.rgba(1, 1, 1, 0.10)
    readonly property color whiteOverlay12: Qt.rgba(1, 1, 1, 0.12)
    readonly property color whiteOverlay15: Qt.rgba(1, 1, 1, 0.15)
    readonly property color whiteOverlay16: Qt.rgba(1, 1, 1, 0.16)
    readonly property color whiteOverlay24: Qt.rgba(1, 1, 1, 0.24)
    readonly property color whiteOverlay30: Qt.rgba(1, 1, 1, 0.30)
    readonly property color whiteOverlay40: Qt.rgba(1, 1, 1, 0.40)

    readonly property color blackOverlay15: Qt.rgba(0, 0, 0, 0.15)
    readonly property color blackOverlay40: Qt.rgba(0, 0, 0, 0.4)
}
