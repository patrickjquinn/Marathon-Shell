import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../components"

// The station on and what it is playing, above the cover's actions: play
// or stop, and the next one.
CoverBackground {
    id: cover

    property var radio
    readonly property var _station: radio.station
    // The cover's actions take its foot.
    readonly property real _top: height - Theme.itemSizeSmall

    StationArt {
        id: art

        visible: cover._station !== null
        x: Theme.paddingLarge
        y: Theme.paddingLarge
        width: Math.min(cover.width * 0.38, cover._top - Theme.paddingLarge * 2)
        height: width
        station: cover._station
    }

    Column {
        anchors {
            left: art.visible ? art.right : parent.left
            leftMargin: Theme.paddingLarge
            right: parent.right
            rightMargin: Theme.paddingLarge
            verticalCenter: art.visible ? art.verticalCenter : undefined
            top: art.visible ? undefined : parent.top
            topMargin: Theme.paddingLarge
        }
        spacing: Theme.paddingSmall

        Label {
            width: parent.width
            text: cover._station ? cover._station.name : qsTr("Radio")
            color: Theme.highlightColor
            wrapMode: Text.Wrap
            maximumLineCount: 2
            truncationMode: TruncationMode.Elide
        }
        Label {
            width: parent.width
            visible: text !== ""
            text: cover.radio.title || (cover.radio.onFm ? qsTr("FM %1").arg(cover.radio.megahertz(cover.radio.frequency)) : "")
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryColor
            wrapMode: Text.Wrap
            maximumLineCount: 2
            truncationMode: TruncationMode.Elide
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
