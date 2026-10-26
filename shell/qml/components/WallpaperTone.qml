import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

// Text straight on the wallpaper takes the tone of what is behind it, as
// the bars' clusters do: dark over a light backdrop, light over a dark one,
// with a faint halo of the other tone. Cover the text with a pixel row clear
// above and below it: the probe reads those two rows.
BackdropProbe {
    id: root

    readonly property bool schemeLight: Silica.Theme.colorScheme === Silica.Theme.DarkOnLight
    // Not animated, for images tinted by drawing them again.
    readonly property color target: light ? Silica.Theme.darkPrimaryColor : Silica.Theme.lightPrimaryColor
    property color glyph: target
    readonly property color secondary: Silica.Theme.rgba(glyph, Silica.Theme.opacityHigh)
    // The ambience's highlight where it reads, else the glyph colour.
    readonly property color accent: light === schemeLight ? Silica.Theme.highlightColor : glyph
    property color halo: light ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(0, 0, 0, 0.35)

    fallbackLight: schemeLight

    Behavior on glyph {
        ColorAnimation {
            duration: MMotion.durationFor("hover")
            easing.type: MMotion.easingFor("hover")
        }
    }

    Behavior on halo {
        ColorAnimation {
            duration: MMotion.durationFor("hover")
            easing.type: MMotion.easingFor("hover")
        }
    }
}
