import QtQuick

// Marathon OS · Slate Aurora (default wallpaper).
// Thin loader over the SVG file in shell/resources/wallpapers/.
// The SVG anchors a horizon at y=540 by composition (not by an
// explicit line — chrome on top composes over it).
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
