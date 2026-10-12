import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "Library.js" as Library

Slider {
    id: slider

    property Player player

    minimumValue: 0
    maximumValue: Math.max(1, player.duration)
    enabled: player.currentTrack !== null
    valueText: down ? Library.formatTime(value / 1000) : ""
    label: qsTr("%1 of %2").arg(Library.formatTime(value / 1000)).arg(Library.formatTime(player.duration / 1000))
    // Playback moves the value only while the slider is not held, so any
    // other change is the user's: a drag ending or a key press.
    onValueChanged: if (!down && Math.abs(value - player.position) > 500) player.seek(value)

    Binding on value {
        when: !slider.down
        value: slider.player.position
    }
}
