// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// TextBaseItem (Sailfish.Silica.private): the base of Silica's BSD
// private/TextBase.qml (TextField, TextArea). Names inferred from that QML:
// the SilicaItem `highlighted` and `palette`, `_editor`,
// `horizontalAlignment` with `explicitHorizontalAlignment` and
// setImplicitHorizontalAlignment(), `_keyboardPalette`. Keel's stand-in: a
// FocusScope; an alignment set by the app is explicit, one passed to
// setImplicitHorizontalAlignment() (the editor's own, e.g. for
// right-to-left text) applies only while none is.
import QtQuick
import Sailfish.Silica.private 1.0

FocusScope {
    id: base

    readonly property bool __keel_silica_style: true
    property bool highlighted: palette._parentHighlighted
    /*override*/ readonly property Palette palette: Palette {}

    property Item _editor
    property int horizontalAlignment: TextInput.AlignLeft
    property bool explicitHorizontalAlignment
    property string _keyboardPalette

    property bool _keelImplicitChange

    function setImplicitHorizontalAlignment(alignment) {
        if (explicitHorizontalAlignment || alignment === horizontalAlignment)
            return
        _keelImplicitChange = true
        horizontalAlignment = alignment
        _keelImplicitChange = false
    }

    onHorizontalAlignmentChanged: {
        if (!_keelImplicitChange)
            explicitHorizontalAlignment = true
    }
}
