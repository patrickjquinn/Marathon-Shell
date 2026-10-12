pragma Singleton
import QtQuick
import Sailfish.Silica 1.0 as Silica

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
    // The variable Sora confused Qt's weight resolution — font.weight
    // alone never instanced the wght axis, so requests for Thin (100)
    // rendered as Regular (400, the OS/2 default). We ship 8 static
    // single-weight cuts alongside the variable file and load each
    // through its own FontLoader; that makes them register as distinct
    // family/style pairs in Qt's QFontDatabase and behave predictably
    // with both QtRendering and NativeRendering.
    property FontLoader _soraLoader: FontLoader {
        source: Qt.resolvedUrl("fonts/Sora.ttf")
    }
    property FontLoader _soraThin: FontLoader {
        source: Qt.resolvedUrl("fonts/Sora-Thin.ttf")
    }
    property FontLoader _soraExtraLight: FontLoader {
        source: Qt.resolvedUrl("fonts/Sora-ExtraLight.ttf")
    }
    property FontLoader _soraLight: FontLoader {
        source: Qt.resolvedUrl("fonts/Sora-Light.ttf")
    }
    property FontLoader _soraRegular: FontLoader {
        source: Qt.resolvedUrl("fonts/Sora-Regular.ttf")
    }
    property FontLoader _soraMedium: FontLoader {
        source: Qt.resolvedUrl("fonts/Sora-Medium.ttf")
    }
    property FontLoader _soraSemiBold: FontLoader {
        source: Qt.resolvedUrl("fonts/Sora-SemiBold.ttf")
    }
    property FontLoader _soraBold: FontLoader {
        source: Qt.resolvedUrl("fonts/Sora-Bold.ttf")
    }
    property FontLoader _soraExtraBold: FontLoader {
        source: Qt.resolvedUrl("fonts/Sora-ExtraBold.ttf")
    }
    property FontLoader _monoLoader: FontLoader {
        source: Qt.resolvedUrl("fonts/JetBrainsMono-Medium.ttf")
    }

    // Default family for callers that don't care about weight. Most
    // body text lands here. Always falls back to literal "Sora" so the
    // resolver never returns empty during cold boot. Bind to the
    // variable font's loaded name — this is the family that supports
    // font.variableAxes for weight axis instancing (Qt 6.7+).
    readonly property string fontFamily: Silica.Theme.fontFamily

    // ── Type scale — design-system roles ──────────────────────
    // Body is Silica's body size; the other roles keep their ratio to it,
    // so shell text matches app text at every density and user scale.
    readonly property real unit: Silica.Theme.fontSizeMedium / 17
    readonly property int sizeTitle1: Math.round(34 * unit)
    readonly property int sizeTitle3: Math.round(22 * unit)
    readonly property int sizeHeadline: Math.round(17 * unit)
    readonly property int sizeBody: Math.round(17 * unit)
    readonly property int sizeFootnote: Math.round(13 * unit)
    readonly property int sizeCaption: Math.round(12 * unit)
    readonly property int sizeEyebrow: Math.round(11 * unit)

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
    readonly property int weightNormal: 400       // Body, Callout, Footnote
    readonly property int weightMedium: 500       // Title 3, Subhead, Caption, Mono
    readonly property int weightDemiBold: 600     // Headline
    readonly property int weightBold: 700         // Eyebrow (UPPERCASE)

    // ── Legacy aliases (kept while components migrate) ───────
    // Map old abstract sizes to the nearest semantic role.
    // Remove once every consumer references the role names.
    readonly property int sizeXSmall: sizeCaption    // 12
    readonly property int sizeSmall: sizeFootnote   // 13
    readonly property int sizeLarge: sizeHeadline   // 17 (was 18)
    readonly property int sizeXLarge: sizeTitle3     // 22 (was 24)
}
