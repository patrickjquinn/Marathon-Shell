// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// CoverAction. API from the Silica public documentation (iconSource,
// onTriggered). Keel adds trigger() so the cover (and tests) can fire it.
import QtQuick

QtObject {
    property url iconSource
    property bool __keel_coveraction: true
    signal triggered()
    function trigger() { triggered() }
}
