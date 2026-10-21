pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import MarathonOS.Settings 1.0
import "../SettingsLogic.js" as Logic

Page {
    id: page

    // Names by app id, kept for the notice after the app has left the list.
    property var removing: ({})
    // Set by the "appmanager/<appId>" route: that app's page opens over the list.
    property string focusAppId

    function showApp(appId) {
        pageStack.push(Qt.resolvedUrl("AppInfoPage.qml"), { appId: appId });
    }

    onStatusChanged: {
        if (status === PageStatus.Active && focusAppId !== "") {
            const id = focusAppId;
            focusAppId = "";
            showApp(id);
        }
    }

    function uninstall(appId, name) {
        const next = Object.assign({}, removing);
        next[appId] = name;
        removing = next;
        AppInstaller.uninstallApp(appId);
    }

    function uninstallAndroid(pkg, name) {
        const next = Object.assign({}, removing);
        next["waydroid." + pkg] = name;
        removing = next;
        AndroidApps.uninstall(pkg);
    }

    Connections {
        target: AndroidApps

        function onDone(pkg, action) {
            if (action === "uninstall" && page.removing["waydroid." + pkg] !== undefined)
                Notices.show(qsTr("%1 uninstalled").arg(page.removing["waydroid." + pkg]));
        }
        function onFailed(pkg, action, error) {
            if (action === "uninstall" && page.removing["waydroid." + pkg] !== undefined)
                Notices.show(qsTr("Couldn't uninstall %1: %2").arg(page.removing["waydroid." + pkg]).arg(error));
        }
    }

    Connections {
        target: AppInstaller

        function onUninstallComplete(appId) {
            Notices.show(qsTr("%1 uninstalled").arg(page.removing[appId] || appId));
        }
        function onUninstallFailed(appId, error) {
            Notices.show(qsTr("Couldn't uninstall %1: %2").arg(page.removing[appId] || appId).arg(error));
        }
    }

    SilicaListView {
        id: view

        objectName: "appList"
        anchors.fill: parent
        model: Apps
        header: PageHeader {
            title: qsTr("Installed apps")
            description: qsTr("%n apps", "", view.count + AndroidApps.apps.length)
        }

        delegate: AppRow {
            required property var model

            appId: model.id
            name: model.name
            icon: model.icon || ""
            subtitle: [model.version ? qsTr("Version %1").arg(model.version) : "", model.isProtected ? qsTr("System app") : ""].filter(t => t !== "").join(" · ")
            Accessible.name: model.name + (model.isProtected ? ", " + qsTr("system app") : "")
            canUninstall: AppInstaller.canUninstall(model.id)
            onUninstallRequested: page.uninstall(model.id, model.name)
            onClicked: page.showApp(model.id)
        }

        // Android apps follow Marathon's, as rows of the same kind.
        footer: Column {
            width: parent ? parent.width : 0

            Repeater {
                objectName: "androidApps"
                model: AndroidApps.apps

                AppRow {
                    required property var modelData

                    width: parent.width
                    appId: modelData.id
                    name: modelData.name
                    icon: modelData.icon || ""
                    subtitle: [modelData.version ? qsTr("Version %1").arg(modelData.version) : "", qsTr("Android app")].filter(t => t !== "").join(" · ")
                    Accessible.name: modelData.name + ", " + qsTr("Android app")
                    canUninstall: Logic.androidRemovable(modelData.pkg)
                    onUninstallRequested: page.uninstallAndroid(modelData.pkg, modelData.name)
                    onClicked: page.showApp(modelData.id)
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
