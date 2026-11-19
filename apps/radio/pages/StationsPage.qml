pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../components"

// A list of stations: a place's, or those around you. `load(done)` fetches
// them; local FM comes first, as the service sorts them.
Page {
    id: page

    property var app
    property string title
    property var load
    property var stations: []
    property bool loading: true
    readonly property var radio: app.radio

    function reload() {
        loading = true;
        load(list => {
            page.stations = list;
            page.loading = false;
        });
    }

    Component.onCompleted: reload()

    Connections {
        target: page.radio
        // The survey after a scan names FM stations as it goes.
        function onScanningChanged() {
            if (!page.radio.scanning)
                page.reload();
        }
    }

    SilicaListView {
        id: list

        anchors {
            fill: parent
            bottomMargin: mini.height
        }
        model: page.stations
        clip: true

        header: PageHeader {
            title: page.title
            description: page.loading ? "" : page.radio.stationCount(page.stations.length)
        }

        PullDownMenu {
            visible: page.radio.tuner

            MenuItem {
                text: page.radio.scanning ? qsTr("Scanning FM…") : qsTr("Scan for FM stations")
                enabled: !page.radio.scanning
                onClicked: page.radio.scan()
            }
        }

        delegate: StationItem {
            required property var modelData

            station: modelData
            current: page.radio.station !== null && page.radio.station.id === modelData.id
            playing: page.radio.playing
            onClicked: page.radio.play(modelData, page.stations)
            onFavouriteToggled: {
                page.radio.setFavourite(modelData, !modelData.favourite);
                page.reload();
            }
        }

        ViewPlaceholder {
            enabled: !page.loading && list.count === 0
            text: qsTr("No stations here")
            hintText: page.radio.tuner && !page.radio.headset ? qsTr("Plug in wired headphones to hear FM: they are the aerial") : ""
        }

        VerticalScrollDecorator {}
    }

    BusyIndicator {
        anchors.centerIn: parent
        size: BusyIndicatorSize.Large
        running: page.loading
    }

    MiniPlayer {
        id: mini

        anchors.bottom: parent.bottom
        width: parent.width
        radio: page.radio
        onOpened: pageStack.animatorPush(Qt.resolvedUrl("NowPlayingPage.qml"), {
            app: page.app
        })
    }
}
