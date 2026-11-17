pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../components"

// The world's radio on a globe. Turn it until a place sits in the ring:
// its stations line up below, local FM first. While the radio is on,
// settling on a place tunes to it.
Page {
    id: page

    property var app
    readonly property var radio: app.radio
    property var stations: []
    property int _loadedPlace: -1

    function placeName(i) {
        return i >= 0 && i < radio.places.length ? radio.places[i][2] : "";
    }

    function openList(title, load) {
        pageStack.animatorPush(Qt.resolvedUrl("StationsPage.qml"), {
            app: page.app,
            title: title,
            load: load
        });
    }

    function goHome() {
        const h = radio.home;
        if (h)
            globe.flyTo(h[0], h[1], 1.5);
    }

    backNavigation: false
    showNavigationIndicator: false

    Connections {
        target: page.radio
        function onPlacesLoaded() {
            if (globe.selected < 0)
                page.goHome();
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#040404"
    }

    Globe {
        id: globe

        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            bottom: mini.top
        }
        places: page.radio.places
        Component.onCompleted: {
            const h = page.radio.home;
            if (h) {
                lat = h[0];
                lon = h[1];
            }
        }
        onSettled: {
            if (selected < 0 || selected === page._loadedPlace)
                return;
            page._loadedPlace = selected;
            const place = selected;
            page.radio.placeStations(place, list => {
                if (globe.selected !== place)
                    return;
                page.stations = list;
                Qt.callLater(strip.positionViewAtBeginning);
                // A dial turned while listening: the place's first station.
                if (page.radio.playing && list.length > 0 && !list.some(s => page.radio.station && s.id === page.radio.station.id))
                    page.radio.play(list[0], list);
            });
        }
        onMovingChanged: {
            if (moving)
                page._loadedPlace = -1;
        }
    }

    // The ring the places snap into.
    Rectangle {
        id: ring

        readonly property bool locked: globe.selected >= 0 && !globe.moving
        anchors.centerIn: globe
        width: locked ? Theme.itemSizeExtraSmall : Theme.itemSizeSmall
        height: width
        radius: width / 2
        color: "transparent"
        border.width: Math.max(2, Math.round(Theme.paddingSmall / 3))
        border.color: locked ? Theme.highlightColor : Theme.rgba(Theme.primaryColor, 0.35)
        Behavior on width {
            NumberAnimation {
                duration: 220
                easing.type: Easing.OutBack
            }
        }
        Behavior on border.color {
            ColorAnimation {
                duration: 180
            }
        }
    }

    // Where the ring is: the place, or how to find one.
    Rectangle {
        id: top

        width: parent.width
        height: header.height + Theme.paddingLarge * 2
        gradient: Gradient {
            GradientStop {
                position: 0
                color: Theme.rgba("#040404", 0.92)
            }
            GradientStop {
                position: 1
                color: "transparent"
            }
        }

        Column {
            id: header

            anchors {
                left: parent.left
                leftMargin: Theme.horizontalPageMargin
                right: tools.left
                top: parent.top
                topMargin: Theme.paddingLarge
            }

            Label {
                width: parent.width
                text: {
                    if (!page.radio.ready)
                        return page.radio.failed ? qsTr("No stations yet") : qsTr("Finding stations…");
                    return globe.selected >= 0 ? page.placeName(globe.selected) : qsTr("Turn the globe");
                }
                font.pixelSize: Theme.fontSizeLarge
                color: globe.selected >= 0 ? Theme.highlightColor : Theme.primaryColor
                truncationMode: TruncationMode.Fade
            }
            Label {
                width: parent.width
                text: {
                    if (!page.radio.ready)
                        return page.radio.failed ? qsTr("Connect to the internet to see the world's stations") : "";
                    if (globe.selected < 0)
                        return qsTr("%1 places with radio").arg(page.radio.places.length);
                    return page.radio.stationCount(page.radio.places[globe.selected][3]);
                }
                font.pixelSize: Theme.fontSizeExtraSmall
                color: Theme.secondaryColor
                truncationMode: TruncationMode.Fade
            }
        }

        Row {
            id: tools

            anchors {
                right: parent.right
                rightMargin: Theme.horizontalPageMargin - Theme.paddingMedium
                top: parent.top
                topMargin: Theme.paddingMedium
            }

            IconButton {
                objectName: "searchButton"
                icon.source: "image://theme/icon-m-search"
                Accessible.name: qsTr("Search")
                onClicked: pageStack.animatorPush(Qt.resolvedUrl("SearchPage.qml"), {
                    app: page.app
                })
            }
            IconButton {
                objectName: "localButton"
                icon.source: "image://theme/icon-m-location"
                Accessible.name: qsTr("Around you")
                onClicked: {
                    page.goHome();
                    page.openList(qsTr("Around you"), done => page.radio.local(done));
                }
            }
            IconButton {
                objectName: "favouritesButton"
                icon.source: "image://theme/icon-m-favorite"
                Accessible.name: qsTr("Favourites")
                onClicked: pageStack.animatorPush(Qt.resolvedUrl("LibraryPage.qml"), {
                    app: page.app
                })
            }
        }
    }

    BusyIndicator {
        anchors.centerIn: globe
        size: BusyIndicatorSize.Large
        running: !page.radio.ready && !page.radio.failed
    }

    // Keeps the station names clear of the globe behind them.
    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            bottom: mini.top
        }
        height: strip.height + Theme.paddingLarge * 2
        opacity: strip.opacity
        gradient: Gradient {
            GradientStop {
                position: 0
                color: "transparent"
            }
            GradientStop {
                position: 0.45
                color: Theme.rgba("#040404", 0.75)
            }
            GradientStop {
                position: 1
                color: Theme.rgba("#040404", 0.92)
            }
        }
    }

    // The place's stations, swiped through and tapped to play.
    ListView {
        id: strip

        anchors {
            left: parent.left
            right: parent.right
            bottom: mini.top
            bottomMargin: Theme.paddingMedium
        }
        height: Theme.itemSizeHuge
        orientation: ListView.Horizontal
        spacing: Theme.paddingMedium
        model: globe.selected >= 0 && !globe.moving ? page.stations : []
        opacity: count > 0 ? 1 : 0
        clip: true
        Behavior on opacity {
            FadeAnimation {}
        }

        header: Item {
            width: Theme.horizontalPageMargin - Theme.paddingMedium * 2
            height: strip.height
        }
        footer: Item {
            width: (more.visible ? more.width + Theme.paddingMedium : 0) + Theme.horizontalPageMargin
            height: strip.height

            BackgroundItem {
                id: more

                visible: page.stations.length > 4
                x: Theme.paddingMedium
                width: Theme.itemSizeHuge * 0.8
                height: parent.height
                onClicked: page.openList(page.placeName(globe.selected), done => page.radio.placeStations(globe.selected, done))

                Label {
                    anchors.centerIn: parent
                    width: parent.width - Theme.paddingMedium
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: qsTr("All %1").arg(page.stations.length)
                    color: more.highlighted ? Theme.highlightColor : Theme.secondaryHighlightColor
                    font.pixelSize: Theme.fontSizeSmall
                }
            }
        }

        delegate: BackgroundItem {
            id: card

            required property var modelData
            readonly property bool current: page.radio.station !== null && page.radio.station.id === modelData.id

            width: Theme.itemSizeHuge * 0.8
            height: strip.height
            onClicked: page.radio.play(modelData, page.stations)
            Accessible.name: modelData.name

            StationArt {
                id: cardArt

                anchors.horizontalCenter: parent.horizontalCenter
                y: Theme.paddingSmall
                width: parent.width - Theme.paddingMedium * 2
                height: width
                station: card.modelData
                border.width: card.current ? 2 : 0
                border.color: Theme.highlightColor
            }
            Rectangle {
                visible: card.modelData.fm > 0
                anchors {
                    right: cardArt.right
                    top: cardArt.top
                    margins: Theme.paddingSmall / 2
                }
                width: fmLabel.width + Theme.paddingSmall
                height: fmLabel.height
                radius: 2
                color: Theme.highlightColor

                Label {
                    id: fmLabel

                    anchors.centerIn: parent
                    text: "FM"
                    font.pixelSize: Theme.fontSizeTiny
                    font.weight: Font.DemiBold
                    color: "#000000"
                }
            }
            Label {
                anchors {
                    top: cardArt.bottom
                    topMargin: Theme.paddingSmall
                    horizontalCenter: parent.horizontalCenter
                }
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: card.modelData.name
                elide: Text.ElideRight
                font.pixelSize: Theme.fontSizeExtraSmall
                color: card.current || card.highlighted ? Theme.highlightColor : Theme.primaryColor
            }
        }
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
