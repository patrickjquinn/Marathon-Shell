import MarathonOS.Shell 1.0
import QtQuick
import Sailfish.Silica 1.0 as Silica

Item {
    id: contextMenu

    property var appData: null
    readonly property string appId: appData ? (appData.id || "") : ""
    readonly property bool removable: appId !== "" && typeof MarathonAppInstaller !== "undefined" && MarathonAppInstaller.canUninstall(appId)

    function show(app, pos) {
        appData = app;
        menu.x = Math.min(Math.max(pos.x - menu.width / 2, Silica.Theme.paddingLarge), width - menu.width - Silica.Theme.paddingLarge);
        menu.y = Math.max(pos.y - menu.height - Silica.Theme.paddingSmall, Constants.statusBarHeight + Silica.Theme.paddingLarge);
        visible = true;
        menu.opacity = 1;
    }

    function hide() {
        menu.opacity = 0;
    }

    anchors.fill: parent
    visible: false
    z: 2550

    MouseArea {
        anchors.fill: parent
        onClicked: contextMenu.hide()
    }

    Rectangle {
        id: menu

        width: Math.round(contextMenu.width * 0.6)
        height: menuColumn.height
        radius: Silica.Theme.paddingMedium
        color: Silica.Theme.rgba("black", 0.85)
        border.width: 1
        border.color: Silica.Theme.rgba(Silica.Theme.primaryColor, 0.1)
        clip: true
        opacity: 0
        onOpacityChanged: if (opacity === 0) contextMenu.visible = false

        Behavior on opacity {
            NumberAnimation { duration: MMotion.quick; easing.type: Easing.OutQuad }
        }

        Column {
            id: menuColumn

            width: parent.width

            MenuEntry {
                text: qsTr("App info")
                onActivated: AppLaunchService.launchAppWithRoute("settings", "appmanager", "", null, null)
            }

            MenuEntry {
                visible: contextMenu.removable
                text: qsTr("Uninstall")
                onActivated: {
                    const id = contextMenu.appId;
                    UIStore.showConfirmDialog(qsTr("Uninstall %1?").arg(contextMenu.appData.name), qsTr("This app will be removed from your device."), function () {
                        MarathonAppInstaller.uninstallApp(id);
                    });
                }
            }
        }
    }

    component MenuEntry: Rectangle {
        id: entry

        property alias text: label.text
        signal activated

        width: menuColumn.width
        height: Silica.Theme.itemSizeSmall
        color: area.pressed ? Silica.Theme.rgba(Silica.Theme.highlightBackgroundColor, Silica.Theme.highlightBackgroundOpacity) : "transparent"

        Silica.Label {
            id: label

            anchors.centerIn: parent
            color: area.pressed ? Silica.Theme.highlightColor : Silica.Theme.primaryColor
        }

        MouseArea {
            id: area

            anchors.fill: parent
            onClicked: {
                HapticManager.light();
                contextMenu.hide();
                entry.activated();
            }
        }
    }
}
