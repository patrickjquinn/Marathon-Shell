import QtQuick

// Marathon OS · Slate Aurora (default wallpaper).
// Thin loader over the SVG file in shell/resources/wallpapers/.
// The SVG anchors a horizon at y=540 by composition (not by an
// explicit line — chrome on top composes over it).
//
// 64×64 dither-noise tile overlaid at very low opacity to break up
// the gradient banding on 18 bpp DPI panels (the HyperPixel 4.0 Square
// on Hackberry CM5 quantises the slate gradient to 6 bpc per channel
// and produces visible Mach bands without dithering).
Item {
    anchors.fill: parent

    Image {
        anchors.fill: parent
        source: "qrc:/wallpapers/slate-aurora.svg"
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: width > 0 ? width : 390
        sourceSize.height: height > 0 ? height : 844
        smooth: true
        cache: true
    }

    Image {
        anchors.fill: parent
        // qrc-form qt_add_resources silently drops every wallpaper but
        // slate-aurora.svg (verified via `strings marathon-shell-bin |
        // grep ^qrc:`). The 18 bpc dither tile only lands as a
        // file install; load it from disk by absolute path.
        source: "file:///usr/share/marathon-shell/wallpapers/dither-noise.png"
        fillMode: Image.Tile
        opacity: 0.04
        smooth: false
        cache: true
    }
}
