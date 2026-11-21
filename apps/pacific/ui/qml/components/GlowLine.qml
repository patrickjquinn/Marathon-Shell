// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

// The glow line on a sheet's top edge, as the shell's: the highlight,
// fading out towards both ends.

import QtQuick
import Sailfish.Silica 1.0

Rectangle {
    implicitHeight: Math.max(2, Math.round(Theme.paddingSmall / 4))
    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop {
            position: 0
            color: "transparent"
        }
        GradientStop {
            position: 0.3
            color: Theme.rgba(Theme.highlightColor, 0.3)
        }
        GradientStop {
            position: 0.7
            color: Theme.rgba(Theme.highlightColor, 0.3)
        }
        GradientStop {
            position: 1
            color: "transparent"
        }
    }
}
