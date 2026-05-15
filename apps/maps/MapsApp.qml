import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme
import QtLocation
import QtPositioning
import QtQuick

MApp {
    id: mapsApp

    property bool showSearch: false
    property var searchResults: []
    property bool isSearching: false
    property bool mapLoaded: false
    property bool hasLocationPermission: false
    property Map mapObject: null
    // Currently-selected place (set after the user picks from search
    // results). Drives the bottom place card per JSX ref-maps.
    property var selectedPlace: null

    function searchLocation(query) {
        if (query.length === 0) {
            searchResults = [];
            return;
        }
        isSearching = true;
        var xhr = new XMLHttpRequest();
        var url = "https://nominatim.openstreetmap.org/search?q=" + encodeURIComponent(query) + "&format=json&limit=5";
        xhr.open("GET", url);
        xhr.setRequestHeader("User-Agent", "MarathonOS/1.0");
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                isSearching = false;
                if (xhr.status === 200) {
                    try {
                        var results = JSON.parse(xhr.responseText);
                        searchResults = results.map(function (result) {
                            return {
                                "name": result.display_name.split(',')[0],
                                "address": result.display_name,
                                "lat": parseFloat(result.lat),
                                "lon": parseFloat(result.lon),
                                "type": result.type
                            };
                        });
                        Logger.info("Maps", "Found " + searchResults.length + " results");
                    } catch (e) {
                        Logger.error("Maps", "Failed to parse search results: " + e);
                        searchResults = [];
                    }
                } else {
                    Logger.error("Maps", "Search request failed: " + xhr.status);
                    searchResults = [];
                }
            }
        };
        xhr.send();
    }

    function goToLocation(lat, lon) {
        if (mapsApp.mapObject) {
            mapsApp.mapObject.center = QtPositioning.coordinate(lat, lon);
            mapsApp.mapObject.zoomLevel = 15;
            showSearch = false;
        }
    }

    appId: "maps"
    appName: "Maps"
    appIcon: "assets/icon.svg"
    onAppLaunched: {
        loadTimer.start();
        if (PermissionManager.hasPermission(appId, "location")) {
            Logger.info("Maps", "Location permission already granted");
            hasLocationPermission = true;
        } else {
            Logger.info("Maps", "Requesting location permission");
            PermissionManager.requestPermission(appId, "location");
        }
    }

    Connections {
        function onPermissionGranted(grantedAppId, permission) {
            if (grantedAppId === appId && permission === "location") {
                Logger.info("Maps", "Location permission granted");
                hasLocationPermission = true;
                positionSource.active = true;
            }
        }

        function onPermissionDenied(deniedAppId, permission) {
            if (deniedAppId === appId && permission === "location") {
                Logger.warn("Maps", "Location permission denied");
                hasLocationPermission = false;
            }
        }

        target: PermissionManager
    }

    Timer {
        id: loadTimer

        interval: 100
        onTriggered: {
            mapLoaded = true;
        }
    }

    PositionSource {
        id: positionSource

        active: mapLoaded && hasLocationPermission
        updateInterval: 5000
        onPositionChanged: {
            if (position.latitudeValid && position.longitudeValid && mapsApp.mapObject) {
                mapsApp.mapObject.center = position.coordinate;
                Logger.info("Maps", "Position updated: " + position.coordinate);
            }
        }
        onSourceErrorChanged: {
            if (sourceError !== PositionSource.NoError)
                Logger.warn("Maps", "Position source error (macOS stub mode)");
        }
    }

    content: Rectangle {
        anchors.fill: parent
        color: MColors.background

        Loader {
            id: mapLoader

            anchors.fill: parent
            active: mapLoaded
            asynchronous: true
            onLoaded: {
                mapsApp.mapObject = item;
            }
            onActiveChanged: {
                if (!active)
                    mapsApp.mapObject = null;
            }

            sourceComponent: Map {
                id: map

                anchors.fill: parent
                center: positionSource.position.valid ? positionSource.position.coordinate : QtPositioning.coordinate(37.7749, -122.419)
                zoomLevel: 14

                MapQuickItem {
                    id: userLocationMarker

                    coordinate: positionSource.position.valid ? positionSource.position.coordinate : map.center
                    anchorPoint.x: locationDot.width / 2
                    anchorPoint.y: locationDot.height / 2

                    sourceItem: Rectangle {
                        id: locationDot

                        width: MSpacing.lg
                        height: MSpacing.lg
                        radius: width / 2
                        color: MColors.marathonTeal
                        border.width: Constants.borderWidthThick
                        border.color: "white"

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width * 0.4
                            height: parent.height * 0.4
                            radius: width / 2
                            color: "white"
                        }
                    }
                }

                plugin: Plugin {
                    name: "osm"
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            color: MColors.background
            visible: !mapLoaded

            Column {
                anchors.centerIn: parent
                spacing: MSpacing.lg

                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "map"
                    size: Constants.iconSizeXLarge * 2
                    color: MColors.marathonTeal

                    RotationAnimation on rotation {
                        running: !mapLoaded
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 2000
                    }
                }

                MLabel {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Loading map..."
                    variant: "secondary"
                    font.pixelSize: MTypography.sizeLarge
                }
            }
        }

        // ── Floating search bar (JSX ref-maps top chrome) ─────
        // Glass-titlebar fill, 1 px tealBorder outer + w-04 inner. Holds
        // a magnifier, the search input (or selected-place title when a
        // pin is active), and a 36 px circle avatar/clear toggle.
        Rectangle {
            id: searchBar

            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 12
            height: 56
            radius: MRadius.md
            color: MColors.glassTitlebar
            border.width: 1
            border.color: mapsApp.selectedPlace ? MColors.tealBorder : MColors.whiteOverlay08
            z: 100

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                color: "transparent"
                border.width: 1
                border.color: MColors.whiteOverlay04
            }

            Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                anchors.rightMargin: 8
                spacing: 12

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: isSearching ? "loader" : "search"
                    size: 20
                    color: MColors.textSecondary
                    RotationAnimation on rotation {
                        running: isSearching
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 1000
                    }
                }

                // When a place is selected, show its name + address as a
                // static label. The input only shows while typing.
                Column {
                    visible: mapsApp.selectedPlace !== null
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 20 - 36 - parent.spacing * 2
                    spacing: 2
                    Text {
                        width: parent.width
                        text: mapsApp.selectedPlace ? mapsApp.selectedPlace.name : ""
                        color: MColors.textPrimary
                        font.family: MTypography.fontFamily
                        font.pixelSize: MTypography.sizeSubhead
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: mapsApp.selectedPlace ? mapsApp.selectedPlace.address : ""
                        color: MColors.textSecondary
                        font.family: MTypography.fontFamily
                        font.pixelSize: MTypography.sizeFootnote
                        elide: Text.ElideRight
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            HapticService.light();
                            mapsApp.selectedPlace = null;
                            searchInput.forceActiveFocus();
                        }
                    }
                }

                MTextInput {
                    id: searchInput

                    visible: mapsApp.selectedPlace === null
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 20 - 36 - parent.spacing * 2
                    placeholderText: "Search Maps"
                    onTextChanged: {
                        showSearch = text.length > 0;
                        if (text.length > 2)
                            searchTimer.restart();
                    }
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 36
                    height: 36
                    radius: width / 2
                    color: MColors.elev3
                    border.width: 1
                    border.color: MColors.whiteOverlay08
                    Icon {
                        anchors.centerIn: parent
                        name: searchInput.text.length > 0 || mapsApp.selectedPlace ? "x" : "user"
                        size: 16
                        color: MColors.textSecondary
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            HapticService.light();
                            if (mapsApp.selectedPlace) {
                                mapsApp.selectedPlace = null;
                                return;
                            }
                            searchInput.text = "";
                            showSearch = false;
                        }
                    }
                }
            }
        }

        Timer {
            id: searchTimer

            interval: 500
            onTriggered: {
                searchLocation(searchInput.text);
            }
        }

        Rectangle {
            id: searchResultsPanel

            anchors.top: searchBar.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: MSpacing.md
            anchors.topMargin: MSpacing.sm
            height: Math.min(searchResultsList.contentHeight + MSpacing.md * 2, parent.height * 0.5)
            color: MColors.surface
            radius: Constants.borderRadiusSharp
            border.width: Constants.borderWidthMedium
            border.color: MColors.border
            visible: showSearch && searchResults.length > 0
            z: 99

            ListView {
                id: searchResultsList

                anchors.fill: parent
                anchors.margins: MSpacing.sm
                clip: true
                model: searchResults

                delegate: Item {
                    width: searchResultsList.width
                    height: Constants.touchTargetLarge + MSpacing.sm

                    MCard {
                        anchors.fill: parent
                        anchors.margins: MSpacing.xs
                        interactive: true
                        onClicked: {
                            HapticService.light();
                            Logger.info("Maps", "Selected: " + modelData.name);
                            mapsApp.selectedPlace = modelData;
                            showSearch = false;
                            goToLocation(modelData.lat, modelData.lon);
                        }

                        Row {
                            anchors.fill: parent
                            spacing: MSpacing.md

                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "map-pin"
                                size: Constants.iconSizeMedium
                                color: MColors.marathonTeal
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - parent.children[0].width - parent.spacing
                                spacing: MSpacing.xs

                                MLabel {
                                    width: parent.width
                                    text: modelData.name
                                    variant: "primary"
                                    font.pixelSize: MTypography.sizeBody
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }

                                MLabel {
                                    width: parent.width
                                    text: modelData.address
                                    variant: "secondary"
                                    font.pixelSize: MTypography.sizeSmall
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }

        Column {
            anchors.right: parent.right
            anchors.bottom: locateButton.top
            anchors.margins: MSpacing.md
            anchors.bottomMargin: MSpacing.sm
            spacing: MSpacing.sm
            z: 100

            MCircularIconButton {
                iconName: "plus"
                iconSize: 20
                buttonSize: 48
                variant: "secondary"
                onClicked: {
                    HapticService.light();
                    if (mapsApp.mapObject)
                        mapsApp.mapObject.zoomLevel = Math.min(mapsApp.mapObject.zoomLevel + 1, mapsApp.mapObject.maximumZoomLevel);
                }
            }

            MCircularIconButton {
                iconName: "minus"
                iconSize: 20
                buttonSize: 48
                variant: "secondary"
                onClicked: {
                    HapticService.light();
                    if (mapsApp.mapObject)
                        mapsApp.mapObject.zoomLevel = Math.max(mapsApp.mapObject.zoomLevel - 1, mapsApp.mapObject.minimumZoomLevel);
                }
            }
        }

        MCircularIconButton {
            id: locateButton

            anchors.right: parent.right
            anchors.bottom: placeCard.visible ? placeCard.top : parent.bottom
            anchors.margins: MSpacing.md
            iconName: "navigation"
            iconSize: 24
            buttonSize: 56
            variant: "primary"
            onClicked: {
                HapticService.medium();
                if (positionSource.position.valid && mapsApp.mapObject) {
                    mapsApp.mapObject.center = positionSource.position.coordinate;
                    mapsApp.mapObject.zoomLevel = 15;
                    Logger.info("Maps", "Centered on current location");
                } else {
                    Logger.warn("Maps", "Position not available");
                }
            }
        }

        // ── Place card (JSX ref-maps bottom chrome) ───────────
        // Visible only when a search result is selected. 64×64 teal
        // gradient bay + place name + meta (address) + ★rating +
        // four-action row: Directions (teal accent) · Call · Share · Save.
        Rectangle {
            id: placeCard
            visible: mapsApp.selectedPlace !== null
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 12
            height: 168
            radius: MRadius.md
            color: MColors.elev2
            border.width: 1
            border.color: MColors.whiteOverlay04
            z: 90

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: parent.radius - 1
                color: "transparent"
                border.width: 1
                border.color: MColors.whiteOverlay04
            }

            Row {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 16
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 14

                // 64 × 64 squircle bay with map-pin glyph.
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 64
                    height: 64
                    radius: MRadius.squircle
                    border.width: 1
                    border.color: MColors.tealBorder
                    gradient: Gradient {
                        GradientStop {
                            position: 0
                            color: Qt.rgba(0, 89 / 255, 77 / 255, 0.55)
                        }
                        GradientStop {
                            position: 1
                            color: Qt.rgba(4 / 255, 4 / 255, 4 / 255, 0.85)
                        }
                    }
                    Icon {
                        anchors.centerIn: parent
                        name: "map-pin"
                        size: 28
                        color: MColors.marathonTealBright
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 64 - parent.spacing
                    spacing: 4

                    Text {
                        width: parent.width
                        text: mapsApp.selectedPlace ? mapsApp.selectedPlace.name : ""
                        color: MColors.textPrimary
                        font.family: MTypography.fontFamily
                        font.pixelSize: 20
                        font.weight: Font.Medium
                        font.letterSpacing: -0.3
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: mapsApp.selectedPlace ? mapsApp.selectedPlace.address : ""
                        color: MColors.textSecondary
                        font.family: MTypography.fontFamily
                        font.pixelSize: MTypography.sizeFootnote
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                    // ★ rating / price line — placeholder until Nominatim
                    // results include richer business metadata. Empty when
                    // no data so the row collapses cleanly.
                    Row {
                        spacing: 8
                        visible: mapsApp.selectedPlace && mapsApp.selectedPlace.type
                        Text {
                            text: (mapsApp.selectedPlace && mapsApp.selectedPlace.type) ? mapsApp.selectedPlace.type : ""
                            color: MColors.textTertiary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeFootnote
                            font.capitalization: Font.Capitalize
                        }
                    }
                }
            }

            // Action row — Directions (teal accent) · Call · Share · Save.
            Row {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottomMargin: 14

                Repeater {
                    model: [
                        {
                            label: "Directions",
                            icon: "navigation",
                            accent: true
                        },
                        {
                            label: "Call",
                            icon: "phone",
                            accent: false
                        },
                        {
                            label: "Share",
                            icon: "share-2",
                            accent: false
                        },
                        {
                            label: "Save",
                            icon: "star",
                            accent: false
                        }
                    ]
                    delegate: Item {
                        width: parent.width / 4
                        height: 48
                        Column {
                            anchors.centerIn: parent
                            spacing: 4
                            Icon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                name: modelData.icon
                                size: 20
                                color: modelData.accent ? MColors.marathonTealBright : MColors.textSecondary
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.label
                                color: modelData.accent ? MColors.marathonTealBright : MColors.textSecondary
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeEyebrow
                                font.weight: Font.Medium
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: HapticService.light()
                        }
                    }
                }
            }
        }
    }
}
