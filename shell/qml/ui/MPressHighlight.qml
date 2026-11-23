import MarathonOS.Shell
import QtQuick
import Sailfish.Silica 1.0 as Silica

// Keel BackgroundItem's press highlight, for rows that can't be one.
Rectangle {
    id: root

    property bool down

    radius: Silica.Theme.paddingMedium
    color: Silica.Theme.rgba(Silica.Theme.highlightBackgroundColor, Silica.Theme.highlightBackgroundOpacity)
    opacity: down ? 1 : 0

    Behavior on opacity {
        OpacityAnimator {
            duration: MMotion.ms(root.down ? 0 : 160)
        }
    }
}
