import MarathonApp.Maps
import MarathonOS.Shell
import MarathonUI.Containers
import MarathonUI.Core
import MarathonUI.Effects
import MarathonUI.Theme
import QtPositioning
import QtQuick
import QtWebChannel
import QtWebEngine

MApp {
    id: mapsApp

    property bool showSearch: false
    property var searchResults: []
    property bool isSearching: false
    property bool mapLoaded: false
    property bool hasLocationPermission: false
    // Reference to the WebEngineView running MapLibre GL JS. Commands
    // are issued via runJavaScript() against the window.MarathonMaps
    // facade defined in apps/maps/web/maps.html. Inbound events arrive
    // through the MapsBridge instance declared below (id: mapsBridge).
    property var mapsView: null
    // True once MapLibre's style.load has fired and the QWebChannel
    // handshake has completed. Bridge cmds before this point are no-ops.
    property bool mapsReady: false
    // Currently-selected place (set after the user picks from search
    // results). Drives the bottom place card per JSX ref-maps.
    property var selectedPlace: null

    // Routing state machine. Drives which bottom-overlay surface is
    // visible:
    //   "idle"    — search bar + place card (or empty map)
    //   "preview" — route summary card (ETA, distance, Start)
    //   "active"  — top maneuver banner + slim collapsed card
    property string routingMode: "idle"
    property var currentRoute: null  // QVariantMap from ValhallaRoutingClient
    property int currentManeuverIndex: 0
    property string currentMode: "auto"  // "auto" | "pedestrian" | "bicycle"

    // Active-navigation lifecycle claim. While routingMode === "active" the
    // app holds the shell-side "active-navigation" capability so the
    // backgrounded runner is kept warm (BackgroundActive, never frozen).
    // The handle is released the moment routingMode leaves "active" — by
    // arrival, cancel, or any other path.
    property int _navTaskHandle: 0
    onRoutingModeChanged: {
        if (typeof AppLifecycle === "undefined")
            return;
        if (routingMode === "active") {
            if (_navTaskHandle === 0)
                _navTaskHandle = AppLifecycle.beginBackgroundTask("active-navigation", "turn-by-turn route");
        } else if (_navTaskHandle !== 0) {
            AppLifecycle.endBackgroundTask(_navTaskHandle);
            _navTaskHandle = 0;
        }
    }

    // Map command facade. Calling `mapCall("setCenter", lat, lon)`
    // resolves to runJavaScript("window.MarathonMaps.setCenter(lat,lon)")
    // — but only after mapsReady. Pre-ready calls queue (replaying once
    // the bridge fires its ready() signal) so the first
    // setUserLocation/setCenter that fires before MapLibre boots
    // doesn't silently disappear.
    property var _pendingCalls: []
    function mapCall(method) {
        if (!mapsView)
            return;
        const args = Array.prototype.slice.call(arguments, 1);
        const payload = args.map(a => JSON.stringify(a)).join(",");
        const js = "if(window.MarathonMaps&&window.MarathonMaps." + method + ")" + "window.MarathonMaps." + method + "(" + payload + ");";
        if (mapsReady) {
            mapsView.runJavaScript(js);
        } else {
            _pendingCalls.push(js);
        }
    }
    function _flushPending() {
        if (!mapsView || !mapsReady)
            return;
        for (let i = 0; i < _pendingCalls.length; i++)
            mapsView.runJavaScript(_pendingCalls[i]);
        _pendingCalls = [];
    }

    // Geoclue2 fix from the shell's LocationManager arrives via the
    // LocationService DBus client. We prefer it over QtPositioning's
    // PositionSource on Linux because (a) it's already aware of the
    // AGPS XEP from cellular networks (NetworkManager/ModemManager
    // assist), (b) it's the single shared fix the rest of the system
    // sees, and (c) on desktop dev Geoclue often resolves via IP/WiFi
    // when QtPositioning would otherwise return nothing.
    readonly property bool geoclueAvailable: (typeof LocationService !== "undefined" && LocationService !== null) ? (LocationService.available === true) : false
    readonly property bool geoclueValid: geoclueAvailable && LocationService.latitude !== 0.0 && LocationService.longitude !== 0.0

    // Best-known fix: Geoclue if we have one, else QtPositioning, else
    // a sensible default (San Francisco) so the map renders something
    // before the first reply lands.
    readonly property var bestCoord: {
        if (geoclueValid)
            return QtPositioning.coordinate(LocationService.latitude, LocationService.longitude);
        if (positionSource.position.coordinate.isValid)
            return positionSource.position.coordinate;
        return QtPositioning.coordinate(37.7749, -122.419);
    }
    readonly property bool bestCoordValid: geoclueValid || (typeof positionSource !== "undefined" && positionSource.position && positionSource.position.coordinate && positionSource.position.coordinate.isValid === true)

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
        mapCall("setCenter", lat, lon, 15);
        showSearch = false;
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
                // Kick off the shell-side Geoclue fix via the IPC
                // client. The fix arrives asynchronously and updates
                // `bestCoord` reactively.
                if (typeof LocationService !== "undefined" && LocationService)
                    LocationService.start();
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

    // Recentre the map whenever the Geoclue fix updates — but only
    // before the user has manually moved or selected a place. After
    // that point we leave the camera where they put it.
    Connections {
        function onLocationChanged() {
            if (mapsApp.geoclueValid) {
                mapCall("setUserLocation", LocationService.latitude, LocationService.longitude);
                if (!mapsApp.selectedPlace)
                    mapCall("setCenter", LocationService.latitude, LocationService.longitude);
                Logger.info("Maps", "Geoclue fix → " + LocationService.latitude + "," + LocationService.longitude + " ±" + LocationService.accuracy + "m");
            }
        }
        target: mapsApp.geoclueAvailable ? LocationService : null
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

        active: mapLoaded && hasLocationPermission && !mapsApp.geoclueValid
        updateInterval: 5000
        onPositionChanged: {
            if (position.latitudeValid && position.longitudeValid) {
                const c = position.coordinate;
                mapCall("setUserLocation", c.latitude, c.longitude);
                if (!mapsApp.selectedPlace)
                    mapCall("setCenter", c.latitude, c.longitude);
            }
        }
        onSourceErrorChanged: {
            if (sourceError !== PositionSource.NoError)
                Logger.warn("Maps", "Position source error (macOS stub mode)");
        }
    }

    // ── Routing & voice clients ────────────────────────────────
    // ValhallaRoutingClient (C++/QML_ELEMENT) POSTs to the public
    // valhalla1.openstreetmap.de endpoint and decodes the response
    // into a GeoJSON polyline + maneuver list. The polyline is handed
    // to the WebEngineView's window.MarathonMaps.setRouteGeoJSON()
    // facade; the maneuver list drives the active-nav banner UI.
    ValhallaRoutingClient {
        id: routingService
        onRouteReady: (geojson, maneuvers, durationSec, distanceM, summary) => {
            mapsApp.currentRoute = {
                "geojson": geojson,
                "maneuvers": maneuvers,
                "duration": durationSec,
                "distance": distanceM,
                "summary": summary
            };
            mapsApp.currentManeuverIndex = 0;
            mapsApp.routingMode = "preview";
            mapCall("setRouteGeoJSON", geojson);
            if (summary)
                mapCall("fitBounds", summary.minLon, summary.minLat, summary.maxLon, summary.maxLat, 80);
            Logger.info("Maps", "Route ready: " + Math.round(distanceM / 1000) + " km, " + Math.round(durationSec / 60) + " min, " + maneuvers.length + " maneuvers");
        }
        onRouteFailed: err => {
            Logger.warn("Maps", "Route failed: " + err);
        }
    }

    function startNavigation() {
        if (!mapsApp.currentRoute || !mapsApp.currentRoute.maneuvers)
            return;
        mapsApp.routingMode = "active";
        mapsApp.currentManeuverIndex = 0;
        const m = mapsApp.currentRoute.maneuvers[0];
        if (m && voiceClient && voiceClient.available && !voiceClient.muted)
            voiceClient.speak(m.verbalPre && m.verbalPre.length > 0 ? m.verbalPre : m.instruction);
    }

    function endNavigation() {
        mapsApp.routingMode = "idle";
        mapsApp.currentRoute = null;
        mapsApp.currentManeuverIndex = 0;
        mapCall("setRouteGeoJSON", {
            "type": "FeatureCollection",
            "features": []
        });
        if (voiceClient && voiceClient.available)
            voiceClient.stop();
    }

    // VoiceClient is QML_ELEMENT-registered ONLY when Qt6::TextToSpeech
    // is found at configure time (MAPS_HAS_VOICE). On the dev rig
    // without qt6-qtspeech installed the type isn't registered, so we
    // can't reference `VoiceClient { }` at parse time — Qt would
    // refuse to load MapsApp.qml entirely. Instead we createQmlObject
    // at startup which fails gracefully if the type is missing.
    property var voiceClient: null
    Component.onCompleted: {
        try {
            voiceClient = Qt.createQmlObject("import MarathonApp.Maps; VoiceClient {}", mapsApp, "VoiceClientDynamic");
        } catch (e) {
            Logger.info("Maps", "VoiceClient unavailable (qt6-qtspeech not installed); nav cues will be silent");
            voiceClient = null;
        }
    }

    content: Rectangle {
        anchors.fill: parent
        color: MColors.background

        // MapLibre GL JS host. The basemap, vector tile rendering,
        // route polylines, and pins all live inside this WebEngineView;
        // every surrounding QML overlay (search bar, place card, nav
        // banner) is layered on top via z-order. The HTML harness +
        // MapLibre bundle + Marathon Dark style JSON ship under the
        // app's install root (web/).
        //
        // MARATHON_APP_PATH is the app-runner-supplied install root;
        // empty for direct-QML runs, where we fall back to the dev
        // user-local install path.
        MapsBridge {
            id: mapsBridge

            WebChannel.id: "marathonBridge"
            onReady: {
                mapsApp.mapsReady = true;
                mapsApp._flushPending();
                if (mapsApp.geoclueValid)
                    mapCall("setUserLocation", LocationService.latitude, LocationService.longitude);
                mapCall("setCenter", mapsApp.bestCoord.latitude, mapsApp.bestCoord.longitude, 14);
            }
            onMapClicked: (lat, lon) => {
                Logger.info("Maps", "JS mapClicked " + lat + "," + lon);
            }
            onPinTapped: id => {
                Logger.info("Maps", "JS pinTapped " + id);
            }
        }

        WebChannel {
            id: webChannel

            registeredObjects: [mapsBridge]
        }

        WebEngineView {
            id: webMap

            anchors.fill: parent
            visible: mapLoaded
            webChannel: webChannel
            backgroundColor: "#0a1814"
            settings.javascriptEnabled: true
            settings.localContentCanAccessFileUrls: true
            settings.localContentCanAccessRemoteUrls: true
            settings.allowRunningInsecureContent: false
            settings.errorPageEnabled: false
            settings.showScrollBars: false
            url: {
                const root = (typeof MARATHON_APP_PATH !== "undefined" && MARATHON_APP_PATH) ? String(MARATHON_APP_PATH) : "";
                if (root.length > 0)
                    return "file://" + root + "/web/maps.html";
                return "file:///home/" + (typeof userName !== "undefined" ? userName : "") + "/.local/share/marathon-apps/maps/web/maps.html";
            }
            onJavaScriptConsoleMessage: (level, message, lineNumber, source) => {
                if (level >= WebEngineView.WarningMessageLevel)
                    Logger.warn("Maps:WebJS", source + ":" + lineNumber + " " + message);
                else
                    Logger.info("Maps:WebJS", message);
            }
            Component.onCompleted: {
                mapsApp.mapsView = webMap;
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

            MTopHairline {
                radius: parent.radius
                color: MColors.whiteOverlay04
                lineWidth: 1
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

        // ── Recenter button (JSX ref-maps right-side glass square) ──
        // 42×42 glass-titlebar square, 4 px radius, 14 px from the right
        // edge, vertical position 200 px from the top. Tap returns the
        // camera to the live Geoclue fix at zoom 15. MapLibre handles
        // pinch zoom natively so no zoom +/- buttons (per JSX spec).
        Rectangle {
            id: locateButton

            anchors.right: parent.right
            anchors.rightMargin: 14
            y: 200
            width: 42
            height: 42
            radius: MRadius.md
            color: MColors.glassTitlebar
            border.width: 1
            border.color: MColors.whiteOverlay08
            z: 100

            Icon {
                anchors.centerIn: parent
                name: "navigation"
                size: 20
                color: MColors.marathonTeal
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    HapticService.medium();
                    if (mapsApp.bestCoordValid) {
                        mapCall("setCenter", mapsApp.bestCoord.latitude, mapsApp.bestCoord.longitude, 15);
                        Logger.info("Maps", "Centered on current location (" + (mapsApp.geoclueValid ? "Geoclue" : "QtPositioning") + ")");
                    } else {
                        Logger.warn("Maps", "Position not available");
                        // Re-arm Geoclue in case the user denied earlier or
                        // the daemon dropped its client.
                        if (typeof LocationService !== "undefined" && LocationService)
                            LocationService.start();
                    }
                }
            }
        }

        // ── Place card (JSX ref-maps bottom chrome) ───────────
        // Visible only when a search result is selected. 64×64 teal
        // gradient bay + place name + meta (address) + ★rating +
        // four-action row: Directions (teal accent) · Call · Share · Save.
        Rectangle {
            id: placeCard
            visible: mapsApp.selectedPlace !== null && mapsApp.routingMode === "idle"
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

            MTopHairline {
                radius: parent.radius
                color: MColors.whiteOverlay04
                lineWidth: 1
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
                            onClicked: {
                                HapticService.light();
                                if (modelData.label === "Directions" && mapsApp.selectedPlace && mapsApp.bestCoordValid) {
                                    routingService.requestRoute(mapsApp.bestCoord.latitude, mapsApp.bestCoord.longitude, mapsApp.selectedPlace.lat, mapsApp.selectedPlace.lon, mapsApp.currentMode);
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Route preview card ─────────────────────────────────
        // Visible while routingMode === "preview". Replaces the place
        // card with an ETA + distance summary, mode toggle, and a
        // primary "Start" button to enter active navigation.
        Rectangle {
            id: previewCard
            visible: mapsApp.routingMode === "preview"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 12
            height: 196
            radius: MRadius.md
            color: MColors.elev2
            border.width: 1
            border.color: MColors.tealBorder
            z: 95

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                Row {
                    width: parent.width
                    spacing: 16
                    Column {
                        width: parent.width - 100
                        spacing: 2
                        Text {
                            text: {
                                if (!mapsApp.currentRoute)
                                    return "";
                                const m = Math.round(mapsApp.currentRoute.duration / 60);
                                if (m < 60)
                                    return m + " min";
                                const h = Math.floor(m / 60);
                                return h + "h " + (m % 60) + "m";
                            }
                            color: MColors.marathonTealBright
                            font.family: MTypography.fontFamily
                            font.pixelSize: 28
                            font.weight: Font.Medium
                            font.letterSpacing: -0.5
                        }
                        Text {
                            text: mapsApp.currentRoute ? (mapsApp.currentRoute.distance / 1000).toFixed(1) + " km · via " + (mapsApp.currentRoute.maneuvers && mapsApp.currentRoute.maneuvers.length > 1 ? (mapsApp.currentRoute.maneuvers[1].streetNames || "fastest route") : "fastest route") : ""
                            color: MColors.textSecondary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeFootnote
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }
                    Item {
                        width: 80
                        height: 56
                        anchors.verticalCenter: parent.verticalCenter
                        Icon {
                            anchors.centerIn: parent
                            name: mapsApp.currentMode === "pedestrian" ? "user" : mapsApp.currentMode === "bicycle" ? "bicycle" : "navigation"
                            size: 48
                            color: MColors.marathonTeal
                            opacity: 0.55
                        }
                    }
                }

                // Mode toggle row — auto / pedestrian / bicycle
                Row {
                    spacing: 8
                    Repeater {
                        model: [
                            {
                                mode: "auto",
                                label: "Drive",
                                icon: "navigation"
                            },
                            {
                                mode: "pedestrian",
                                label: "Walk",
                                icon: "user"
                            },
                            {
                                mode: "bicycle",
                                label: "Bike",
                                icon: "bicycle"
                            }
                        ]
                        delegate: Rectangle {
                            width: 100
                            height: 36
                            radius: MRadius.md
                            color: mapsApp.currentMode === modelData.mode ? MColors.marathonTealGlow : MColors.glassTitlebar
                            border.width: 1
                            border.color: mapsApp.currentMode === modelData.mode ? MColors.tealBorder : MColors.whiteOverlay08
                            Row {
                                anchors.centerIn: parent
                                spacing: 6
                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: modelData.icon
                                    size: 14
                                    color: mapsApp.currentMode === modelData.mode ? MColors.marathonTealBright : MColors.textSecondary
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.label
                                    color: mapsApp.currentMode === modelData.mode ? MColors.marathonTealBright : MColors.textSecondary
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: MTypography.sizeFootnote
                                    font.weight: Font.Medium
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    HapticService.light();
                                    mapsApp.currentMode = modelData.mode;
                                    if (mapsApp.selectedPlace && mapsApp.bestCoordValid)
                                        routingService.requestRoute(mapsApp.bestCoord.latitude, mapsApp.bestCoord.longitude, mapsApp.selectedPlace.lat, mapsApp.selectedPlace.lon, mapsApp.currentMode);
                                }
                            }
                        }
                    }
                }

                // Primary Start button + secondary Cancel
                Row {
                    width: parent.width
                    spacing: 8
                    Rectangle {
                        width: (parent.width - 8) * 0.7
                        height: 48
                        radius: MRadius.md
                        gradient: Gradient {
                            GradientStop {
                                position: 0
                                color: Qt.rgba(0, 191 / 255, 165 / 255, 1.0)
                            }
                            GradientStop {
                                position: 1
                                color: Qt.rgba(0, 138 / 255, 119 / 255, 1.0)
                            }
                        }
                        border.width: 1
                        border.color: MColors.tealBorder
                        Row {
                            anchors.centerIn: parent
                            spacing: 8
                            Icon {
                                name: "navigation"
                                size: 18
                                color: "#040404"
                            }
                            Text {
                                text: "Start"
                                color: "#040404"
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeBody
                                font.weight: Font.Medium
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                HapticService.medium();
                                mapsApp.startNavigation();
                            }
                        }
                    }
                    Rectangle {
                        width: parent.width * 0.3 - 8
                        height: 48
                        radius: MRadius.md
                        color: MColors.glassTitlebar
                        border.width: 1
                        border.color: MColors.whiteOverlay08
                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: MColors.textSecondary
                            font.family: MTypography.fontFamily
                            font.pixelSize: MTypography.sizeBody
                            font.weight: Font.Medium
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                HapticService.light();
                                mapsApp.endNavigation();
                                mapsApp.selectedPlace = null;
                            }
                        }
                    }
                }
            }
        }

        // ── Active navigation banner ───────────────────────────
        // Top-of-screen glass banner that replaces the search bar
        // during turn-by-turn. Big distance + maneuver icon on the
        // left, instruction text on the right. Tap to expand the full
        // maneuver list sheet.
        Rectangle {
            id: navBanner
            visible: mapsApp.routingMode === "active"
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 12
            height: 84
            radius: MRadius.md
            color: MColors.glassTitlebar
            border.width: 1
            border.color: MColors.tealBorder
            z: 110

            Row {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 14
                Item {
                    width: 56
                    height: 56
                    anchors.verticalCenter: parent.verticalCenter
                    Icon {
                        anchors.centerIn: parent
                        name: {
                            if (!mapsApp.currentRoute || !mapsApp.currentRoute.maneuvers)
                                return "navigation";
                            const m = mapsApp.currentRoute.maneuvers[mapsApp.currentManeuverIndex];
                            if (!m)
                                return "navigation";
                            // Valhalla maneuver type codes:
                            // 10 = right, 15 = left, 20 = sharp right, 11 = slight right, etc.
                            const t = m.type;
                            if (t === 10 || t === 11 || t === 20)
                                return "corner-up-right";
                            if (t === 15 || t === 16 || t === 19)
                                return "corner-up-left";
                            if (t === 4 || t === 5 || t === 6)
                                return "flag";  // arrival
                            return "navigation";
                        }
                        size: 36
                        color: MColors.marathonTealBright
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 56 - parent.spacing
                    spacing: 4
                    Text {
                        text: {
                            if (!mapsApp.currentRoute || !mapsApp.currentRoute.maneuvers)
                                return "";
                            const m = mapsApp.currentRoute.maneuvers[mapsApp.currentManeuverIndex];
                            if (!m)
                                return "";
                            const meters = Math.round((m.length || 0) * 1000);
                            if (meters < 30)
                                return "Now";
                            if (meters < 1000)
                                return meters + " m";
                            return (meters / 1000).toFixed(1) + " km";
                        }
                        color: MColors.marathonTealBright
                        font.family: MTypography.fontFamily
                        font.pixelSize: 22
                        font.weight: Font.Medium
                        font.letterSpacing: -0.3
                    }
                    Text {
                        text: {
                            if (!mapsApp.currentRoute || !mapsApp.currentRoute.maneuvers)
                                return "";
                            const m = mapsApp.currentRoute.maneuvers[mapsApp.currentManeuverIndex];
                            return m ? m.instruction : "";
                        }
                        color: MColors.textPrimary
                        font.family: MTypography.fontFamily
                        font.pixelSize: MTypography.sizeFootnote
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: maneuverSheet.visible = true
            }
        }

        // End-nav pill, bottom-right while in active mode
        Rectangle {
            visible: mapsApp.routingMode === "active"
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 16
            width: 88
            height: 44
            radius: MRadius.md
            color: Qt.rgba(0.95, 0.25, 0.25, 0.85)
            border.width: 1
            border.color: Qt.rgba(1, 0.4, 0.4, 0.5)
            z: 105
            Text {
                anchors.centerIn: parent
                text: "End"
                color: "white"
                font.family: MTypography.fontFamily
                font.pixelSize: MTypography.sizeBody
                font.weight: Font.Medium
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    HapticService.medium();
                    mapsApp.endNavigation();
                }
            }
        }

        // Full maneuver list sheet — tap the nav banner to bring up.
        Rectangle {
            id: maneuverSheet
            visible: false
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.85)
            z: 200

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: parent.height * 0.7
                radius: MRadius.md
                color: MColors.elev2
                border.width: 1
                border.color: MColors.whiteOverlay08

                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 8
                    Row {
                        width: parent.width
                        Text {
                            text: "Directions"
                            color: MColors.textPrimary
                            font.family: MTypography.fontFamily
                            font.pixelSize: 20
                            font.weight: Font.Medium
                            width: parent.width - 60
                        }
                        Rectangle {
                            width: 60
                            height: 32
                            radius: MRadius.md
                            color: "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: "Close"
                                color: MColors.marathonTealBright
                                font.family: MTypography.fontFamily
                                font.pixelSize: MTypography.sizeFootnote
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: maneuverSheet.visible = false
                            }
                        }
                    }
                    ListView {
                        width: parent.width
                        height: parent.height - 48
                        clip: true
                        model: mapsApp.currentRoute ? mapsApp.currentRoute.maneuvers : []
                        delegate: Item {
                            width: parent.width
                            height: 56
                            Row {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 12
                                Text {
                                    width: 60
                                    text: modelData.length < 1 ? Math.round(modelData.length * 1000) + " m" : modelData.length.toFixed(1) + " km"
                                    color: MColors.marathonTealBright
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: MTypography.sizeFootnote
                                    font.weight: Font.Medium
                                    verticalAlignment: Text.AlignVCenter
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    width: parent.width - 60 - parent.spacing
                                    text: modelData.instruction
                                    color: index === mapsApp.currentManeuverIndex ? MColors.textPrimary : MColors.textSecondary
                                    font.family: MTypography.fontFamily
                                    font.pixelSize: MTypography.sizeBody
                                    font.weight: index === mapsApp.currentManeuverIndex ? Font.Medium : Font.Normal
                                    wrapMode: Text.WordWrap
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                z: -1
                onClicked: maneuverSheet.visible = false
            }
        }
    }
}
