// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// CoverActionList. API from the Silica public documentation (enabled,
// iconBackground, window); holds CoverAction children.
import QtQuick

QtObject {
    id: list
    property bool enabled: true
    property bool iconBackground: false
    property var window: null
    property bool __keel_coveractionlist: true
    default property list<QtObject> _actionObjects
}
