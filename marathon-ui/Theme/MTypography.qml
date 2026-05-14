pragma Singleton
import QtQuick
import MarathonOS.Shell

QtObject {
    // ── Families ──────────────────────────────────────────────
    // Sora is a variable font (single file, weights 100-800).
    // JetBrains Mono Medium for numerics / code / terminal.
    readonly property string fontFamily: "Sora"
    readonly property string fontFamilyMono: "JetBrains Mono"
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
    readonly property int weightThin: 100
    readonly property int weightLight: 200
    readonly property int weightRegular: 400
    readonly property int weightNormal: 400
    readonly property int weightMedium: 500
    readonly property int weightDemiBold: 600
    readonly property int weightBold: 700
    readonly property int weightBlack: 800

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
