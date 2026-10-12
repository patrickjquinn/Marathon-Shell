pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../components"

// Pending updates first, then everything installed from Flathub.
TabItem {
    id: root

    property var store
    property real topMargin

    flickable: flick
    Component.onCompleted: store.refreshState()

    SilicaFlickable {
        id: flick

        objectName: "installedView"
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem {
                text: qsTr("Update all")
                visible: root.store.updateApps.length > 0
                onClicked: root.store.updateAll()
            }
            MenuItem {
                text: qsTr("Refresh")
                onClicked: root.store.refreshState()
            }
        }

        ViewPlaceholder {
            objectName: "installedPlaceholder"
            enabled: root.store.installedApps.length === 0 && root.store.updateApps.length === 0
            text: qsTr("No apps installed yet")
            hintText: qsTr("Apps you get from the Store appear here, with their updates")
        }

        Column {
            id: column

            width: parent.width

            Item {
                width: 1
                height: root.topMargin
            }

            SectionHeader {
                text: root.store.updateApps.length === 1 ? qsTr("1 update") : qsTr("%1 updates").arg(root.store.updateApps.length)
                visible: root.store.updateApps.length > 0
            }
            Repeater {
                objectName: "updateRows"
                model: root.store.updateApps
                delegate: AppRow {
                    required property var modelData
                    width: column.width
                    store: root.store
                    app: modelData
                }
            }

            SectionHeader {
                text: qsTr("On this phone")
                visible: installedRows.count > 0
            }
            Repeater {
                id: installedRows

                objectName: "installedRows"
                model: root.store.installedApps.filter(a => !root.store.hasUpdate(a.app_id))
                delegate: AppRow {
                    required property var modelData
                    width: column.width
                    store: root.store
                    app: modelData
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
