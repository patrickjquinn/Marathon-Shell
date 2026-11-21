import QtQuick
import Sailfish.Silica 1.0 as Silica

// Sailfish's glow line: the edge of a band or sheet lit in the highlight,
// fading out towards both ends.
Rectangle {
    id: root

    implicitHeight: Math.max(2, Math.round(Silica.Theme.paddingSmall / 4))
    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop {
            position: 0
            color: "transparent"
        }
        GradientStop {
            position: 0.3
            color: Silica.Theme.highlightColor
        }
        GradientStop {
            position: 0.7
            color: Silica.Theme.highlightColor
        }
        GradientStop {
            position: 1
            color: "transparent"
        }
    }
}
