pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import MarathonApp.Settings
import "../SettingsLogic.js" as Logic

Page {
    id: page

    // Names by package, kept for the notice after the app has left the list.
    property var removing: ({})

    function uninstall(pkg, name) {
        const next = Object.assign({}, removing);
        next[pkg] = name;
        removing = next;
        AndroidApps.uninstall(pkg);
    }

    objectName: "androidAppsPage"
    Component.onCompleted: AndroidApps.refresh()

    Connections {
        target: AndroidApps

        function onDone(pkg, action) {
            if (action === "uninstall" && page.removing[pkg] !== undefined)
                Notices.show(qsTr("%1 uninstalled").arg(page.removing[pkg]));
        }
        function onFailed(pkg, action, error) {
            if (action === "uninstall" && page.removing[pkg] !== undefined)
                Notices.show(qsTr("Couldn't uninstall %1: %2").arg(page.removing[pkg]).arg(error));
        }
    }

    SilicaListView {
        id: view

        objectName: "androidAppList"
        anchors.fill: parent
        model: AndroidApps.apps
        header: PageHeader {
            title: qsTr("Android apps")
            description: qsTr("%n apps", "", view.count)
        }

        delegate: AppRow {
            required property var modelData

            appId: modelData.id
            name: modelData.name
            icon: modelData.icon || ""
            subtitle: modelData.version ? qsTr("Version %1").arg(modelData.version) : ""
            canUninstall: Logic.androidRemovable(modelData.pkg)
            onUninstallRequested: page.uninstall(modelData.pkg, modelData.name)
            onClicked: pageStack.push(Qt.resolvedUrl("AppInfoPage.qml"), { appId: modelData.id })
        }

        ViewPlaceholder {
            objectName: "noApps"
            enabled: view.count === 0
            text: qsTr("No Android apps")
            hintText: qsTr("Android apps you install from the Store appear here")
        }

        VerticalScrollDecorator {}
    }
}
