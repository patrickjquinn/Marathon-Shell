pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    // ── Family loaders ───────────────────────────────────────
    // Sora is a variable font (single file, weights 100-800).
    // We load it from the shell qrc inside MTypography so that
    // `font.family` binds to the FontLoader's loaded `name` instead
    // of a hardcoded string. On Linux/Wayland, hardcoded family
    // strings go through fontconfig and silently fall back to Noto
    // Sans if Sora isn't installed system-wide — the FontLoader
    // adds the font to Qt's QFontDatabase but the fontconfig lookup
    // is what QML really hits when it sees a string. Binding to
    // `loader.name` keeps the resolution inside Qt's app-font store.
    // Font files live inside this module under fonts/. Qt.resolvedUrl
    // produces a module-relative qrc path that works in both the shell
    // process and the per-app marathon-app-runner process (each gets
    // its own qrc, but the font travels with the module).
    property FontLoader _soraLoader: FontLoader {
        source: Qt.resolvedUrl("fonts/Sora.ttf")
        onStatusChanged: {
            const map = ["Null", "Ready", "Loading", "Error"];
            console.warn("[MTypography] Sora -> status=" + map[status] + " family='" + name + "'");
        }
    }
    property FontLoader _monoLoader: FontLoader {
        source: Qt.resolvedUrl("fonts/JetBrainsMono-Medium.ttf")
        onStatusChanged: {
            const map = ["Null", "Ready", "Loading", "Error"];
            console.warn("[MTypography] JetBrains Mono -> status=" + map[status] + " family='" + name + "'");
        }
    }

    // Use the loaded font's reported family name. If status isn't Ready
    // yet (cold start race), fall back to the static string so the
    // singleton resolution never returns empty.
    readonly property string fontFamily: _soraLoader.name !== "" ? _soraLoader.name : "Sora"
    readonly property string fontFamilyMono: _monoLoader.name !== "" ? _monoLoader.name : "JetBrains Mono"
    readonly property string fontMonospace: fontFamilyMono

    // ── Type scale — design-system roles (Sora) ───────────────
    // Marathon DS 2026. iOS-aligned, 2-tier hierarchy.
    // Roles are semantic — use these in new code rather than
    // the legacy abstract sizes below.
    readonly property int sizeDisplay: Math.round(96 * (Constants.scaleFactor || 1.0))
    readonly property int sizeTitleL: Math.round(48 * (Constants.scaleFactor || 1.0))
    readonly property int sizeTitle1: Math.round(34 * (Constants.scaleFactor || 1.0))
    readonly property int sizeTitle2: Math.round(28 * (Constants.scaleFactor || 1.0))
    readonly property int sizeTitle3: Math.round(22 * (Constants.scaleFactor || 1.0))
    readonly property int sizeHeadline: Math.round(17 * (Constants.scaleFactor || 1.0))
    readonly property int sizeBody: Math.round(17 * (Constants.scaleFactor || 1.0))
    readonly property int sizeCallout: Math.round(16 * (Constants.scaleFactor || 1.0))
    readonly property int sizeSubhead: Math.round(15 * (Constants.scaleFactor || 1.0))
    readonly property int sizeFootnote: Math.round(13 * (Constants.scaleFactor || 1.0))
    readonly property int sizeCaption: Math.round(12 * (Constants.scaleFactor || 1.0))
    readonly property int sizeEyebrow: Math.round(11 * (Constants.scaleFactor || 1.0))
    readonly property int sizeMono: Math.round(13 * (Constants.scaleFactor || 1.0))

    // ── Letter-spacing per role ──────────────────────────────
    // Negative on display weights, positive on tracked caps.
    readonly property real trackingDisplay: -3.0
    readonly property real trackingTitleL: -1.2
    readonly property real trackingTitle1: -0.8
    readonly property real trackingTitle2: -0.5
    readonly property real trackingTitle3: -0.3
    readonly property real trackingHeadline: -0.1
    readonly property real trackingBody: 0.0
    readonly property real trackingCallout: 0.0
    readonly property real trackingSubhead: -0.1
    readonly property real trackingFootnote: 0.1
    readonly property real trackingCaption: 0.2
    readonly property real trackingEyebrow: 1.4
    readonly property real trackingMono: 0.2

    // ── Weights (Sora is a variable font, 100-800 axis) ──────
    // Defaults per role:
    //   Display/TitleL/Title1   200
    //   Title2                  300
    //   Title3                  500
    //   Headline                600
    //   Body/Callout/Footnote   400
    //   Subhead/Caption/Mono    500
    //   Eyebrow                 700 + uppercase
    // CSS-standard axis numbers (variable Sora ships 100–800).
    // Sora[wght] only renders interpolated weights when the family is
    // loaded as a variable font; if the system falls back to a static
    // face the weight axis snaps to the nearest available cut.
    readonly property int weightThin: 100         // Lock clock variant
    readonly property int weightExtraLight: 200   // Display / Title L / Title 1 / Top-bar
    readonly property int weightLight: 300        // Title 2 (Music now-playing track name)
    readonly property int weightRegular: 400      // Body, Callout, Footnote
    readonly property int weightNormal: 400       // alias
    readonly property int weightMedium: 500       // Title 3, Subhead, Caption, Mono
    readonly property int weightDemiBold: 600     // Headline
    readonly property int weightBold: 700         // Eyebrow (UPPERCASE)
    readonly property int weightBlack: 800        // reserved

    // Compatibility shim — the old weightUltraLight constant used to
    // hold 300; some shipped components still reference it. Keep the
    // value pointed at 300 so behaviour is unchanged until callers
    // migrate to weightLight.
    readonly property int weightUltraLight: 300

    // ── Legacy aliases (kept while components migrate) ───────
    // Map old abstract sizes to the nearest semantic role.
    // Remove once every consumer references the role names.
    readonly property int sizeXSmall: sizeCaption    // 12
    readonly property int sizeSmall: sizeFootnote   // 13
    readonly property int sizeLarge: sizeHeadline   // 17 (was 18)
    readonly property int sizeXLarge: sizeTitle3     // 22 (was 24)
    readonly property int sizeXXLarge: sizeTitle2     // 28 (was 32)
    readonly property int sizeHuge: sizeTitleL     // 48
    readonly property int sizeGigantic: sizeDisplay    // 96
}
