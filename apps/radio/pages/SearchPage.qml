pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../components"

// Every station in the directory by name, genre or place: those near you
// and on FM first.
Page {
    id: page

    property var app
    property var stations: []
    property bool searching: false
    property string _asked: ""
    readonly property var radio: app.radio

    // Ready to type once the page has slid in.
    onStatusChanged: {
        if (status === PageStatus.Active && list.headerItem)
            list.headerItem.forceActiveFocus();
    }

    function run(text) {
        const q = text.trim();
        _asked = q;
        if (q.length < 2) {
            stations = [];
            searching = false;
            return;
        }
        searching = true;
        radio.search(q, list => {
            if (q !== page._asked)
                return;
            page.stations = list;
            page.searching = false;
        });
    }

    SilicaListView {
        id: list

        anchors {
            fill: parent
            bottomMargin: mini.height
        }
        model: page.stations
        clip: true
        currentIndex: -1

        header: SearchField {
            id: field

            width: list.width
            placeholderText: qsTr("Station, genre or place")
            inputMethodHints: Qt.ImhNoPredictiveText
            EnterKey.iconSource: "image://theme/icon-m-enter-close"
            EnterKey.onClicked: focus = false
            onTextChanged: debounce.restart()

            Timer {
                id: debounce

                interval: 350
                onTriggered: page.run(field.text)
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
                page.run(page._asked);
            }
        }

        ViewPlaceholder {
            enabled: !page.searching && list.count === 0 && page._asked.length >= 2
            text: qsTr("Nothing found")
            hintText: qsTr("Try a station's name, a genre like jazz, or a city")
        }

        VerticalScrollDecorator {}
    }

    BusyIndicator {
        anchors.centerIn: parent
        size: BusyIndicatorSize.Large
        running: page.searching
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
