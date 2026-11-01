// SPDX-FileCopyrightText: 2016 - 2019 Jolla Ltd.
// SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
// SPDX-FileCopyrightText: 2026 Patrick Quinn
//
// SPDX-License-Identifier: BSD-3-Clause

import QtQuick 2.12
import Sailfish.Silica 1.0

// A grid line that fades out at both ends, drawn
// with a public gradient instead of Sailfish.Silica.private's Underline,
// so the app uses only public Silica.
Rectangle {
    height: Theme.paddingSmall / 2
    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop {
            position: 0.0
            color: Theme.rgba(Theme.lightSecondaryColor, 0.0)
        }
        GradientStop {
            position: 0.5
            color: Theme.rgba(Theme.lightSecondaryColor, Theme.opacityHigh)
        }
        GradientStop {
            position: 1.0
            color: Theme.rgba(Theme.lightSecondaryColor, 0.0)
        }
    }
}
