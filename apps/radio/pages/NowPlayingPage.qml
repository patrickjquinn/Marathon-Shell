pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../components"

// The station on: its logo, what it is playing, how it reaches you (FM
// and its signal, or the stream), and the controls. Side by side on a
// screen as wide as it is tall, stacked on a tall one.
Page {
    id: page

    property var app
    readonly property var radio: app.radio
    readonly property var station: radio.station
    readonly property bool wide: width > height * 0.85

    readonly property string _how: {
        if (!station)
            return "";
        if (radio.onFm) {
            const parts = [qsTr("FM %1").arg(radio.megahertz(radio.frequency))];
            if (radio.state.stereo)
                parts.push(qsTr("stereo"));
            return parts.join(" · ");
        }
        const parts = [];
        if (station.codec)
            parts.push(station.bitrate > 0 ? "%1 %2 kbps".arg(station.codec).arg(station.bitrate) : station.codec);
        const where = [station.region, station.country].filter(s => s).join(", ");
        if (where)
            parts.push(where);
        return parts.join(" · ");
    }

    readonly property string _playing: {
        if (radio.connecting)
            return qsTr("Tuning in…");
        if (radio.broken)
            return qsTr("This station isn't answering. Try another, or again later.");
        if (!radio.title)
            return "";
        return radio.artist ? "%1\n%2".arg(radio.title).arg(radio.artist) : radio.title;
    }

    PageHeader {
        id: header

        title: qsTr("Now playing")
    }

    StationArt {
        id: art

        station: page.station
        width: page.wide ? Math.min(page.height - header.height - Theme.paddingLarge * 3, page.width * 0.42) : Math.min(page.width * 0.62, page.height * 0.36)
        height: width
        x: page.wide ? Theme.horizontalPageMargin : (page.width - width) / 2
        y: header.height + (page.wide ? Math.max(0, (page.height - header.height - height) / 2 - Theme.paddingLarge) : 0)
    }

    Column {
        id: info

        x: page.wide ? art.x + art.width + Theme.paddingLarge * 2 : Theme.horizontalPageMargin
        y: page.wide ? art.y + (art.height - height) / 2 : art.y + art.height + Theme.paddingLarge
        width: page.wide ? page.width - x - Theme.horizontalPageMargin : page.width - 2 * Theme.horizontalPageMargin
        spacing: Theme.paddingMedium

        Label {
            objectName: "stationName"
            width: parent.width
            horizontalAlignment: page.wide ? Text.AlignLeft : Text.AlignHCenter
            text: page.station ? page.station.name : qsTr("Nothing on")
            font.pixelSize: Theme.fontSizeLarge
            color: Theme.highlightColor
            wrapMode: Text.Wrap
            maximumLineCount: 2
            truncationMode: TruncationMode.Elide
        }
        Label {
            objectName: "nowPlaying"
            width: parent.width
            visible: text !== ""
            horizontalAlignment: page.wide ? Text.AlignLeft : Text.AlignHCenter
            text: page._playing
            wrapMode: Text.Wrap
            maximumLineCount: 4
            truncationMode: TruncationMode.Elide
            color: page.radio.broken ? Theme.errorColor : Theme.primaryColor
        }
        Label {
            width: parent.width
            horizontalAlignment: page.wide ? Text.AlignLeft : Text.AlignHCenter
            text: page._how
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryColor
            wrapMode: Text.Wrap
            maximumLineCount: 2
        }

        Item {
            width: 1
            height: Theme.paddingSmall
        }

        Row {
            anchors.horizontalCenter: page.wide ? undefined : parent.horizontalCenter
            x: page.wide ? -Theme.paddingMedium : 0
            spacing: Theme.paddingMedium

            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                icon.source: "image://theme/icon-m-media-previous"
                Accessible.name: qsTr("Previous station")
                onClicked: page.radio.previous()
            }
            IconButton {
                objectName: "playToggle"
                icon.source: page.radio.playing ? "image://theme/icon-l-media-pause" : "image://theme/icon-l-media-play"
                opacity: page.radio.connecting ? 0 : 1
                Accessible.name: page.radio.playing ? qsTr("Stop") : qsTr("Play")
                enabled: page.station !== null
                onClicked: page.radio.toggle()

                BusyIndicator {
                    anchors.centerIn: parent
                    size: BusyIndicatorSize.Medium
                    running: page.radio.connecting
                }
            }
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                icon.source: "image://theme/icon-m-media-next"
                Accessible.name: qsTr("Next station")
                onClicked: page.radio.next()
            }
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                visible: page.station !== null
                icon.source: page.station && page.station.favourite ? "image://theme/icon-m-favorite-selected" : "image://theme/icon-m-favorite"
                Accessible.name: page.station && page.station.favourite ? qsTr("Remove from favourites") : qsTr("Add to favourites")
                onClicked: page.radio.setFavourite(page.station, !page.station.favourite)
            }
        }

        Label {
            width: parent.width
            visible: page.radio.onFm && !page.radio.headset
            horizontalAlignment: page.wide ? Text.AlignLeft : Text.AlignHCenter
            wrapMode: Text.Wrap
            text: qsTr("Plug in wired headphones for clear FM: they are the aerial")
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryHighlightColor
        }
    }
}
