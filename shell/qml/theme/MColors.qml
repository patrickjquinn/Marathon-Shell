pragma Singleton
import QtQuick
import Sailfish.Silica 1.0 as Silica

QtObject {
    // Accent and text follow the Silica ambience (wallpaper-derived);
    // surfaces stay dark glass over it.

    // E-paper (docs/design/EINK_MODE.md): ink on paper, from the panel's
    // 16 greys (multiples of 0x11), no glass. The ambience turns dark on
    // light with it (AmbienceController).
    property bool eink: typeof DeviceProfile !== "undefined" && DeviceProfile.displayTechnology === "epaper"
    // OLED pixels at the floor are off: black, and wallpapers dithered from 16 bits.
    readonly property bool oled: typeof DeviceProfile !== "undefined" && DeviceProfile.displayTechnology === "oled"

    function wallpaper(path) {
        return oled && path ? "image://wallpaper/" + encodeURIComponent(path) + "?oled=1" : path;
    }

    // ── Surface ramp · canonical DS Theme (engineering doc) ─────
    // Six near-blacks. Cards stack one step lighter than their parent;
    // there is no light theme. Match dev.marathon.UI Silica.Theme.elev0..5 in
    // ds-engineering.jsx and marathon-tokens.css :root.
    readonly property color elev0: eink ? "#ffffff" : oled ? "#000000" : "#040404"   // black
    readonly property color elev1: eink ? "#ffffff" : "#0a0a0b"
    readonly property color elev2: eink ? "#eeeeee" : "#121213"
    readonly property color elev3: eink ? "#dddddd" : "#1c1c1d"
    readonly property color elev4: eink ? "#cccccc" : "#282829"
    readonly property color elev5: eink ? "#bbbbbb" : "#353536"

    // BB10-lineage surface tokens — kept for backward compat with
    // existing consumers. New code should prefer elev0..5 above.
    // Values intentionally differ from the DS ramp (more subtle).
    readonly property color bb10Black: eink ? "#ffffff" : oled ? "#000000" : "#040404"
    readonly property color bb10Surface: eink ? "#ffffff" : "#0d0d0e"
    readonly property color bb10Elevated: eink ? "#eeeeee" : "#161718"
    readonly property color bb10Card: eink ? "#eeeeee" : "#1a1b1c"

    readonly property color marathonTeal: Silica.Theme.highlightColor
    readonly property color marathonTealBright: Qt.lighter(Silica.Theme.highlightColor, 1.2)

    readonly property color tealHalo: eink ? "transparent" : Silica.Theme.rgba(Silica.Theme.highlightColor, 0.18)

    readonly property color textPrimary: Silica.Theme.primaryColor
    readonly property color textSecondary: Silica.Theme.secondaryColor
    readonly property color textTertiary: Silica.Theme.secondaryColor
    // Black on teal — DS rule. The teal-bright accent is intentionally
    // light enough that black gives high-contrast labels on primary
    // buttons. (Previously #ffffff which failed WCAG against
    // tealBright.)
    readonly property color textOnAccent: eink ? "#ffffff" : "#000000"

    // Glass divider under chrome / over content. Matches
    // --border-glass in marathon-tokens.css.
    readonly property color borderGlass: eink ? "#777777" : Qt.rgba(1, 1, 1, 0.06)

    // The nav bar under dark and light content: Keel's overlay backgrounds.
    readonly property color barDark: eink ? "#ffffff" : "#000000"
    readonly property color barLight: eink ? "#ffffff" : Qt.rgba(0.96, 0.96, 0.96, 0.9)
    // Behind the status bar on a screen with a notch: the notch's own black.
    readonly property color cutoutBand: "#000000"

    readonly property color ripple: eink ? "transparent" : Silica.Theme.rgba(Silica.Theme.highlightBackgroundColor, 0.12)

    // Marathon DS reserves only --error for destructive UI (decline
    // call, delete confirmations). No warning/success/info hues —
    // those states are surfaced with neutrals + teal accent per
    // ds-foundations.jsx 'Semantic' rule.
    readonly property color error: eink ? "#000000" : "#EF4444"

    // Legacy semantic token — used by older surfaces. New code should
    // NOT use it; surface state via neutrals + teal accent instead.
    readonly property color warning: eink ? "#000000" : "#F59E0B"

    readonly property color background: bb10Black
    readonly property color surface: bb10Surface
    readonly property color elevated: bb10Elevated
    readonly property color text: textPrimary
    readonly property color accent: marathonTeal
    // A switched-on or suggested control's fill: the ambience highlight, deep
    // enough to carry a white glyph.
    readonly property color accentFill: eink ? "#000000" : Qt.hsla(Silica.Theme.highlightColor.hslHue, Math.min(1, Silica.Theme.highlightColor.hslSaturation * 0.9), 0.2, 1)
    // A control's resting fill.
    readonly property color controlFill: eink ? "#eeeeee" : Qt.rgba(1, 1, 1, 0.08)
    readonly property color border: borderGlass
    // Toasts, the HUD and other cards over whatever is behind them: dark
    // glass, or paper with an ink edge on e-paper, which can only dither it.
    readonly property color badge: eink ? background : Qt.rgba(0, 0, 0, 0.85)
    readonly property real badgeEdgeOpacity: eink ? 1 : 0.1

    // On paper an overlay darkens, one and two of the panel's grey steps.
    readonly property color whiteOverlay08: eink ? Qt.rgba(0, 0, 0, 1 / 15) : Qt.rgba(1, 1, 1, 0.08)
    readonly property color whiteOverlay16: eink ? Qt.rgba(0, 0, 0, 2 / 15) : Qt.rgba(1, 1, 1, 0.16)

    // Nightshade's bedside clock: no light but the glyphs, in a hue that
    // spares night vision.
    readonly property color nightshadeBackground: "#000000"
    readonly property var nightshadeTints: ({
            "red": "#ff2a14",
            "amber": "#ffa31a",
            "green": "#33d17a"
        })
}
