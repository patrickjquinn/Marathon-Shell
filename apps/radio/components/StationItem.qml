pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0

// A station in a list: its logo, name and what it is (FM 100.3 and the name
// it sends over RDS, or the stream's codec and rate, and its genres),
// marked when it is playing.
ListItem {
    id: item

    property var station
    property bool current: false
    property bool playing: false

    signal favouriteToggled

    readonly property string _what: {
        const s = station;
        const parts = [];
        if (s.fm > 0) {
            parts.push(qsTr("FM %1").arg((s.fm / 1000).toFixed(1)));
            if (s.rds)
                parts.push(qsTr("RDS %1").arg(s.rds));
        } else if (s.codec)
            parts.push(s.bitrate > 0 ? "%1 %2k".arg(s.codec).arg(s.bitrate) : s.codec);
        if (s.tags)
            parts.push(s.tags);
        else if (s.region || s.country)
            parts.push(s.region || s.country);
        return parts.join(" · ");
    }

    contentHeight: Theme.itemSizeMedium
    Accessible.name: station.name

    menu: ContextMenu {
        MenuItem {
            text: item.station.favourite ? qsTr("Remove from favourites") : qsTr("Add to favourites")
            onClicked: item.favouriteToggled()
        }
    }

    StationArt {
        id: art

        x: Theme.horizontalPageMargin
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.itemSizeSmall
        height: width
        station: item.station
    }

    Column {
        anchors {
            left: art.right
            leftMargin: Theme.paddingLarge
            right: badge.left
            rightMargin: Theme.paddingMedium
            verticalCenter: parent.verticalCenter
        }

        Label {
            width: parent.width
            text: item.station.name
            truncationMode: TruncationMode.Fade
            color: item.current || item.highlighted ? Theme.highlightColor : Theme.primaryColor
        }
        Label {
            width: parent.width
            text: item._what
            truncationMode: TruncationMode.Fade
            font.pixelSize: Theme.fontSizeExtraSmall
            color: item.current || item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
        }
    }

    Row {
        id: badge

        anchors {
            right: parent.right
            rightMargin: Theme.horizontalPageMargin
            verticalCenter: parent.verticalCenter
        }
        spacing: Theme.paddingSmall

        Image {
            visible: item.station.favourite === true
            source: "image://theme/icon-s-favorite-selected?" + Theme.highlightColor
            anchors.verticalCenter: parent.verticalCenter
        }
        Equalizer {
            visible: item.current
            running: item.playing
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
