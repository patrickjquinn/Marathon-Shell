import QtQuick
import QtMultimedia
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

// Tap shows or hides the controls; they stay up while paused.
Item {
    id: root

    property alias source: video.source
    readonly property bool playing: video.playbackState === MediaPlayer.PlayingState
    readonly property bool controlsShown: !playing || shown
    property bool shown: true

    function toggle() {
        if (playing)
            video.pause();
        else
            video.play();
    }

    Video {
        id: video

        objectName: "video"
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectFit
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.shown = !root.shown
    }

    IconButton {
        objectName: "playButton"
        anchors.centerIn: parent
        visible: root.controlsShown
        icon.source: root.playing ? "image://theme/icon-l-pause" : "image://theme/icon-l-play"
        icon.color: Theme.lightPrimaryColor
        Accessible.name: root.playing ? qsTr("Pause") : qsTr("Play")
        onClicked: root.toggle()
    }

    Slider {
        id: slider

        objectName: "positionSlider"
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            bottomMargin: Theme.paddingLarge
        }
        visible: root.controlsShown
        minimumValue: 0
        maximumValue: Math.max(1, video.duration)
        enabled: video.seekable
        palette.colorScheme: Theme.LightOnDark
        valueText: Format.formatDuration(value / 1000, Formatter.DurationShort)
        label: Format.formatDuration(video.duration / 1000, Formatter.DurationShort)
        // Playback moves the value only while the slider is not held.
        onValueChanged: if (!down && Math.abs(value - video.position) > 500)
            video.seek(value)

        Binding on value {
            when: !slider.down
            value: video.position
        }
    }
}
