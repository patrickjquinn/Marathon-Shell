// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

import QtQuick

// Qt 5 Multimedia's CameraImageProcessing, as Camera.imageProcessing. The
// controller has neither control; CameraConfigs offers no choices.
QtObject {
    enum WhiteBalanceMode {
        WhiteBalanceAuto,
        WhiteBalanceSunlight,
        WhiteBalanceCloudy,
        WhiteBalanceShade,
        WhiteBalanceTungsten,
        WhiteBalanceFluorescent,
        WhiteBalanceSunset
    }
    enum ColorFilter {
        ColorFilterNone,
        ColorFilterGrayscale,
        ColorFilterNegative,
        ColorFilterSolarize,
        ColorFilterSepia,
        ColorFilterPosterize,
        ColorFilterWhiteboard,
        ColorFilterBlackboard,
        ColorFilterAqua
    }

    property int whiteBalanceMode: CameraImageProcessing.WhiteBalanceAuto
    property int colorFilter: CameraImageProcessing.ColorFilterNone
}
