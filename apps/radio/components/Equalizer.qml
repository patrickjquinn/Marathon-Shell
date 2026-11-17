pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0

// Three bars that bounce while sound plays and rest low when it does not.
Row {
    id: eq

    property bool running: true

    spacing: Math.max(2, Math.round(Theme.paddingSmall / 2))
    height: Theme.iconSizeExtraSmall
    Accessible.ignored: true

    Repeater {
        model: 3

        Rectangle {
            id: bar

            required property int index

            width: Math.max(3, Math.round(Theme.paddingSmall * 0.6))
            height: eq.height * 0.3
            anchors.bottom: parent.bottom
            color: Theme.highlightColor

            SequentialAnimation on height {
                running: eq.running && Qt.application.state === Qt.ApplicationActive
                loops: Animation.Infinite
                alwaysRunToEnd: false

                NumberAnimation {
                    to: eq.height * (0.55 + 0.15 * bar.index)
                    duration: 260 + 70 * bar.index
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    to: eq.height * (0.25 + 0.1 * ((bar.index + 1) % 3))
                    duration: 300 + 60 * ((bar.index + 2) % 3)
                    easing.type: Easing.InOutSine
                }
            }
        }
    }
}
