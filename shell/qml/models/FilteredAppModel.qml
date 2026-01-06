import QtQuick

Item {
    // TODO: Implement usage tracking
    // For now, fall back to alphabetical
    // TODO: Implement install date tracking
    // For now, fall back to alphabetical

    id: filteredModel

    // Expose the filtered list
    property var filteredApps: []
    property int count: filteredApps.length
    // React to source model changes
    property var sourceModel: AppModel
    // React to settings changes
    property var hiddenApps: SettingsManagerCpp.hiddenApps
    property string sortOrder: SettingsManagerCpp.appSortOrder
    property bool showNotificationBadges: SettingsManagerCpp.showNotificationBadges

    // Note: countChanged() signal is automatically generated for the 'count' property
    signal dataChanged

    // Request a rebuild (debounced)
    function requestRebuild() {
        if (debounceTimer.running)
            debounceTimer.restart();
        else
            debounceTimer.start();
    }

    // Rebuild the filtered list
    function rebuildFilteredList() {
        var apps = [];
        // Step 1: Filter out hidden apps
        for (var i = 0; i < sourceModel.count; i++) {
            var app = sourceModel.getAppAtIndex(i);
            if (!app)
                continue;

            // Check if app is hidden
            if (hiddenApps.indexOf(app.id) >= 0)
                continue;

            apps.push(app);
        }
        // Step 2: Sort based on preference
        if (sortOrder === "alphabetical")
            apps.sort(function (a, b) {
                return a.name.localeCompare(b.name);
            });
        else if (sortOrder === "frequent")
            apps.sort(function (a, b) {
                return a.name.localeCompare(b.name);
            });
        else if (sortOrder === "recent")
            apps.sort(function (a, b) {
                return a.name.localeCompare(b.name);
            });
        filteredApps = apps;
        dataChanged();
        Logger.info("FilteredAppModel", "Rebuilt: " + filteredApps.length + " apps (filtered from " + sourceModel.count + ")");
    }

    // Get app at index
    function getAppAtIndex(index) {
        if (index < 0 || index >= filteredApps.length)
            return null;

        return filteredApps[index];
    }

    // Get app by ID
    function getApp(appId) {
        for (var i = 0; i < filteredApps.length; i++) {
            if (filteredApps[i].id === appId)
                return filteredApps[i];
        }
        return null;
    }

    Component.onCompleted: {
        requestRebuild();
        Logger.info("FilteredAppModel", "Initialized");
    }

    // Debounce timer to prevent "thundering herd" updates
    Timer {
        id: debounceTimer

        interval: 50
        repeat: false
        onTriggered: filteredModel.rebuildFilteredList()
    }

    Connections {
        function onCountChanged() {
            filteredModel.requestRebuild();
        }

        function onDataChanged() {
            filteredModel.requestRebuild();
        }

        target: AppModel
    }

    Connections {
        function onHiddenAppsChanged() {
            filteredModel.hiddenApps = SettingsManagerCpp.hiddenApps;
            filteredModel.requestRebuild();
        }

        function onAppSortOrderChanged() {
            filteredModel.sortOrder = SettingsManagerCpp.appSortOrder;
            filteredModel.requestRebuild();
        }

        target: SettingsManagerCpp
    }
}
