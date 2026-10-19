pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import MarathonApp.Settings

// Every app that asks for one permission, Marathon's and Android's in one list.
Page {
    id: page

    property string permission
    property var androidApps: []
    // Bumped when Marathon's grants change, so the rows read them again.
    property int revision: 0
    readonly property var rows: {
        revision;
        const marathon = (Apps.getAllAppIds() || []).map(id => Apps.getApp(id)).filter(a => a && (a.permissions || []).indexOf(page.permission) >= 0).map(a => ({
                    id: a.id,
                    name: a.name || a.id,
                    android: false,
                    granted: !!a.isProtected || Permissions.hasPermission(a.id, page.permission),
                    fixed: !!a.isProtected,
                    note: a.isProtected ? qsTr("System app") : ""
                }));
        const android = page.androidApps.map(a => ({
                    id: "waydroid." + a.pkg,
                    pkg: a.pkg,
                    name: a.label,
                    android: true,
                    granted: !!a.granted,
                    fixed: !!a.fixed,
                    note: qsTr("Android app")
                }));
        return marathon.concat(android).sort((x, y) => x.name.localeCompare(y.name));
    }

    function loadAndroid() {
        AndroidApps.loadPermissionApps(permission);
    }

    function toggle(row) {
        if (row.android) {
            AndroidApps.setPermission(row.pkg, permission, !row.granted);
            return;
        }
        Permissions.setPermission(row.id, permission, !row.granted);
        revision++;
    }

    objectName: "permissionAppsPage"
    Component.onCompleted: loadAndroid()

    Connections {
        target: AndroidApps

        function onPermissionAppsLoaded(permission, apps) {
            if (permission === page.permission)
                page.androidApps = apps;
        }
        function onAppChanged(pkg) {
            page.loadAndroid();
        }
        function onAppRemoved(pkg) {
            page.loadAndroid();
        }
        function onFailed(pkg, action, error) {
            if (action === "setPermission" && page.androidApps.some(a => a.pkg === pkg)) {
                Notices.show(qsTr("Couldn't change that: %1").arg(error));
                page.loadAndroid();
            }
        }
    }

    Connections {
        target: Permissions

        function onPermissionGranted(appId, permission) {
            page.revision++;
        }
        function onPermissionDenied(appId, permission) {
            page.revision++;
        }
    }

    SilicaListView {
        id: view

        objectName: "appList"
        anchors.fill: parent
        model: page.rows
        header: Column {
            width: view.width

            PageHeader {
                title: Permissions.describe(page.permission).label
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                bottomPadding: Theme.paddingMedium
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: Permissions.describe(page.permission).description
            }
        }

        delegate: TextSwitch {
            required property var modelData

            objectName: "app-" + modelData.id
            text: modelData.name
            description: modelData.note
            automaticCheck: false
            checked: modelData.granted
            enabled: !modelData.fixed
            onClicked: page.toggle(modelData)
        }

        ViewPlaceholder {
            objectName: "noApps"
            enabled: view.count === 0
            text: qsTr("No apps ask for this")
        }

        VerticalScrollDecorator {}
    }
}
