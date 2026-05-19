import QtQuick

Item {
    id: filteredModel

    property var filteredApps: []
    property int count: filteredApps.length
    property var sourceModel: AppModel
    property var hiddenApps: SettingsManagerCpp.hiddenApps
    property string sortOrder: SettingsManagerCpp.appSortOrder
    property bool showNotificationBadges: SettingsManagerCpp.showNotificationBadges
    // Curated home-grid order. When set, the model emits these apps in this
    // exact order and DROPS everything else — that's the DS HomePage1
    // contract (screens-shell.jsx ships 16 specific apps in 4×4). The App
    // Drawer surface uses a separate alphabetical model. Default list mirrors
    // the JSX HomePage1 ordering, substituting installed Marathon apps for
    // the brand-only slots (mi/wallet/health) that don't ship as separate
    // app bundles yet.
    property var pinnedAppIds: ["phone", "messages", "email", "browser", "store", "music", "camera", "gallery", "maps", "calendar", "clock", "calculator", "notes", "settings"]
    property bool pinnedMode: true

    signal dataChanged

    function requestRebuild() {
        if (debounceTimer.running)
            debounceTimer.restart();
        else
            debounceTimer.start();
    }

    function rebuildFilteredList() {
        var apps = [];
        // Pinned mode: lookup each id in the source model and emit in order.
        // Drop entries that don't resolve so we don't render empty cells
        // when a built-in app is missing from this build.
        if (pinnedMode && pinnedAppIds && pinnedAppIds.length > 0) {
            var indexById = {};
            for (var k = 0; k < sourceModel.count; k++) {
                var src = sourceModel.getAppAtIndex(k);
                if (src && src.id)
                    indexById[src.id] = src;
            }
            for (var j = 0; j < pinnedAppIds.length; j++) {
                var id = pinnedAppIds[j];
                var hit = indexById[id];
                if (hit && hiddenApps.indexOf(id) < 0)
                    apps.push(hit);
            }
            filteredApps = apps;
            dataChanged();
            Logger.info("FilteredAppModel", "Rebuilt (pinned): " + filteredApps.length + " of " + pinnedAppIds.length + " requested (source has " + sourceModel.count + ")");
            return;
        }
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
