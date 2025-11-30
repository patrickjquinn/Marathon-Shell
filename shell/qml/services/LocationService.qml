pragma Singleton
import QtQuick

QtObject {
    id: locationService

    property bool locationEnabled: false
    property bool hasPermission: false
    property string accuracy: "high"

    property real latitude: 0.0
    property real longitude: 0.0
    property real altitude: 0.0
    property real accuracy_meters: 0.0
    property real heading: 0.0
    property real speed: 0.0

    property string lastUpdate: ""
    property bool isUpdating: false

    signal locationChanged(real lat, real lon, real accuracy)
    signal locationError(string error)
    signal permissionChanged(bool granted)

    function enable() {
        enableLocation();
    }

    function enableLocation() {
        console.log("[LocationService] Enabling location services...");
        locationEnabled = true;
        _platformEnableLocation();
        startUpdating();
    }

    function disableLocation() {
        console.log("[LocationService] Disabling location services...");
        locationEnabled = false;
        stopUpdating();
        _platformDisableLocation();
    }

    function requestPermission() {
        console.log("[LocationService] Requesting location permission...");
        _platformRequestPermission();
    }

    function startUpdating() {
        if (!locationEnabled) {
            console.warn("[LocationService] Location not enabled");
            return;
        }

        if (!hasPermission) {
            console.warn("[LocationService] No location permission");
            requestPermission();
            return;
        }

        console.log("[LocationService] Starting location updates...");
        isUpdating = true;
        locationUpdateTimer.start();
        _platformStartUpdating();
    }

    function stopUpdating() {
        console.log("[LocationService] Stopping location updates...");
        isUpdating = false;
        locationUpdateTimer.stop();
        _platformStopUpdating();
    }

    function setAccuracy(accuracyLevel) {
        if (["low", "medium", "high"].indexOf(accuracyLevel) === -1) {
            console.warn("[LocationService] Invalid accuracy level:", accuracyLevel);
            return;
        }

        console.log("[LocationService] Setting accuracy:", accuracyLevel);
        accuracy = accuracyLevel;
        _platformSetAccuracy(accuracyLevel);
    }

    function getCurrentPosition() {
        return {
            latitude: latitude,
            longitude: longitude,
            altitude: altitude,
            accuracy: accuracy_meters,
            heading: heading,
            speed: speed,
            timestamp: lastUpdate
        };
    }

    function _platformEnableLocation() {
        if (Platform.isLinux) {
            console.log("[LocationService] Enabling via GeoClue D-Bus");
        } else if (Platform.isMacOS) {
            console.log("[LocationService] macOS CoreLocation");
        }
    }

    function _platformDisableLocation() {
        if (Platform.isLinux) {
            console.log("[LocationService] Disabling GeoClue");
        }
    }

    function _platformRequestPermission() {
        if (Platform.isLinux || Platform.isMacOS) {
            console.log("[LocationService] Requesting location permission via PermissionManager");
            // Request permission via system permission manager
            // The appId is "shell" since LocationService is a system service
            if (typeof PermissionManager !== 'undefined') {
                PermissionManager.requestPermission("shell", "location");
            } else {
                console.warn("[LocationService] PermissionManager not available, auto-granting");
                hasPermission = true;
                permissionChanged(true);
            }
        }
    }

    // Listen for permission responses
    property var _permissionConnections: Connections {
        target: typeof PermissionManager !== 'undefined' ? PermissionManager : null

        function onPermissionGranted(appId, permission) {
            if (appId === "shell" && permission === "location") {
                console.log("[LocationService] Location permission granted");
                hasPermission = true;
                permissionChanged(true);
                // Auto-start location updates if enabled
                if (locationEnabled) {
                    startUpdating();
                }
            }
        }

        function onPermissionDenied(appId, permission) {
            if (appId === "shell" && permission === "location") {
                console.log("[LocationService] Location permission denied");
                hasPermission = false;
                permissionChanged(false);
                locationEnabled = false;
            }
        }
    }

    function _platformStartUpdating() {
        if (Platform.isLinux) {
            console.log("[LocationService] D-Bus call to GeoClue Start");
        }
    }

    function _platformStopUpdating() {
        if (Platform.isLinux) {
            console.log("[LocationService] D-Bus call to GeoClue Stop");
        }
    }

    function _platformSetAccuracy(accuracyLevel) {
        var level = 0;
        switch (accuracyLevel) {
        case "low":
            level = 4;
            break;
        case "medium":
            level = 6;
            break;
        case "high":
            level = 8;
            break;
        }

        if (Platform.isLinux) {
            console.log("[LocationService] GeoClue accuracy level:", level);
        }
    }

    function _simulateLocationUpdate() {
        latitude += (Math.random() - 0.5) * 0.001;
        longitude += (Math.random() - 0.5) * 0.001;
        altitude = 100 + Math.random() * 50;
        accuracy_meters = 10 + Math.random() * 20;
        heading = Math.random() * 360;
        speed = Math.random() * 10;
        lastUpdate = new Date().toISOString();

        locationChanged(latitude, longitude, accuracy_meters);
    }

    property Timer locationUpdateTimer: Timer {
        interval: 5000
        repeat: true
        running: false
        onTriggered: {
            if (Platform.isLinux || Platform.isMacOS) {} else {
                _simulateLocationUpdate();
            }
        }
    }

    Component.onCompleted: {
        console.log("[LocationService] Initialized");
        console.log("[LocationService] GeoClue available:", Platform.isLinux);

        latitude = 37.7749;
        longitude = -122.4194;
    }
}
