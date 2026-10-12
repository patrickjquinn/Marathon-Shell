pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import Marathon.Platform 1.0

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
            description: qsTr("%n apps", "", view.count)
        }

        delegate: ListItem {
            id: item

            required property var model

            // The menu is gone by the time the remorse timer ends, so the callback lives here.
            function uninstall() {
                const id = model.id;
                const name = model.name;
                remorseDelete(() => page.uninstall(id, name));
            }

            objectName: "app-" + model.id
            contentHeight: Theme.itemSizeMedium
            Accessible.name: model.name + (model.isProtected ? ", " + qsTr("system app") : "")
            menu: item.model.isProtected ? null : uninstallMenu
            onClicked: page.showApp(item.model.id)

            Component {
                id: uninstallMenu

                ContextMenu {
                    MenuItem {
                        objectName: "uninstallItem"
                        text: qsTr("Uninstall")
                        onClicked: item.uninstall()
                    }
                }
            }

            Image {
                id: icon

                x: Theme.horizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.iconSizeMedium
                height: Theme.iconSizeMedium
                sourceSize: Qt.size(width, height)
                source: item.model.icon || ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }
            Icon {
                anchors.centerIn: icon
                visible: icon.status !== Image.Ready
                source: "image://theme/icon-m-apps"
            }
            Column {
                anchors {
                    left: icon.right
                    leftMargin: Theme.paddingLarge
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }

                Label {
                    width: parent.width
                    text: item.model.name
                    truncationMode: TruncationMode.Fade
                    color: item.highlighted ? Theme.highlightColor : Theme.primaryColor
                }
                Label {
                    width: parent.width
                    text: item.model.isProtected ? qsTr("Version %1 · system app").arg(item.model.version || "1.0.0") : qsTr("Version %1").arg(item.model.version || "1.0.0")
                    font.pixelSize: Theme.fontSizeExtraSmall
                    truncationMode: TruncationMode.Fade
                    color: item.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
