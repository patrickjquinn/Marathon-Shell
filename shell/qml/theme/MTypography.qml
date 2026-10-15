pragma Singleton
import QtQuick
import Sailfish.Silica 1.0 as Silica

QtObject {
    property FontLoader _phosphorThin: FontLoader {
        source: Qt.resolvedUrl("../ui/fonts/Phosphor-Thin.ttf")
    }
    property FontLoader _phosphorBold: FontLoader {
        source: Qt.resolvedUrl("../ui/fonts/Phosphor-Bold.ttf")
    }
    readonly property string iconFontThin: _phosphorThin.name
    readonly property string iconFontBold: _phosphorBold.name

    // Default family for callers that don't care about weight.
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
