pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0
import MarathonApp.Settings
import "../SettingsLogic.js" as Logic

Page {
    id: page

    property string appId
    readonly property var app: Apps.getApp(appId) || ({})
    readonly property var notifications: (SettingsController.notificationApps || []).find(a => a.id === page.appId)

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

            PageHeader {
                objectName: "header"
                title: page.app.name || page.appId
            }
            DetailItem {
                objectName: "versionItem"
                visible: !!page.app.version
                label: qsTr("Version")
                value: page.app.version || ""
            }
            DetailItem {
                objectName: "kindItem"
                label: qsTr("Type")
                value: page.app.isProtected ? qsTr("System app") : qsTr("Installed app")
            }
            TextSwitch {
                objectName: "notifySwitch"
                visible: page.notifications !== undefined
                text: qsTr("Notifications")
                description: qsTr("Show this app's notifications")
                automaticCheck: false
                checked: page.notifications !== undefined && page.notifications.enabled
                onClicked: SettingsController.setNotificationEnabled(page.appId, !checked)
            }

            SectionHeader {
                text: qsTr("Permissions")
            }
            Repeater {
                objectName: "permissions"
                model: page.app.permissions || []

                TextSwitch {
                    id: permissionSwitch

                    required property string modelData

                    function refresh() {
                        checked = Permissions.hasPermission(page.appId, modelData);
                    }

                    objectName: "permission-" + modelData
                    text: Logic.permissionInfo(modelData).title
                    description: Logic.permissionInfo(modelData).description
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
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
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
