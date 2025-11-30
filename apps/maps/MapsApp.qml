import QtQuick
import QtLocation
import QtPositioning
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Theme

MApp {
    id: mapsApp
    appId: "maps"
    appName: "Maps"
    appIcon: "assets/icon.svg"

    property bool showSearch: false
    property var searchResults: []
    property bool isSearching: false
    property bool mapLoaded: false
    property bool hasLocationPermission: false

    onAppLaunched: {
        loadTimer.start();

        // Check location permission
        if (typeof PermissionManager !== 'undefined') {
            if (PermissionManager.hasPermission(appId, "location")) {
                Logger.info("Maps", "Location permission already granted");
                hasLocationPermission = true;
            } else {
                Logger.info("Maps", "Requesting location permission");
                PermissionManager.requestPermission(appId, "location");
            }
        } else {
            Logger.warn("Maps", "PermissionManager not available, auto-granting");
            hasLocationPermission = true;
        }
    }

    // Listen for permission responses
    Connections {
        target: typeof PermissionManager !== 'undefined' ? PermissionManager : null

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
            if (position.latitudeValid && position.longitudeValid && mapLoader.item) {
                mapLoader.item.center = position.coordinate;
                Logger.info("Maps", "Position updated: " + position.coordinate);
            }
        }

        onSourceErrorChanged: {
            if (sourceError !== PositionSource.NoError) {
                Logger.warn("Maps", "Position source error (macOS stub mode)");
            }
        }
    }

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
                                name: result.display_name.split(',')[0],
                                address: result.display_name,
                                lat: parseFloat(result.lat),
                                lon: parseFloat(result.lon),
                                type: result.type
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
        if (mapLoader.item) {
            mapLoader.item.center = QtPositioning.coordinate(lat, lon);
            mapLoader.item.zoomLevel = 15;
            showSearch = false;
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

            sourceComponent: Map {
                id: map
                anchors.fill: parent

                plugin: Plugin {
                    name: "osm"
                }

                center: positionSource.position.valid ? positionSource.position.coordinate : QtPositioning.coordinate(37.7749, -122.4194)
                zoomLevel: 14

                // Gestures are enabled by default in Qt 6
                // gesture.enabled: true removed - not a valid property

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

        Row {
            id: searchBar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: MSpacing.md
            height: Constants.touchTargetLarge
            spacing: MSpacing.sm
            z: 100

            Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: isSearching ? "loader" : "search"
                size: Constants.iconSizeMedium
                color: MColors.textSecondary

                RotationAnimation on rotation {
                    running: isSearching
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 1000
                }
            }

            MTextInput {
                id: searchInput
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - parent.spacing * 3 - Constants.iconSizeMedium * 2
                placeholderText: "Search for places..."

                onTextChanged: {
                    showSearch = text.length > 0;
                    if (text.length > 2) {
                        searchTimer.restart();
                    }
                }
            }

            MIconButton {
                anchors.verticalCenter: parent.verticalCenter
                iconName: "x"
                iconSize: 20
                variant: "secondary"
                visible: searchInput.text.length > 0
                onClicked: {
                    searchInput.text = "";
                    showSearch = false;
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

                        onClicked: {
                            HapticService.light();
                            Logger.info("Maps", "Selected: " + modelData.name);
                            goToLocation(modelData.lat, modelData.lon);
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
                    if (mapLoader.item) {
                        mapLoader.item.zoomLevel = Math.min(mapLoader.item.zoomLevel + 1, mapLoader.item.maximumZoomLevel);
                    }
                }
            }

            MCircularIconButton {
                iconName: "minus"
                iconSize: 20
                buttonSize: 48
                variant: "secondary"
                onClicked: {
                    HapticService.light();
                    if (mapLoader.item) {
                        mapLoader.item.zoomLevel = Math.max(mapLoader.item.zoomLevel - 1, mapLoader.item.minimumZoomLevel);
                    }
                }
            }
        }

        MCircularIconButton {
            id: locateButton
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: MSpacing.md
            iconName: "navigation"
            iconSize: 24
            buttonSize: 56
            variant: "primary"
            onClicked: {
                HapticService.medium();
                if (positionSource.position.valid && mapLoader.item) {
                    mapLoader.item.center = positionSource.position.coordinate;
                    mapLoader.item.zoomLevel = 15;
                    Logger.info("Maps", "Centered on current location");
                } else {
                    Logger.warn("Maps", "Position not available");
                }
            }
        }
    }
}
