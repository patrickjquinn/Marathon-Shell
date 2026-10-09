// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Qt 5 Camera.imageProcessing (QtMultimedia 5.x) and its enums
// (CameraImageProcessing.WhiteBalanceFlash, ...). The Camera wrapper forwards
// whiteBalanceMode (Qt 5 and Qt 6 number the modes alike) and
// manualWhiteBalance (Qt 6's colorTemperature). Brightness, contrast,
// saturation, sharpening, denoising and colour filters are accepted and
// ignored: Qt 6 has no API for them.
import QtQml 2.15

QtObject {
    enum WhiteBalanceMode {
        WhiteBalanceAuto, WhiteBalanceManual, WhiteBalanceSunlight, WhiteBalanceCloudy,
        WhiteBalanceShade, WhiteBalanceTungsten, WhiteBalanceFluorescent, WhiteBalanceFlash,
        WhiteBalanceSunset, WhiteBalanceVendor = 1000
    }
    enum ColorFilter {
        ColorFilterNone, ColorFilterGrayscale, ColorFilterNegative, ColorFilterSolarize,
        ColorFilterSepia, ColorFilterPosterize, ColorFilterWhiteboard, ColorFilterBlackboard,
        ColorFilterAqua, ColorFilterVendor = 1000
    }

    property int whiteBalanceMode: 0
    property real manualWhiteBalance: 0
    property real brightness: 0
    property real contrast: 0
    property real saturation: 0
    property real sharpeningLevel: -1
    property real denoisingLevel: -1
    property int colorFilter: 0
    readonly property bool available: false

    function isWhiteBalanceModeSupported(mode) {
        return mode >= 0 && mode <= 8
    }
    function isColorFilterSupported(filter) {
        return filter === 0
    }
}
