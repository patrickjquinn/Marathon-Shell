// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Qt 5 Camera.focus (QtMultimedia 5.x). The Camera wrapper maps focusMode to
// Qt 6's focusMode and applies customFocusPoint (FocusPointCustom) or the
// centre (FocusPointCenter) as Qt 6's customFocusPoint. focusZones is always
// empty: Qt 6 does not report focus areas. The FocusMode, FocusPointMode and
// FocusAreaStatus enums are on Camera, as in Qt 5.
import QtQml 2.15

QtObject {
    property int focusMode: 16 // Camera.FocusContinuous
    property int focusPointMode: 0 // Camera.FocusPointAuto
    property point customFocusPoint: Qt.point(0.5, 0.5)
    readonly property var focusZones: []
    readonly property var supportedFocusModes: [8, 16] // FocusAuto, FocusContinuous
    readonly property var supportedFocusPointModes: [0, 1, 3] // Auto, Center, Custom

    function isFocusModeSupported(mode) {
        return supportedFocusModes.indexOf(mode) >= 0
    }
    function isFocusPointModeSupported(mode) {
        return supportedFocusPointModes.indexOf(mode) >= 0
    }
}
