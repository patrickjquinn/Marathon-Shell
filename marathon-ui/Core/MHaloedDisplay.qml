import QtQuick
import MarathonUI.Theme

// Display-weight text with a teal radial halo behind it.
// Used wherever a hero numeric reads against a dark surface:
//   • Lock screen clock
//   • Calculator readout
//   • Dialer number
//   • OOBE completion glyph
//
// The halo composition (teal radial fading to transparent at ~65%)
// is the design's signature — it's what makes the clock read as
// "lit", not just typed. Implemented as a static SVG asset behind
// the text rather than a MultiEffect blur, per the DS performance
// rule against persistent FBO effects.
Item {
    id: root

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight

    // How far past the text the halo reaches.
    property real haloMargin: 28

    // Text properties — proxied to the inner Text.
    property alias text: label.text
    property alias font: label.font
    property alias color: label.color
    property alias textFormat: label.textFormat
    property alias horizontalAlignment: label.horizontalAlignment

    // The halo. SVG asset, gradient pre-baked.
    Image {
        id: halo
        x: -root.haloMargin
        y: -root.haloMargin
        width: root.width + root.haloMargin * 2
        height: root.height + root.haloMargin * 2
        // The Theme module qrc resource. Use the full URL so resolution
        // works whether or not the caller has already imported
        // MarathonUI.Theme — the hardcoded qrc path resolves through the
        // global Qt resource system once any module has loaded the
        // Theme resource bundle. (Previous failure mode: Image opened
        // before Theme.qmldir was processed → resource not yet
        // registered → "Cannot open: qrc:..." warning. Use the
        // Qt.resolvedUrl pointing into the sibling Theme/ directory
        // instead — Qt's QQmlEngine handles the cross-module ref.)
        source: Qt.resolvedUrl("../Theme/halo-teal.svg")
        fillMode: Image.PreserveAspectFit
        smooth: true
        cache: true
        z: -1
    }

    Text {
        id: label
        anchors.centerIn: parent
        // Caller sets text + font + color via the aliases above.
        // Defaults: Display 96 / weight 200 / -3 letter-spacing
        // (matches the lock clock from the DS).
        color: MColors.textPrimary
        font.family: MTypography.fontFamily
        font.pixelSize: MTypography.sizeDisplay
        font.weight: MTypography.weightExtraLight   // 200 default
        font.letterSpacing: MTypography.trackingDisplay
        // Sora ships as a variable font (wght axis 100–800, default 400).
        // font.weight alone does NOT instance the axis — Qt resolves to
        // the static cut whose OS/2 weight is closest, and since the
        // file's default is 400 the lock clock rendered as Regular even
        // when the caller asked for Thin (100). Empirically verified by
        // pixel-matching the rendered glyphs against fontTools-instanced
        // reference renders at 100/200/300/400. Binding variableAxes
        // here engages the wght axis so font.weight actually maps to a
        // weighted instance. font.styleName is belt-and-suspenders for
        // the NativeRendering path where Qt falls back to fontconfig
        // matching by style rather than axis interpolation.
        font.variableAxes: ({
                "wght": label.font.weight
            })
        font.styleName: label.font.weight <= 100 ? "Thin" : label.font.weight <= 200 ? "ExtraLight" : label.font.weight <= 300 ? "Light" : label.font.weight <= 400 ? "Regular" : label.font.weight <= 500 ? "Medium" : label.font.weight <= 600 ? "SemiBold" : label.font.weight <= 700 ? "Bold" : "ExtraBold"
        renderType: Text.QtRendering
    }
}
