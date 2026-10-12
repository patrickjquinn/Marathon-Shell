pragma ComponentBehavior: Bound
import QtQuick
import Sailfish.Silica 1.0
import Marathon.Silica 1.0
import "../components"

// Categories, then the top-charts list.
TabItem {
    id: root

    property var store

    flickable: flick

    SilicaFlickable {
        id: flick

        objectName: "appsView"
        anchors.fill: parent
        contentHeight: column.height + Theme.paddingLarge

        Column {
            id: column

            width: parent.width

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
                visible: root.store.topApps.length > 0
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
