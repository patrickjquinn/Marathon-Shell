pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../components"

// The world's radio on a globe. Tap a place, or turn it into the ring:
// its stations line up below, local FM first, to play from there. The
// globe itself never changes what is playing.
Page {
    id: page

    property var app
    readonly property var radio: app.radio
    property var stations: []
    property int _loadedPlace: -1
    // Where the location button takes the globe: a country fills the screen.
    readonly property real _localZoom: 7
    readonly property var location: typeof Location !== "undefined" ? Location : null
    readonly property var permissions: typeof Permissions !== "undefined" ? Permissions : null
    readonly property bool _fixed: location !== null && location.available && (location.latitude !== 0 || location.longitude !== 0)
    property bool _locating: false

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
            globe.flyTo(h[0], h[1], _localZoom);
    }

    // Where to open: the station on, if it has a place, else home.
    function goStart() {
        const s = radio.station;
        if (radio.playing && s && s.lat !== undefined)
            globe.flyTo(s.lat, s.lon, _localZoom);
        else
            goHome();
    }

    // The globe to where the phone is: GeoClue's fix, asked for once and
    // let go of when it comes; the time zone's city meanwhile.
    function locate() {
        if (_fixed) {
            globe.flyTo(location.latitude, location.longitude, _localZoom);
            return;
        }
        goHome();
        if (location === null)
            return;
        if (permissions !== null && !permissions.hasPermission(app.appId, "location")) {
            permissions.requestPermission(app.appId, "location");
            return;
        }
        _locating = true;
        location.start();
        locateTimeout.restart();
    }

    function _stopLocating() {
        if (_locating && location !== null)
            location.stop();
        _locating = false;
        locateTimeout.stop();
    }

    // Whether a place is the one the phone is in, give or take a city.
    function _isHome(i) {
        const h = _fixed ? [location.latitude, location.longitude] : radio.home;
        return h && i >= 0 && globe._distance(h[0], h[1], radio.places[i][0], radio.places[i][1]) < 0.5;
    }

    function openMore() {
        if (_isHome(globe.selected))
            openList(qsTr("Around you"), done => radio.local(done));
        else
            openList(placeName(globe.selected), done => radio.placeStations(globe.selected, done));
    }

    backNavigation: false
    showNavigationIndicator: false

    Connections {
        target: page.radio
        function onPlacesLoaded() {
            if (globe.selected < 0)
                page.goStart();
        }
    }

    Connections {
        target: page.location
        enabled: page._locating
        function onLocationChanged() {
            if (!page._fixed)
                return;
            page._stopLocating();
            globe.flyTo(page.location.latitude, page.location.longitude, page._localZoom);
        }
    }

    Connections {
        target: page.permissions
        ignoreUnknownSignals: true
        function onPermissionGranted(appId, permission) {
            if (appId === page.app.appId && permission === "location")
                page.locate();
        }
    }

    Timer {
        id: locateTimeout

        interval: 30000
        onTriggered: page._stopLocating()
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
        reach: Theme.itemSizeSmall / 2
        inputInset: strip.count > 0 ? height - strip.y : 0
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
                Accessible.name: qsTr("Where you are")
                onClicked: page.locate()
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

                objectName: "moreButton"
                visible: page.stations.length > 1 || page._isHome(globe.selected)
                x: Theme.paddingMedium
                width: Theme.itemSizeHuge * 0.8
                height: parent.height
                onClicked: page.openMore()
                Accessible.name: moreLabel.text

                Column {
                    anchors.centerIn: parent
                    width: parent.width - Theme.paddingMedium
                    spacing: Theme.paddingSmall

                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        source: "image://theme/icon-m-right"
                        highlighted: more.highlighted
                    }
                    Label {
                        id: moreLabel

                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: page._isHome(globe.selected) ? qsTr("Around you") : qsTr("All %1").arg(page.stations.length)
                        color: more.highlighted ? Theme.highlightColor : Theme.secondaryHighlightColor
                        font.pixelSize: Theme.fontSizeExtraSmall
                    }
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
