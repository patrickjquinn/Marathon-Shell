pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import MarathonApp.Settings

Page {
    id: page

    property string appId
    readonly property var app: Apps.getApp(appId) || ({})
    readonly property var notifications: (SettingsController.notificationApps || []).find(a => a.id === page.appId)
    // Restricted permissions are held only by protected system apps.
    readonly property var refused: page.app.isProtected ? [] : (page.app.permissions || []).filter(p => !!Permissions.describe(p).restricted)
    // Android apps ("waydroid.<package>") get their details from Android.
    readonly property bool android: appId.startsWith("waydroid.")
    readonly property string pkg: android ? appId.substring(9) : ""
    property var androidApp: ({})

    Component.onCompleted: {
        if (android)
            AndroidApps.loadApp(pkg);
    }

    // The app is gone (removed here or elsewhere): once, and only from the top.
    property bool leaving: false
    function leave() {
        if (leaving)
            return;
        leaving = true;
        if (pageStack.currentPage === page)
            pageStack.pop();
    }

    RemorsePopup {
        id: remorse
    }

    Connections {
        target: page.android ? AndroidApps : null

        function onAppLoaded(pkg, app) {
            if (pkg === page.pkg)
                page.androidApp = app;
        }
        function onAppChanged(pkg) {
            if (pkg === page.pkg)
                AndroidApps.loadApp(pkg);
        }
        function onAppRemoved(pkg) {
            if (pkg === page.pkg)
                page.leave();
        }
        function onDone(pkg, action) {
            if (pkg !== page.pkg)
                return;
            if (action === "uninstall") {
                Notices.show(qsTr("%1 uninstalled").arg(page.androidApp.label || page.pkg));
                page.leave();
            } else if (action === "forceStop") {
                Notices.show(qsTr("%1 stopped").arg(page.androidApp.label || page.pkg));
            } else if (action === "clearData" || action === "clearCache") {
                AndroidApps.loadApp(pkg);
            }
        }
        function onFailed(pkg, action, error) {
            if (pkg !== page.pkg || page.leaving)
                return;
            Notices.show(qsTr("Couldn't do that: %1").arg(error));
            if (action !== "loadApp" && action !== "uninstall")
                AndroidApps.loadApp(pkg);
        }
    }

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            objectName: "androidPulley"
            visible: page.android

            MenuItem {
                objectName: "uninstallItem"
                text: qsTr("Uninstall")
                onClicked: remorse.execute(qsTr("Uninstalling %1").arg(page.androidApp.label || page.pkg), () => AndroidApps.uninstall(page.pkg))
            }
            MenuItem {
                objectName: "forceStopItem"
                text: qsTr("Force stop")
                onClicked: AndroidApps.forceStop(page.pkg)
            }
        }

        Column {
            id: column

            width: parent.width

            PageHeader {
                objectName: "header"
                title: page.app.name || page.androidApp.label || page.appId
            }
            AndroidAppDetails {
                width: parent.width
                visible: page.android
                pkg: page.pkg
                app: page.androidApp
                remorse: remorse
            }
            DetailItem {
                objectName: "versionItem"
                visible: !page.android && !!page.app.version
                label: qsTr("Version")
                value: page.app.version || ""
            }
            DetailItem {
                objectName: "kindItem"
                visible: !page.android
                label: qsTr("Type")
                value: page.app.isProtected ? qsTr("System app") : qsTr("Installed app")
            }
            TextSwitch {
                objectName: "notifySwitch"
                visible: !page.android && page.notifications !== undefined
                text: qsTr("Notifications")
                description: qsTr("Show this app's notifications")
                automaticCheck: false
                checked: page.notifications !== undefined && page.notifications.enabled
                onClicked: SettingsController.setNotificationEnabled(page.appId, !checked)
            }

            SectionHeader {
                visible: !page.android
                text: qsTr("Permissions")
            }
            Repeater {
                objectName: "permissions"
                model: (page.app.permissions || []).filter(p => !page.refused.includes(p))

                TextSwitch {
                    id: permissionSwitch

                    required property string modelData

                    function refresh() {
                        checked = Permissions.hasPermission(page.appId, modelData);
                    }

                    objectName: "permission-" + modelData
                    text: Permissions.describe(modelData).label
                    description: Permissions.describe(modelData).description
                    automaticCheck: false
                    enabled: !page.app.isProtected
                    Component.onCompleted: refresh()
                    onClicked: {
                        if (Permissions.setPermission(page.appId, modelData, !checked))
                            checked = !checked;
                    }

                    Connections {
                        target: Permissions

                        function onPermissionGranted(appId, permission) {
                            if (appId === page.appId && permission === permissionSwitch.modelData)
                                permissionSwitch.checked = true;
                        }
                        function onPermissionDenied(appId, permission) {
                            if (appId === page.appId && permission === permissionSwitch.modelData)
                                permissionSwitch.checked = false;
                        }
                    }
                }
            }
            SectionHeader {
                objectName: "notAllowedHeader"
                visible: page.refused.length > 0
                text: qsTr("Not allowed")
            }
            Repeater {
                objectName: "refusedPermissions"
                model: page.refused

                Column {
                    id: refusedRow

                    required property string modelData
                    readonly property string label: Permissions.describe(modelData).label
                    readonly property string description: qsTr("Only Marathon's system apps can have this")

                    objectName: "refused-" + modelData
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    topPadding: Theme.paddingSmall
                    bottomPadding: Theme.paddingSmall
                    opacity: Theme.opacityHigh

                    Label {
                        width: parent.width
                        text: refusedRow.label
                        wrapMode: Text.Wrap
                    }
                    Label {
                        width: parent.width
                        text: refusedRow.description
                        wrapMode: Text.Wrap
                        font.pixelSize: Theme.fontSizeExtraSmall
                        color: Theme.secondaryColor
                    }
                }
            }
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                visible: !page.android
                topPadding: Theme.paddingMedium
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryHighlightColor
                text: (page.app.permissions || []).length === 0 ? qsTr("This app doesn't use any permissions.") : page.app.isProtected ? qsTr("System apps always have these permissions.") : qsTr("Apps ask for these permissions the first time they need them.")
            }
        }

        VerticalScrollDecorator {}
    }
}
