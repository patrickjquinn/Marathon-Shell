import Marathon.Silica 1.0
import QtQuick
import Sailfish.Silica 1.0

CoverBackground {
    id: cover

    property var app

    CoverHeadline {
        objectName: "coverFrequency"
        x: Theme.paddingLarge
        y: Theme.paddingLarge
        width: parent.width - 2 * Theme.paddingLarge
        value: cover.app.megahertz(cover.app.frequency)
        label: qsTr("MHz")
    }

    CoverActionList {
        enabled: cover.app.available

        CoverAction {
            objectName: "playAction"
            iconSource: cover.app.playing ? "image://theme/icon-cover-pause" : "image://theme/icon-cover-play"
            onTriggered: cover.app.playing ? cover.app.stop() : cover.app.play(cover.app.frequency)
        }

    }

}
