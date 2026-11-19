import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

// What is on, along the foot of a page: the station, what it is playing,
// and play or stop. A tap opens Now playing.
BackgroundItem {
    id: bar

    property var radio
    readonly property var _station: bar.radio.station
    readonly property string _line: {
        if (bar.radio.connecting)
            return qsTr("Tuning in…");

        if (bar.radio.broken)
            return qsTr("This station isn't answering");

        if (bar.radio.title)
            return bar.radio.artist ? "%1 · %2".arg(bar.radio.title).arg(bar.radio.artist) : bar.radio.title;

        if (bar.radio.onFm)
            return qsTr("FM %1").arg(bar.radio.megahertz(bar.radio.frequency));

        return _station ? (_station.region || _station.country || "") : "";
    }

    signal opened

    height: _station ? Theme.itemSizeLarge : 0
    visible: _station !== null
    clip: true
    onClicked: bar.opened()
    Accessible.name: _station ? _station.name : ""

    Rectangle {
        anchors.fill: parent
        color: "#0d0e0f"
    }

    Rectangle {
        width: parent.width
        height: 1
        color: Theme.rgba(Theme.highlightColor, 0.25)
    }

    StationArt {
        id: art

        x: Theme.horizontalPageMargin
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.itemSizeSmall
        height: width
        station: bar._station
    }

    Column {
        anchors {
            left: art.right
            leftMargin: Theme.paddingLarge
            right: toggle.left
            rightMargin: Theme.paddingSmall
            verticalCenter: parent.verticalCenter
        }

        Label {
            width: parent.width
            text: bar._station ? bar._station.name : ""
            truncationMode: TruncationMode.Fade
            color: bar.highlighted ? Theme.highlightColor : Theme.primaryColor
        }

        Label {
            width: parent.width
            text: bar._line
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeExtraSmall
            color: bar.radio.broken ? Theme.errorColor : Theme.secondaryColor
        }
    }

    BusyIndicator {
        anchors.centerIn: toggle
        size: BusyIndicatorSize.Medium
        running: bar.radio.connecting
    }

    IconButton {
        id: toggle

        icon.source: bar.radio.playing ? "image://theme/icon-m-media-pause" : "image://theme/icon-m-media-play"
        opacity: bar.radio.connecting ? 0 : 1
        Accessible.name: bar.radio.playing ? qsTr("Stop") : qsTr("Play")
        onClicked: bar.radio.toggle()

        anchors {
            right: parent.right
            rightMargin: Theme.horizontalPageMargin - Theme.paddingMedium
            verticalCenter: parent.verticalCenter
        }
    }

    Behavior on height {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
        }
    }
}
