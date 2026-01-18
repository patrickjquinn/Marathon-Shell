import QtQuick

Item {
    id: filteredModel

    property var filteredApps: []
    property int count: filteredApps.length
    property var sourceModel: AppModel
    property var hiddenApps: SettingsManagerCpp.hiddenApps
    property string sortOrder: SettingsManagerCpp.appSortOrder
    property bool showNotificationBadges: SettingsManagerCpp.showNotificationBadges

    signal dataChanged

    function requestRebuild() {
        if (debounceTimer.running)
            debounceTimer.restart();
        else
            debounceTimer.start();
    }

    function rebuildFilteredList() {
        var apps = [];
        for (var i = 0; i < sourceModel.count; i++) {
            var app = sourceModel.getAppAtIndex(i);
            if (!app)
                continue;

            if (hiddenApps.indexOf(app.id) >= 0)
                continue;

            apps.push(app);
        }
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

    function getAppAtIndex(index) {
        if (index < 0 || index >= filteredApps.length)
            return null;

        return filteredApps[index];
    }

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
