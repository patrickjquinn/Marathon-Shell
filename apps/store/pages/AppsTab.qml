pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../components"

// Categories, then the top-charts list.
TabItem {
    id: root

    property var store
    property real topMargin

    flickable: flick

    SilicaFlickable {
        id: flick

        objectName: "appsView"
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem {
                objectName: "refreshItem"
                text: qsTr("Refresh")
                onClicked: root.store.loadCatalog()
            }
        }

        Column {
            id: column

            width: parent.width

            Item {
                width: 1
                height: root.topMargin
            }

            SectionHeader {
                text: qsTr("Categories")
            }
            Repeater {
                objectName: "categoryRows"
                model: root.store.categories
                delegate: ListItem {
                    id: category

                    required property var modelData

                    width: column.width
                    Accessible.name: modelData.label
                    onClicked: root.store.openCategory(modelData.id, modelData.label)

                    Icon {
                        id: categoryIcon
                        x: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        source: "image://theme/icon-m-" + category.modelData.icon
                        highlighted: category.highlighted
                    }
                    Label {
                        anchors.left: categoryIcon.right
                        anchors.leftMargin: Theme.paddingLarge
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        text: category.modelData.label
                        color: category.highlighted ? Theme.highlightColor : Theme.primaryColor
                        truncationMode: TruncationMode.Fade
                    }
                }
            }

            SectionHeader {
                text: qsTr("Top charts")
                visible: root.store.topApps.length > 0 || !root.store.catalogLoading
            }
            Label {
                objectName: "chartsNote"
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                bottomPadding: Theme.paddingMedium
                visible: text !== ""
                text: root.store.showingSavedCatalog ? qsTr("Offline. Showing apps saved %1.").arg(root.store.timeAgo(root.store.catalogSavedAt)) : root.store.topApps.length === 0 && !root.store.catalogLoading ? qsTr("Couldn't reach Flathub. Check your connection.") : ""
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.Wrap
            }
            Repeater {
                objectName: "topCharts"
                model: root.store.topApps
                delegate: AppRow {
                    required property var modelData
                    required property int index
                    width: column.width
                    store: root.store
                    app: modelData
                    rank: index + 1
                }
            }
        }

        VerticalScrollDecorator {}
    }
}
