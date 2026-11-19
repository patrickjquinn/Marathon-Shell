pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../components"

// Your stations: favourites, then what you played lately.
Page {
    id: page

    property var app
    property var favourites: []
    property var recents: []
    readonly property var radio: app.radio
    readonly property var _recentOnly: recents.filter(r => !favourites.some(f => f.id === r.id))

    function reload() {
        radio.favourites(list => page.favourites = list);
        radio.recents(list => page.recents = list);
    }

    Component.onCompleted: reload()

    component Group: Column {
        id: group

        property string title
        property var stations: []

        width: parent.width
        visible: stations.length > 0

        SectionHeader {
            text: group.title
        }
        Repeater {
            model: group.stations

            StationItem {
                required property var modelData

                width: group.width
                station: modelData
                current: page.radio.station !== null && page.radio.station.id === modelData.id
                playing: page.radio.playing
                onClicked: page.radio.play(modelData, group.stations)
                onFavouriteToggled: {
                    page.radio.setFavourite(modelData, !modelData.favourite);
                    page.reload();
                }
            }
        }
    }

    SilicaFlickable {
        id: flick

        anchors {
            fill: parent
            bottomMargin: mini.height
        }
        contentHeight: column.height + Theme.paddingLarge
        clip: true

        Column {
            id: column

            width: parent.width

            PageHeader {
                title: qsTr("Your stations")
            }
            Group {
                title: qsTr("Favourites")
                stations: page.favourites
            }
            Group {
                title: qsTr("Recently played")
                stations: page._recentOnly
            }
        }

        ViewPlaceholder {
            enabled: page.favourites.length === 0 && page.recents.length === 0
            text: qsTr("No stations yet")
            hintText: qsTr("Stations you play show here. Press and hold one to keep it as a favourite")
        }

        VerticalScrollDecorator {}
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
