// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// HighlightImageBase (Sailfish.Silica.private): an Image that is tinted with
// `color`, or `highlightColor` while highlighted; the base of Silica's BSD
// Icon.qml and HighlightImage.qml (names inferred from them). Keel's
// stand-in: image://theme icons are tinted by Keel's theme image provider
// ("<id>?<color>"), drawn over the untinted image; other images are shown
// as they are. `color` and `highlightColor` accept undefined (no tint): in
// a light ambience an untinted theme icon is still drawn in the palette's
// primary colour if it is monochrome ("<id>?mono=<color>"), as Sailfish's
// white monochrome icons are on a light ambience (HighlightImage,
// IconTextSwitch).
import QtQuick
import Sailfish.Silica 1.0
import Sailfish.Silica.private 1.0

Image {
    id: image

    readonly property bool __keel_silica_style: true
    property bool highlighted: palette._parentHighlighted
    /*override*/ readonly property Palette palette: Palette {}
    property var color
    property var highlightColor
    property real monochromeWeight: 1.0

    readonly property string _keelBase: source.toString()
    readonly property bool _keelThemed: _keelBase.indexOf("image://theme/") === 0 && _keelBase.indexOf("?") < 0
    readonly property var _keelTint: highlighted && highlightColor !== undefined ? highlightColor : color
    readonly property bool _keelExplicit: _keelTint !== undefined && _keelTint !== null
                                          && Qt.colorEqual(_keelTint, "transparent") === false
    readonly property bool _keelLightAuto: !_keelExplicit && (_keelTint === undefined || _keelTint === null)
                                           && palette.colorScheme === Theme.DarkOnLight
    readonly property bool _keelTinted: _keelThemed && (_keelExplicit || _keelLightAuto)
    readonly property string _keelTintArg: _keelExplicit ? String(_keelTint) : "mono=" + palette.primaryColor


    // Qt 6 resolves a relative source against this file; resolve it against
    // the app's file that set it (Keel's own).
    onSourceChanged: KeelUrlResolver.fixSourceForControl(image)

    Image {
        anchors.fill: parent
        visible: image._keelTinted && status === Image.Ready
        source: image._keelTinted ? image._keelBase + "?" + image._keelTintArg : ""
        sourceSize: image.sourceSize
        fillMode: image.fillMode
        horizontalAlignment: image.horizontalAlignment
        verticalAlignment: image.verticalAlignment
        asynchronous: image.asynchronous
        smooth: image.smooth
        mirror: image.mirror
    }
}
