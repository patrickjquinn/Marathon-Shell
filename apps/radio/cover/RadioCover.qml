import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../components"

// The station on and what it is playing; play or stop, and the next one.
CoverBackground {
    id: cover

    property var radio
    readonly property var _station: radio.station

    StationArt {
        id: art

        visible: cover._station !== null
        anchors.horizontalCenter: parent.horizontalCenter
        y: Theme.paddingLarge
        width: parent.width * 0.42
        height: width
        station: cover._station
    }

    Column {
        anchors {
            top: art.visible ? art.bottom : parent.top
            topMargin: Theme.paddingMedium
            left: parent.left
            leftMargin: Theme.paddingLarge
            right: parent.right
            rightMargin: Theme.paddingLarge
        }

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: cover._station ? cover._station.name : qsTr("Radio")
            color: Theme.highlightColor
            truncationMode: TruncationMode.Fade
        }

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: cover.radio.title || (cover.radio.onFm ? qsTr("FM %1").arg(cover.radio.megahertz(cover.radio.frequency)) : "")
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryColor
            wrapMode: Text.Wrap
            maximumLineCount: 2
            truncationMode: TruncationMode.Fade
        }
    }

    CoverActionList {
        enabled: cover._station !== null

        CoverAction {
            iconSource: cover.radio.playing ? "image://theme/icon-cover-pause" : "image://theme/icon-cover-play"
            onTriggered: cover.radio.toggle()
        }

        CoverAction {
            iconSource: "image://theme/icon-cover-next-song"
            onTriggered: cover.radio.next()
        }
    }
}
