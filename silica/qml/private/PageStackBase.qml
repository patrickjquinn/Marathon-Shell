// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// PageStackBase (Sailfish.Silica.private): the base of Silica's BSD
// PageStack.qml. Silica's own is native and not open; Keel's stand-in is
// PageStackGestureArea (plugin/cpp/private/pagestackgesture.h) plus the
// state PageStack.qml and PageStack.js keep on it (names inferred from
// them): `depth`, `currentPage`, `busy`, `_currentContainer`,
// `_ongoingTransitionCount`, and the SilicaItem `highlighted` and
// `palette`.
import QtQuick
import Sailfish.Silica.private 1.0

PageStackGestureArea {
    readonly property bool __keel_silica_style: true
    property bool highlighted: palette._parentHighlighted
    /*override*/ readonly property Palette palette: Palette {}

    property int depth
    property Item currentPage
    property Item _currentContainer
    property int _ongoingTransitionCount
    readonly property bool busy: _ongoingTransitionCount > 0
}
